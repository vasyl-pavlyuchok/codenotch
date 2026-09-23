/* audience: machine */
#import "ClaudeOAuthUsage.h"
#import <Security/Security.h>

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

/* A fallback reader that went through /usr/bin/security to keep the Fable row
 * alive was written on 23-sep-2026 and WITHDRAWN the same night, before ever
 * being built. It is deliberately not in this file. See README-VP.md,
 * "Known limitation: the Fable row", for what it did and what it would take
 * to adopt it. */
+ (nullable NSDictionary *)readKeychainCredentialData {
    /* Belt: no dialog may ever originate from this process. Called here
     * rather than only at launch so it holds no matter which path gets here
     * first. dispatch_once makes it free after the first call. */
    [self disableKeychainUserInteraction];

    /* Braces: once a read has failed, stop hammering. Without this the app
     * would re-run a read it knows will fail on every single poll. */
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
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = (NSDictionary *)obj;
    NSDictionary *oauth = dict[@"claudeAiOauth"];
    if (![oauth isKindOfClass:[NSDictionary class]]) return nil;
    NSString *accessToken = oauth[@"accessToken"];
    if (![accessToken isKindOfClass:[NSString class]] || accessToken.length == 0) return nil;
    return oauth;
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

    NSDictionary *credential = [self readKeychainCredentialData];
    NSString *accessToken = credential[@"accessToken"];
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
                        [rows addObject:[[VPLimitRow alloc] initWithLabel:@"Fable esta semana · límite propio"
                                                               usedPercent:percentNum.doubleValue
                                                                  resetsAt:resetsAt]];
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

+ (nullable NSString *)planLabel {
    NSDictionary *credential = [self readKeychainCredentialData];
    /* Keychain unreadable (partition list reset by the CLI's token refresh,
     * breaker open, item missing...). Fall back to the last value we really
     * read rather than emptying the field on the user. */
    if (!credential) return [self cachedPlanLabel];

    /* "default_claude_max_5x" -> "Max 5x". Strips the constant prefix, then
     * title-cases each remaining underscore-separated word; a multiplier
     * like "5x" is left as-is since capitalizedString only touches letters. */
    NSString *tier = credential[@"rateLimitTier"];
    if ([tier isKindOfClass:[NSString class]] && tier.length > 0) {
        NSString *stripped = tier;
        NSString *prefix = @"default_claude_";
        if ([stripped hasPrefix:prefix]) stripped = [stripped substringFromIndex:prefix.length];
        NSMutableArray<NSString *> *words = [NSMutableArray array];
        for (NSString *part in [stripped componentsSeparatedByString:@"_"]) {
            if (part.length > 0) [words addObject:part.capitalizedString];
        }
        if (words.count > 0) return [self rememberPlanLabel:[words componentsJoinedByString:@" "]];
    }

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
