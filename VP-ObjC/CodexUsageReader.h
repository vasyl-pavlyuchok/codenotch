/* audience: machine */
/* Codex is not installed on this Mac, so this reads the same on-disk
 * convention (~/.codex/auth.json, tokens.{access_token,account_id}) and,
 * only if that folder exists, calls the same endpoint
 * (chatgpt.com/backend-api/wham/usage, rate_limit.primary_window). If the
 * folder is missing this never touches the network and reports
 * "not installed" so the ring can grey out honestly instead of inventing
 * data. Ported from VP/CodexUsageReader.swift. */
#import <Foundation/Foundation.h>
#import "UsageModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface VPCodexUsageReader : NSObject

+ (BOOL)isInstalled;

/* Only ever meaningfully called when isInstalled is true. Completes with nil
 * on any failure (no credential, network error, bad response) so the caller
 * can show "installed but unavailable" rather than crash. */
+ (void)pollWithCompletion:(void (^)(VPLimitRow *_Nullable row))completion;

@end

NS_ASSUME_NONNULL_END
