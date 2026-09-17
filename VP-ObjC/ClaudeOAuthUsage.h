/* audience: machine */
/* Reads the Claude Code OAuth token from the macOS login keychain
 * ("Claude Code-credentials") and calls the same usage endpoint the upstream
 * ClaudeOAuthProvider.swift does, to find the Fable weekly window (the third
 * bar in the Claude card). Read-only: never refreshes, never writes, never
 * logs the token value. Ported from VP/ClaudeOAuthUsage.swift.
 *
 * Review fix #2 (medium finding, APTO CON RESERVAS review): the Swift
 * version mutated lastAttempt/backoffUntil/consecutive429 as unsynchronized
 * static vars from a background URLSession callback. This port serializes
 * all reads/writes of that shared state through a private serial
 * dispatch_queue_t (vp.claude-oauth-usage.state), so the completion callback
 * (which NSURLSession delivers off the calling thread) never races the next
 * poll() call. */
#import <Foundation/Foundation.h>
#import "UsageModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface VPClaudeOAuthUsage : NSObject

/* Poll for the Fable weekly row. Fires the completion on the main queue.
 * Respects a 60s minimum interval and backs off on 429; every other failure
 * (no keychain item, network error, no matching window) simply completes
 * with nil so the caller hides the row instead of crashing. */
+ (void)pollWithCompletion:(void (^)(VPLimitRow *_Nullable row))completion;

@end

NS_ASSUME_NONNULL_END
