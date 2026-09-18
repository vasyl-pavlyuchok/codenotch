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

#pragma mark - Keychain

+ (nullable NSDictionary *)readKeychainCredentialData {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"Claude Code-credentials",
        (__bridge id)kSecAttrAccount: NSUserName(),
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecUseAuthenticationUI: (__bridge id)kSecUseAuthenticationUIFail
    };
    CFTypeRef item = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &item);
    if (status != errSecSuccess || item == NULL) {
        if (status != errSecItemNotFound) {
            fprintf(stderr, "codenotch-vp: keychain read for Fable usage failed, OSStatus %d\n", (int)status);
        }
        return nil;
    }
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

+ (nullable NSString *)planLabel {
    NSDictionary *credential = [self readKeychainCredentialData];
    if (!credential) return nil;

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
        if (words.count > 0) return [words componentsJoinedByString:@" "];
    }

    NSString *subscriptionType = credential[@"subscriptionType"];
    if ([subscriptionType isKindOfClass:[NSString class]] && subscriptionType.length > 0) {
        return subscriptionType.capitalizedString;
    }
    return nil;
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
