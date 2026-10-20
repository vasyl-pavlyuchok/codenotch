/* audience: machine */
#import "CodexUsageReader.h"

@implementation VPCodexUsageReader

+ (NSString *)codexDir {
    return [NSHomeDirectory() stringByAppendingString:@"/.codex"];
}

+ (NSString *)authPath {
    return [[self codexDir] stringByAppendingString:@"/auth.json"];
}

+ (BOOL)isInstalled {
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[self codexDir] isDirectory:&isDir];
    return exists && isDir;
}

+ (nullable NSDictionary *)loadCredential {
    NSData *data = [NSData dataWithContentsOfFile:[self authPath]];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *tokens = ((NSDictionary *)obj)[@"tokens"];
    if (![tokens isKindOfClass:[NSDictionary class]]) return nil;
    NSString *accessToken = tokens[@"access_token"];
    if (![accessToken isKindOfClass:[NSString class]] || accessToken.length == 0) return nil;
    return tokens;
}

+ (void)pollWithCompletion:(void (^)(NSArray<VPLimitRow *> *))completion {
    if (![self isInstalled]) { completion(@[]); return; }
    NSDictionary *credential = [self loadCredential];
    if (!credential) { completion(@[]); return; }

    NSString *accessToken = credential[@"access_token"];
    NSString *accountID = credential[@"account_id"] ?: @"";

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://chatgpt.com/backend-api/wham/usage"]
                                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                         timeoutInterval:15];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:accountID forHTTPHeaderField:@"ChatGPT-Account-Id"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (status < 200 || status >= 300 || data == nil) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }
            id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![payload isKindOfClass:[NSDictionary class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }
            id rateLimit = ((NSDictionary *)payload)[@"rate_limit"];
            if (![rateLimit isKindOfClass:[NSDictionary class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
                return;
            }
            /* primary_window = the 5h session; secondary_window = the weekly one
             * (20-oct-2026: shown as the thin inner ring; not verifiable on this
             * Mac, where Codex is not installed). */
            NSMutableArray<VPLimitRow *> *rows = [NSMutableArray array];
            NSArray<NSArray<NSString *> *> *windows = @[ @[@"primary_window", @"Sesión actual"],
                                                         @[@"secondary_window", @"Esta semana"] ];
            for (NSArray<NSString *> *pair in windows) {
                id window = ((NSDictionary *)rateLimit)[pair[0]];
                if (![window isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *windowDict = (NSDictionary *)window;
                NSNumber *pctNum = windowDict[@"used_percent"];
                if (![pctNum isKindOfClass:[NSNumber class]]) continue;
                NSDate *resetsAt = nil;
                NSNumber *resetAt = windowDict[@"reset_at"];
                NSNumber *resetAfterSeconds = windowDict[@"reset_after_seconds"];
                if ([resetAt isKindOfClass:[NSNumber class]]) {
                    resetsAt = [NSDate dateWithTimeIntervalSince1970:resetAt.doubleValue];
                } else if ([resetAfterSeconds isKindOfClass:[NSNumber class]]) {
                    resetsAt = [NSDate dateWithTimeIntervalSinceNow:resetAfterSeconds.doubleValue];
                }
                [rows addObject:[[VPLimitRow alloc] initWithLabel:pair[1] usedPercent:pctNum.doubleValue resetsAt:resetsAt]];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(rows); });
        }];
    [task resume];
}

@end
