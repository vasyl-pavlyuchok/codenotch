/* audience: machine */
/* Reads the Claude Code OAuth token from the macOS login keychain
 * ("Claude Code-credentials") and calls the same usage endpoint the upstream
 * ClaudeOAuthProvider.swift does. `GET /api/oauth/usage` returns a `limits`
 * array with THREE entries (confirmed live, 18-sep-2026), in this order:
 * kind "session" (the 5h row — originally read from the local file
 * VPClaudeUsageFile instead, but that file is dead (nothing has written it
 * in over a day), so its frozen resets_at eventually falls into the past
 * and the relative countdown showed "↻0m" — CEO-reported bug, 18-sep-2026 —
 * this live call is now the row's source of truth instead), kind
 * "weekly_all" (the second Claude card row — "Esta semana · todos los
 * modelos" — which VPClaudeUsageFile's local file never populates either,
 * because nothing wires its would-be writer, Scripts/tb-usage-sink.js, into
 * the statusLine pipeline; CEO-reported bug, 18-sep-2026: the card was only
 * ever showing 2 of the 3 rows in the approved design), and kind
 * "weekly_scoped" whose scope.model.display_name is "Fable" (the third row).
 * This one call now supplies all three of the rows this class returns.
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

/* Turns the legacy keychain's user-interaction switch OFF for this process,
 * for good. With it off a keychain read that would have opened the classic
 * "Codenotch VP wants to access key Claude Code-credentials" dialog fails
 * with errSecAuthFailed instead, silently.
 *
 * Call it once at launch. The keychain read path calls it too (dispatch_once,
 * so it is free), which means no code path in this app can ever put a
 * keychain dialog on the user's screen. See ClaudeOAuthUsage.m for the
 * measured A/B that established this, and README-VP.md for the root cause. */
+ (void)disableKeychainUserInteraction;

/* Poll for all three rows (session, weekly_all, then Fable — in that order,
 * matching the approved design's row order). Fires the completion on the
 * main queue with whichever of the three it found (possibly empty, never
 * nil). Respects a 60s minimum interval and backs off on 429; every other
 * failure (no keychain item, network error, throttled) simply completes
 * with an empty array so the caller keeps showing the last good reading
 * instead of blanking rows or crashing. */
+ (void)pollWithCompletion:(void (^)(NSArray<VPLimitRow *> *rows))completion;

/* The account's plan, e.g. "Max 5x" or "Pro" (CEO request, 18-sep-2026: show
 * the subscription type in the Claude hover card). Read straight from the
 * same local keychain credential this class already reads for the OAuth
 * call — `subscriptionType` and `rateLimitTier` sit right next to
 * `accessToken` in that blob, so this needs no network call of its own and
 * can't be rate-limited. nil if the keychain item is missing or has neither
 * field. */
+ (nullable NSString *)planLabel;

/* The logged-in account's email, e.g. "vasyl@techbooster.io" (CEO request,
 * 18-sep-2026: shown alongside the plan so a second Claude account, if one
 * is ever added, is distinguishable at a glance). Read from
 * ~/.claude.json's oauthAccount.emailAddress -- a local Claude Code config
 * file, not the keychain, and not a network call. nil if missing/unparsable. */
+ (nullable NSString *)accountEmail;

@end

NS_ASSUME_NONNULL_END
