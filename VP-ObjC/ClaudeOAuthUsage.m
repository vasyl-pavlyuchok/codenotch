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

+ (void)pollWithCompletion:(void (^)(VPLimitRow *_Nullable))completion {
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
        completion(nil);
        return;
    }

    NSDictionary *credential = [self readKeychainCredentialData];
    NSString *accessToken = credential[@"accessToken"];
    if (!accessToken.length) {
        completion(nil);
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
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }
            dispatch_sync([self stateQueue], ^{ gConsecutive429 = 0; });

            if (error != nil || status < 200 || status >= 300 || data == nil) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }

            NSError *jsonError = nil;
            id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (![payload isKindOfClass:[NSDictionary class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }
            NSArray *limits = ((NSDictionary *)payload)[@"limits"];
            if (![limits isKindOfClass:[NSArray class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }

            NSDictionary *fable = nil;
            for (id item in limits) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *limit = (NSDictionary *)item;
                NSString *kind = [limit[@"kind"] isKindOfClass:[NSString class]] ? limit[@"kind"] : @"";
                NSString *displayName = @"";
                id scope = limit[@"scope"];
                if ([scope isKindOfClass:[NSDictionary class]]) {
                    id model = ((NSDictionary *)scope)[@"model"];
                    if ([model isKindOfClass:[NSDictionary class]]) {
                        id name = ((NSDictionary *)model)[@"display_name"];
                        if ([name isKindOfClass:[NSString class]]) displayName = name;
                    }
                }
                if ([kind rangeOfString:@"fable" options:NSCaseInsensitiveSearch].location != NSNotFound
                    || [displayName rangeOfString:@"fable" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    fable = limit;
                    break;
                }
            }

            NSString *resetsAtText = fable ? fable[@"resets_at"] : nil;
            NSDate *resetsAt = [resetsAtText isKindOfClass:[NSString class]] ? [self parseISO8601:resetsAtText] : nil;

            if (!fable || !resetsAt) {
                __block BOOL shouldLog = NO;
                dispatch_sync([self stateQueue], ^{
                    if (!gLoggedMissingFable) {
                        gLoggedMissingFable = YES;
                        shouldLog = YES;
                    }
                });
                if (shouldLog) {
                    fprintf(stderr, "codenotch-vp: no Fable window in /api/oauth/usage response — hiding the third bar\n");
                }
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }

            NSNumber *percentNum = fable[@"percent"];
            double percent = [percentNum isKindOfClass:[NSNumber class]] ? percentNum.doubleValue : 0;
            VPLimitRow *row = [[VPLimitRow alloc] initWithLabel:@"Fable esta semana · límite propio"
                                                     usedPercent:percent
                                                        resetsAt:resetsAt];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(row); });
        }];
    [task resume];
}

@end
