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
 * as if fresh. */
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
