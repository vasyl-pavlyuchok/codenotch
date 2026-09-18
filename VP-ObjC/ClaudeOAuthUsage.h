/* audience: machine */
/* Reads the Claude Code OAuth token from the macOS login keychain
 * ("Claude Code-credentials") and calls the same usage endpoint the upstream
 * ClaudeOAuthProvider.swift does. `GET /api/oauth/usage` returns a `limits`
 * array with THREE entries (confirmed live, 18-sep-2026): kind "session" (the
 * 5h window, already covered locally by VPClaudeUsageFile), kind
 * "weekly_all" (the second Claude card row — "Esta semana · todos los
 * modelos" — which VPClaudeUsageFile's local file never actually populates
 * because nothing wires its would-be writer, Scripts/tb-usage-sink.js, into
 * the statusLine pipeline; CEO-reported bug, 18-sep-2026: the card was only
 * ever showing 2 of the 3 rows in the approved design), and kind
 * "weekly_scoped" whose scope.model.display_name is "Fable" (the third row).
 * This one call now supplies both of the rows this class returns.
 * Read-only: never refreshes, never writes, never logs the token value.
 * Ported from VP/ClaudeOAuthUsage.swift.
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

/* Poll for the weekly rows (weekly_all, then Fable — in that order,
 * matching the approved design's row order). Fires the completion on the
 * main queue with whichever of the two it found (possibly empty, never
 * nil). Respects a 60s minimum interval and backs off on 429; every other
 * failure (no keychain item, network error, throttled) simply completes
 * with an empty array so the caller hides those rows instead of crashing. */
+ (void)pollWithCompletion:(void (^)(NSArray<VPLimitRow *> *rows))completion;

/* The account's plan, e.g. "Max 5x" or "Pro" (CEO request, 18-sep-2026: show
 * the subscription type in the Claude hover card). Read straight from the
 * same local keychain credential this class already reads for the OAuth
 * call — `subscriptionType` and `rateLimitTier` sit right next to
 * `accessToken` in that blob, so this needs no network call of its own and
 * can't be rate-limited. nil if the keychain item is missing or has neither
 * field. */
+ (nullable NSString *)planLabel;

@end

NS_ASSUME_NONNULL_END
