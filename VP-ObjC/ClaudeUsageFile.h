/* audience: machine */
/* Reads ~/.claude/state/usage-5h.json, the file Scripts/tb-usage-sink.js
 * writes from the status line's own JSON. This is the primary, no-network
 * source for Claude's "current session" (five_hour) and "this week, all
 * models" (seven_day) rows. Ported from VP/ClaudeUsageFile.swift.
 *
 * Frozen top-level keys, read 17-sep-2026 from the live file and from
 * ~/.claude/bin/tb_usage_breaker.py's own docstring: used_percentage,
 * resets_at, updated_at (all at the top level — this is the 5h reading, kept
 * exactly as tb_usage_breaker.py expects it). seven_day is an additive
 * sibling object the breaker does not read and must not be broken.
 *
 * Review fix #1 (medium finding, APTO CON RESERVAS review): the Swift
 * version computed `isStale` but nothing consumed it. This port keeps
 * isStale on the reading AND the window controller consumes it (see
 * NotchWindow.m) to dim/mark a stale row instead of showing an old number
 * as if fresh.
 *
 * Second source, added 29-sep-2026 (CEO-reported: usage-5h.json had been
 * frozen since 26-sep, silently — no crash, wiring intact). Root cause:
 * usage-5h.json only gets written when the TERMINAL `claude` CLI renders its
 * status line, which invokes Scripts/tb-usage-sink.js. Once the CEO stopped
 * using the terminal CLI in favour of the Claude desktop app, nothing called
 * that hook again, and the sink script (correctly) has no way to notice —
 * it is fed, not polled.
 *
 * The desktop app writes its OWN usage log independently of any hook, at
 * `~/Library/Application Support/Claude/plan-usage-history.json`
 * (`{version, samples: [{t, org, u: {fh, sd}}, ...]}`, `t` epoch-ms, `fh`/`sd`
 * the same 0-100 five_hour/seven_day percentages, appended roughly every
 * 15 minutes whenever that app is running) — confirmed live 29-sep-2026,
 * updating in real time while this exact investigation was happening.
 * +readWithNow: now reads both files and keeps whichever has the more
 * recent `updatedAt`, so the rows stay live regardless of which client
 * (terminal CLI or desktop app) the CEO is actually using. Neither source
 * carries a per-model breakdown (checked both live) — that gap is real and
 * is why the Fable row still needs its own OAuth source (ClaudeOAuthUsage.h).
 * This file's samples have no resets_at, so a reading built from it leaves
 * that field nil rather than inventing one. */
#import <Foundation/Foundation.h>
#import "UsageModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface VPClaudeUsageReading : NSObject
@property (nonatomic, strong, nullable) VPLimitRow *fiveHour;
@property (nonatomic, strong, nullable) VPLimitRow *sevenDay;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
/* 30 minutes since updatedAt, matching tb_usage_breaker.py's staleness
 * window. Consumed by the window controller to dim a stale row. */
@property (nonatomic) BOOL isStale;
@end

@interface VPClaudeUsageFile : NSObject

/* 30 minutes, the same staleness window tb_usage_breaker.py uses to decide a
 * reading is too old to trust. */
+ (NSTimeInterval)staleAfter;
+ (NSString *)path;
/* ~/Library/Application Support/Claude/plan-usage-history.json — the desktop
 * app's own usage log, the second source described above. */
+ (NSString *)desktopAppHistoryPath;

/* Returns nil if the file is missing/unparsable or has neither row. */
+ (nullable VPClaudeUsageReading *)readWithNow:(NSDate *)now;
+ (nullable VPClaudeUsageReading *)read; /* now = [NSDate date] */

@end

/* Deliberately simple "working / waiting" signal for Claude's ring, per the
 * task spec: working = a session file touched in the last 90s, or the
 * domain flag touched in the last 60s; waiting = a flag file exists. No
 * parsing of session content — just mtimes and existence, on purpose.
 * Ported from VP/SessionState.swift. */
@interface VPSessionFlags : NSObject
@property (nonatomic) BOOL isWorking;
@property (nonatomic) BOOL isWaiting;
@end

@interface VPSessionState : NSObject
+ (VPSessionFlags *)currentClaudeFlagsWithNow:(NSDate *)now;
+ (VPSessionFlags *)currentClaudeFlags; /* now = [NSDate date] */
@end

NS_ASSUME_NONNULL_END
