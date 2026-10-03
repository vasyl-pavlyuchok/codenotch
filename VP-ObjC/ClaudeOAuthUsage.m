/* audience: machine */
#import "ClaudeOAuthUsage.h"
#import <Security/Security.h>
#import <signal.h>

static NSString *const kVPOAuthEndpoint = @"https://api.anthropic.com/api/oauth/usage";
static const NSTimeInterval kVPMinPollInterval = 60.0;

@implementation VPClaudeOAuthUsage

/* All mutable poll state (lastAttempt, backoffUntil, consecutive429,
 * loggedMissingFable) lives behind this private serial queue — review fix
 * #2. Every read and every write happens inside a block submitted to this
 * queue, so the background URLSession callback can never race a concurrent
 * poll() call or another callback. */
+ (dispatch_queue_t)stateQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("io.techbooster.codenotch-vp.claude-oauth-usage.state", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

/* Backing storage for the queue-protected state. Never touch these ivars
 * outside a block submitted to +stateQueue. */
static NSDate *_Nullable gLastAttempt = nil;
static NSDate *_Nullable gBackoffUntil = nil;
static NSInteger gConsecutive429 = 0;
static BOOL gLoggedMissingFable = NO;
/* Circuit breaker for the keychain itself (see +readKeychainCredentialData). */
static NSDate *_Nullable gKeychainBlockedUntil = nil;
static BOOL gLoggedKeychainBlocked = NO;

/* How long to stop touching the keychain after a read fails. The failure we
 * expect (partition-list mismatch) is not transient — it persists until the
 * user re-authorises the item — so retrying every 60s buys nothing and only
 * burns cycles. */
static const NSTimeInterval kVPKeychainBackoff = 30 * 60;

#pragma mark - Keychain

/* THE fix for the repeated password dialog (VP05, 23-sep-2026). Measured, not
 * assumed — see README-VP.md "The password dialog" for the full A/B.
 *
 * `Claude Code-credentials` lives in the LEGACY file-based login keychain
 * (login.keychain-db). Its access control has two independent layers: the
 * classic ACL app list, and the newer *partition list*. Every time the
 * `claude` CLI refreshes its OAuth token it REWRITES that item, and the
 * rewrite resets the partition list to `apple-tool:` only — proven from
 * securityd's own log on 22/23-sep: the list held
 * ("apple-tool:","apple:","codesign:") at 18:39:42 and just ("apple-tool:")
 * from 00:46:21 onward, with no `security` command run in between. Codenotch
 * VP is signed with a local certificate, so it is never in that list, and
 * every read after a refresh logs `ACL partition mismatch` and then
 * `displaying keychain prompt`. NO amount of ACL/partition tinkering fixes
 * this for good: the next token refresh wipes it again. (Worse: setting the
 * partition list by hand to "apple-tool:,apple:,codesign:" on 22-sep made it
 * fire on nearly every 60s poll instead of occasionally.)
 *
 * `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail` does NOT suppress
 * this dialog — that attribute governs the iOS-style data-protection
 * keychain (Touch ID / passcode-protected keys), not the legacy ACL prompt.
 * Measured: with and without the flag the behaviour was byte-identical.
 *
 * The legacy switch that DOES govern it is this one. With it off,
 * SecItemCopyMatching returns errSecAuthFailed (-25293) immediately instead
 * of putting a window on the user's screen. Measured 23-sep-2026 with a probe
 * signed by the same "Codenotch VP Signing" identity, against the same
 * mismatched partition list, 30 seconds apart:
 *   interaction allowed  ->  1 mismatch,  1 `displaying keychain prompt`,  1 SecurityAgent
 *   interaction disabled -> 60 mismatches, 0 prompts,                      0 SecurityAgent
 *
 * This is process-global and permanent for our lifetime. That is exactly what
 * we want: NOTHING in this app may ever put a keychain dialog on screen. The
 * app is a passive read-only status widget; if it cannot read the item it
 * hides the rows it cannot fill, it never interrupts the user. */
+ (void)disableKeychainUserInteraction {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* Deprecated by Apple in favour of the data-protection keychain, but
         * this item IS a legacy file-keychain item and this is the only API
         * that governs its prompt. Still fully functional on macOS 14
         * (measured 23-sep-2026). Scoped pragma so the rest of the build
         * keeps its deprecation warnings. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        OSStatus status = SecKeychainSetUserInteractionAllowed(FALSE);
#pragma clang diagnostic pop
        if (status != errSecSuccess) {
            /* Never fatal: worst case we are back to today's behaviour. */
            fprintf(stderr, "codenotch-vp: SecKeychainSetUserInteractionAllowed(FALSE) failed, OSStatus %d\n", (int)status);
        }
    });
}

/* PRIMARY reader (VP06, 24-sep-2026 — the CEO's direct decision in session,
 * after the 23-sep withdrawal documented in README-VP.md "The Fable row").
 *
 * Why a helper process: the item's partition list is reset to `apple-tool:`
 * by every CLI token refresh (see above), and NOTHING signed by us will ever
 * be in that list for long. `/usr/bin/security` IS an Apple tool, so it reads
 * the item in exactly the state where our own SecItemCopyMatching is refused
 * — verified 23-sep-2026: exit 0, 0 prompts, 0 partition mismatches.
 *
 * Contract: never hangs (hard deadline, then SIGKILL), never shows a dialog
 * (stdin is /dev/null, so `security` cannot prompt), never logs or persists
 * the secret (logs carry a byte count or an exit status only), never throws.
 * On any failure it returns nil and the caller falls back to the Keychain API
 * path below, which keeps its own 30-minute breaker. */
static const NSTimeInterval kVPSecurityToolDeadline = 2.0;
static BOOL gLoggedSecurityToolState = NO;   /* one-shot per state change, on +stateQueue */
static BOOL gSecurityToolLastOK = NO;

+ (nullable NSData *)readCredentialViaSecurityTool {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/security"];
    task.arguments = @[ @"find-generic-password",
                        @"-s", @"Claude Code-credentials",
                        @"-a", NSUserName(),
                        @"-w" ];
    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];

    /* Set BEFORE launch so a process that exits instantly still signals. */
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *_Nonnull t) { dispatch_semaphore_signal(finished); };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [self noteSecurityToolResult:NO detail:[NSString stringWithFormat:@"launch failed (%ld)", (long)launchError.code]];
        return nil;
    }

    /* Drain stdout off-thread so a full pipe can never stall the child. */
    __block NSData *output = nil;
    dispatch_group_t drain = dispatch_group_create();
    NSFileHandle *reader = [stdoutPipe fileHandleForReading];
    dispatch_group_async(drain, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        output = [reader readDataToEndOfFile];
    });

    long timedOut = dispatch_semaphore_wait(finished,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVPSecurityToolDeadline * NSEC_PER_SEC)));
    if (timedOut != 0) {
        kill(task.processIdentifier, SIGKILL);
        [task waitUntilExit];
        [self noteSecurityToolResult:NO detail:@"deadline exceeded, killed"];
        return nil;
    }
    dispatch_group_wait(drain, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)));

    if (task.terminationStatus != 0 || output.length == 0) {
        [self noteSecurityToolResult:NO detail:[NSString stringWithFormat:@"exit %d, %lu bytes",
                                                (int)task.terminationStatus, (unsigned long)output.length]];
        return nil;
    }

    /* `-w` prints the secret followed by a newline; strip trailing whitespace. */
    const uint8_t *bytes = output.bytes;
    NSUInteger len = output.length;
    while (len > 0 && (bytes[len - 1] == '\n' || bytes[len - 1] == '\r' || bytes[len - 1] == ' ')) len--;
    NSData *trimmed = [output subdataWithRange:NSMakeRange(0, len)];
    [self noteSecurityToolResult:YES detail:[NSString stringWithFormat:@"ok (%lu bytes)", (unsigned long)trimmed.length]];
    return trimmed;
}

/* One line per state change (ok <-> failing), never per poll, never the data. */
+ (void)noteSecurityToolResult:(BOOL)ok detail:(NSString *)detail {
    __block BOOL shouldLog = NO;
    dispatch_sync([self stateQueue], ^{
        if (!gLoggedSecurityToolState || gSecurityToolLastOK != ok) {
            gLoggedSecurityToolState = YES;
            gSecurityToolLastOK = ok;
            shouldLog = YES;
        }
    });
    if (shouldLog) {
        fprintf(stderr, "codenotch-vp: security tool path: %s\n", detail.UTF8String);
    }
}

/* Shared tail of both readers: the item is a JSON blob whose `claudeAiOauth`
 * object carries `accessToken`. Anything else -> nil, never a throw. */
+ (nullable NSDictionary *)oauthDictFromCredentialData:(NSData *)data {
    if (data.length == 0) return nil;
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *oauth = ((NSDictionary *)obj)[@"claudeAiOauth"];
    if (![oauth isKindOfClass:[NSDictionary class]]) return nil;
    NSString *accessToken = oauth[@"accessToken"];
    if (![accessToken isKindOfClass:[NSString class]] || accessToken.length == 0) return nil;
    return oauth;
}

+ (nullable NSString *)longLivedTokenFromFile {
    NSString *path = [NSHomeDirectory() stringByAppendingString:@"/.claude/state/codenotch-token"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

+ (nullable NSDictionary *)readKeychainCredentialData {
    /* Belt: no dialog may ever originate from this process. Called here
     * rather than only at launch so it holds no matter which path gets here
     * first. dispatch_once makes it free after the first call. */
    [self disableKeychainUserInteraction];

    /* 1. Primary: the Apple-signed helper. Cheap, so it may run on every poll
     *    (the poll itself is already throttled to every 15 minutes). */
    NSData *viaTool = [self readCredentialViaSecurityTool];
    if (viaTool) {
        NSDictionary *oauth = [self oauthDictFromCredentialData:viaTool];
        if (oauth) return oauth;
    }

    /* 2. Fallback: our own Keychain API read, with its breaker. This is the
     *    pre-VP06 path, unchanged: it succeeds only while the partition list
     *    happens to include us, and backs off 30 minutes when it does not. */
    NSDate *now = [NSDate date];
    __block BOOL blocked = NO;
    dispatch_sync([self stateQueue], ^{
        blocked = (gKeychainBlockedUntil && [gKeychainBlockedUntil compare:now] == NSOrderedDescending);
    });
    if (blocked) return nil;

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"Claude Code-credentials",
        (__bridge id)kSecAttrAccount: NSUserName(),
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        /* Kept deliberately. It does not suppress the legacy ACL prompt (see
         * above) but it is still correct for the data-protection keychain, and
         * removing it would silently widen what this query is willing to do. */
        (__bridge id)kSecUseAuthenticationUI: (__bridge id)kSecUseAuthenticationUIFail
    };
    CFTypeRef item = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &item);

    if (status != errSecSuccess || item == NULL) {
        __block BOOL shouldLog = NO;
        dispatch_sync([self stateQueue], ^{
            gKeychainBlockedUntil = [NSDate dateWithTimeIntervalSinceNow:kVPKeychainBackoff];
            if (!gLoggedKeychainBlocked) {
                gLoggedKeychainBlocked = YES;
                shouldLog = YES;
            }
        });
        if (shouldLog) {
            fprintf(stderr,
                    "codenotch-vp: keychain read failed (OSStatus %d) — no dialog was shown, "
                    "backing off %.0f min. The session/weekly rows keep working from "
                    "~/.claude/state/usage-5h.json; the Fable row and the plan label stay on "
                    "their last known value until the item is readable again.\n",
                    (int)status, kVPKeychainBackoff / 60.0);
        }
        return nil;
    }
    /* A good read clears the breaker and re-arms the one-shot log. */
    dispatch_sync([self stateQueue], ^{
        gKeychainBlockedUntil = nil;
        gLoggedKeychainBlocked = NO;
    });
    NSData *data = (__bridge_transfer NSData *)item;
    return [self oauthDictFromCredentialData:data];
}

#pragma mark - Fable row cache

/* Same idea and same mechanism as +rememberPlanLabel: NSUserDefaults, not the
 * in-memory-only array VPUsageCoordinator used to rely on exclusively
 * (AppDelegate.m's `oauthRows`, reset to empty by every relaunch). Stored as
 * three primitives rather than an archived VPLimitRow so this file does not
 * need VPLimitRow to adopt NSSecureCoding for one small cache. */
static NSString *const kVPFableRowPercentDefaultsKey = @"VPLastKnownFablePercent";
static NSString *const kVPFableRowResetsAtDefaultsKey = @"VPLastKnownFableResetsAt";
static NSString *const kVPFableRowCachedAtDefaultsKey = @"VPLastKnownFableCachedAt";
static const NSTimeInterval kVPFableRowStaleAfter = 30 * 60; /* matches VPClaudeUsageFile.staleAfter */

+ (void)rememberFableRow:(VPLimitRow *)row {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:row.usedPercent forKey:kVPFableRowPercentDefaultsKey];
    if (row.resetsAt) {
        [defaults setDouble:row.resetsAt.timeIntervalSince1970 forKey:kVPFableRowResetsAtDefaultsKey];
    } else {
        [defaults removeObjectForKey:kVPFableRowResetsAtDefaultsKey];
    }
    [defaults setDouble:[NSDate date].timeIntervalSince1970 forKey:kVPFableRowCachedAtDefaultsKey];
}

+ (nullable NSDate *)cachedFableRowTimestamp {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kVPFableRowCachedAtDefaultsKey]) return nil;
    return [NSDate dateWithTimeIntervalSince1970:[defaults doubleForKey:kVPFableRowCachedAtDefaultsKey]];
}

+ (nullable VPLimitRow *)cachedFableRow {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kVPFableRowPercentDefaultsKey]) return nil;
    double percent = [defaults doubleForKey:kVPFableRowPercentDefaultsKey];
    NSDate *resetsAt = [defaults objectForKey:kVPFableRowResetsAtDefaultsKey]
        ? [NSDate dateWithTimeIntervalSince1970:[defaults doubleForKey:kVPFableRowResetsAtDefaultsKey]]
        : nil;
    /* The weekly window this reading belonged to already reset: the percentage
     * describes a week that no longer exists, so showing it (even marked
     * stale) is a wrong number, not an old one. Better no row than that.
     * (2-oct-2026: the card showed 69 % cached on 29-sep for a week that had
     * reset 3 days earlier.) */
    if (resetsAt && [resetsAt timeIntervalSinceNow] < 0) return nil;
    return [[VPLimitRow alloc] initWithLabel:@"Fable esta semana · límite propio"
                                  usedPercent:percent
                                     resetsAt:resetsAt];
}

+ (BOOL)cachedFableRowIsStale {
    NSDate *cachedAt = [self cachedFableRowTimestamp];
    if (!cachedAt) return YES;
    return [[NSDate date] timeIntervalSinceDate:cachedAt] > kVPFableRowStaleAfter;
}

#pragma mark - Date parsing

+ (nullable NSDate *)parseISO8601:(NSString *)text {
    static NSISO8601DateFormatter *withFraction;
    static NSISO8601DateFormatter *plain;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        withFraction = [[NSISO8601DateFormatter alloc] init];
        withFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        plain = [[NSISO8601DateFormatter alloc] init];
        plain.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    NSDate *date = [withFraction dateFromString:text];
    if (!date) date = [plain dateFromString:text];
    return date;
}

#pragma mark - Poll

+ (void)pollWithCompletion:(void (^)(NSArray<VPLimitRow *> *))completion {
    NSDate *now = [NSDate date];

    /* Atomic check-and-set of the throttle/backoff state, and snapshot of
     * whether we've already logged the "no Fable window" message, all
     * inside one block on the serial state queue. */
    __block BOOL shouldSkip = NO;
    dispatch_sync([self stateQueue], ^{
        if (gBackoffUntil && [gBackoffUntil compare:now] == NSOrderedDescending) {
            shouldSkip = YES;
            return;
        }
        if (gLastAttempt && [now timeIntervalSinceDate:gLastAttempt] < kVPMinPollInterval) {
            shouldSkip = YES;
            return;
        }
        gLastAttempt = now;
    });
    if (shouldSkip) {
        completion(@[]);
        return;
    }

    /* A 1-year token from `claude setup-token`, stored by the user in a 0600
     * file, wins over the keychain: it needs no keychain access at all and does
     * not empty itself when the CLI logs out (29-sep-2026: the keychain item had
     * accessToken "" / expiresAt 0 while the desktop app kept working). */
    NSDictionary *credential = [self readKeychainCredentialData];
    NSString *accessToken = credential[@"accessToken"];
    BOOL usedTokenFile = NO;
    if (!accessToken.length) {
        accessToken = [self longLivedTokenFromFile];
        usedTokenFile = accessToken.length > 0;
    }
    if (!accessToken.length) {
        completion(@[]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kVPOAuthEndpoint]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"oauth-2025-04-20" forHTTPHeaderField:@"anthropic-beta"];
    request.timeoutInterval = 15;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];

            if (status == 429) {
                __block NSTimeInterval wait = 60;
                dispatch_sync([self stateQueue], ^{
                    gConsecutive429 += 1;
                    NSTimeInterval floorSec = 60, ceiling = 15 * 60;
                    NSInteger exponent = MIN(gConsecutive429, 4);
                    wait = MIN(ceiling, floorSec * pow(2.0, (double)exponent));
                    gBackoffUntil = [NSDate dateWithTimeIntervalSinceNow:wait];
                });
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }
            dispatch_sync([self stateQueue], ^{ gConsecutive429 = 0; });

            if (error != nil || status < 200 || status >= 300 || data == nil) {
                if (status == 401 || status == 403) {
                    fprintf(stderr, "codenotch-vp: /api/oauth/usage answered HTTP %ld using the %s\n",
                            (long)status, usedTokenFile ? "token file (this token type may lack the usage scope)" : "keychain token");
                }
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }

            NSError *jsonError = nil;
            id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (![payload isKindOfClass:[NSDictionary class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }
            NSArray *limits = ((NSDictionary *)payload)[@"limits"];
            if (![limits isKindOfClass:[NSArray class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }

            /* Confirmed live 18-sep-2026: `limits` holds one entry per kind —
             * "session" (the 5h row -- CEO-reported bug, 18-sep-2026: the
             * local file (VPClaudeUsageFile) that used to cover this row is
             * dead, nothing has written it in over a day, so its frozen
             * resets_at drifted into the past and the relative countdown
             * showed "↻0m" instead of a real value; this live call replaces
             * it as the row's source of truth), "weekly_all" (the second
             * row), and "weekly_scoped" with scope.model.display_name ==
             * "Fable" (the third row). The API already returns them in this
             * same order, matching the approved design. */
            NSMutableArray<VPLimitRow *> *rows = [NSMutableArray array];
            for (id item in limits) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *limit = (NSDictionary *)item;
                NSString *kind = [limit[@"kind"] isKindOfClass:[NSString class]] ? limit[@"kind"] : @"";
                NSString *resetsAtText = [limit[@"resets_at"] isKindOfClass:[NSString class]] ? limit[@"resets_at"] : nil;
                NSDate *resetsAt = resetsAtText ? [self parseISO8601:resetsAtText] : nil;
                NSNumber *percentNum = [limit[@"percent"] isKindOfClass:[NSNumber class]] ? limit[@"percent"] : nil;
                if (!resetsAt || !percentNum) continue;

                if ([kind isEqualToString:@"session"]) {
                    [rows addObject:[[VPLimitRow alloc] initWithLabel:@"Sesión actual"
                                                           usedPercent:percentNum.doubleValue
                                                              resetsAt:resetsAt]];
                    continue;
                }
                if ([kind isEqualToString:@"weekly_all"]) {
                    [rows addObject:[[VPLimitRow alloc] initWithLabel:@"Esta semana · todos los modelos"
                                                           usedPercent:percentNum.doubleValue
                                                              resetsAt:resetsAt]];
                    continue;
                }
                if ([kind isEqualToString:@"weekly_scoped"]) {
                    NSString *displayName = @"";
                    id scope = limit[@"scope"];
                    if ([scope isKindOfClass:[NSDictionary class]]) {
                        id model = ((NSDictionary *)scope)[@"model"];
                        if ([model isKindOfClass:[NSDictionary class]]) {
                            id name = ((NSDictionary *)model)[@"display_name"];
                            if ([name isKindOfClass:[NSString class]]) displayName = name;
                        }
                    }
                    if ([displayName rangeOfString:@"fable" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        VPLimitRow *fableRow = [[VPLimitRow alloc] initWithLabel:@"Fable esta semana · límite propio"
                                                                      usedPercent:percentNum.doubleValue
                                                                         resetsAt:resetsAt];
                        [rows addObject:fableRow];
                        [self rememberFableRow:fableRow];
                    }
                }
            }

            if (rows.count == 0) {
                __block BOOL shouldLog = NO;
                dispatch_sync([self stateQueue], ^{
                    if (!gLoggedMissingFable) {
                        gLoggedMissingFable = YES;
                        shouldLog = YES;
                    }
                });
                if (shouldLog) {
                    fprintf(stderr, "codenotch-vp: no weekly_all/weekly_scoped window in /api/oauth/usage response — hiding those bars\n");
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(rows); });
        }];
    [task resume];
}

#pragma mark - Plan label

/* Last successfully-read plan label, persisted so a keychain outage (or a
 * relaunch during one) shows the last thing we actually read instead of
 * blanking the field. Never a guess: only a value the keychain really gave
 * us at some point is ever stored or returned. */
static NSString *const kVPPlanLabelDefaultsKey = @"VPLastKnownPlanLabel";

+ (nullable NSString *)cachedPlanLabel {
    NSString *cached = [[NSUserDefaults standardUserDefaults] stringForKey:kVPPlanLabelDefaultsKey];
    return cached.length > 0 ? cached : nil;
}

+ (nullable NSString *)rememberPlanLabel:(nullable NSString *)label {
    if (label.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:label forKey:kVPPlanLabelDefaultsKey];
        return label;
    }
    return [self cachedPlanLabel];
}

/* "default_claude_max_5x" -> "Max 5x", "claude_pro" -> "Pro". Strips the
 * constant prefix, then upper-cases only the FIRST letter of each remaining
 * underscore-separated word. Not capitalizedString: it treats the digit as a
 * word boundary and turned "5x" into "5X" (seen on screen 23-sep-2026).
 * nil for anything that is not a string or leaves nothing behind. */
+ (nullable NSString *)labelFromTier:(nullable id)tier {
    if (![tier isKindOfClass:[NSString class]] || [tier length] == 0) return nil;
    NSString *stripped = tier;
    for (NSString *prefix in @[@"default_claude_", @"claude_"]) {
        if ([stripped hasPrefix:prefix]) {
            stripped = [stripped substringFromIndex:prefix.length];
            break;
        }
    }
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *part in [stripped componentsSeparatedByString:@"_"]) {
        if (part.length > 0) {
            [words addObject:[[part substringToIndex:1].uppercaseString
                              stringByAppendingString:[part substringFromIndex:1]]];
        }
    }
    return words.count > 0 ? [words componentsJoinedByString:@" "] : nil;
}

/* CEO-reported bug, 23-sep-2026: after a /logout + /login the plan label
 * stayed on the old plan forever. The login rewrites the keychain item, which
 * resets its partition list and locks this app out (see
 * +disableKeychainUserInteraction), so +planLabel fell back to the cached
 * value every time. ~/.claude.json carries the same plan in
 * oauthAccount.organizationRateLimitTier / organizationType, the CLI rewrites
 * it on every login, and reading it needs no keychain and no network. It is
 * now the primary source; the keychain is only a fallback. */
+ (nullable NSString *)planLabelFromClaudeConfig {
    NSString *path = [NSHomeDirectory() stringByAppendingString:@"/.claude.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    id account = ((NSDictionary *)obj)[@"oauthAccount"];
    if (![account isKindOfClass:[NSDictionary class]]) return nil;

    /* The rate-limit tier carries the multiplier ("Max 5x" vs "Max 20x"), so
     * it wins when it names a Max plan. Other tiers are not self-describing
     * (a Pro account's tier is not "..._pro"), so for those the
     * organization type ("claude_pro" -> "Pro") is the honest label. */
    for (NSString *key in @[@"userRateLimitTier", @"organizationRateLimitTier"]) {
        id tier = account[key];
        if ([tier isKindOfClass:[NSString class]] && [tier containsString:@"max"]) {
            NSString *label = [self labelFromTier:tier];
            if (label) return label;
        }
    }
    return [self labelFromTier:account[@"organizationType"]];
}

+ (nullable NSString *)planLabel {
    NSString *fromConfig = [self planLabelFromClaudeConfig];
    if (fromConfig) return [self rememberPlanLabel:fromConfig];

    NSDictionary *credential = [self readKeychainCredentialData];
    /* Keychain unreadable (partition list reset by the CLI's token refresh,
     * breaker open, item missing...). Fall back to the last value we really
     * read rather than emptying the field on the user. */
    if (!credential) return [self cachedPlanLabel];

    NSString *fromTier = [self labelFromTier:credential[@"rateLimitTier"]];
    if (fromTier) return [self rememberPlanLabel:fromTier];

    NSString *subscriptionType = credential[@"subscriptionType"];
    if ([subscriptionType isKindOfClass:[NSString class]] && subscriptionType.length > 0) {
        return [self rememberPlanLabel:subscriptionType.capitalizedString];
    }
    return [self cachedPlanLabel];
}

#pragma mark - Account email

+ (nullable NSString *)accountEmail {
    NSString *path = [NSHomeDirectory() stringByAppendingString:@"/.claude.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    id account = ((NSDictionary *)obj)[@"oauthAccount"];
    if (![account isKindOfClass:[NSDictionary class]]) return nil;
    NSString *email = ((NSDictionary *)account)[@"emailAddress"];
    return [email isKindOfClass:[NSString class]] && email.length > 0 ? email : nil;
}

@end
