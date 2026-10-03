/* audience: machine */
#import "ClaudeUsageFile.h"
#import <errno.h>
#import <signal.h>

@implementation VPClaudeUsageReading
@end

@implementation VPClaudeUsageFile

+ (NSString *)path {
    return [NSHomeDirectory() stringByAppendingString:@"/.claude/state/usage-5h.json"];
}

+ (NSString *)desktopAppHistoryPath {
    return [NSHomeDirectory() stringByAppendingString:@"/Library/Application Support/Claude/plan-usage-history.json"];
}

+ (NSTimeInterval)staleAfter {
    return 30 * 60;
}

static NSNumber *_Nullable VPNumberFromAny(id _Nullable v) {
    if ([v isKindOfClass:[NSNumber class]]) return (NSNumber *)v;
    return nil;
}

+ (nullable VPClaudeUsageReading *)read {
    return [self readWithNow:[NSDate date]];
}

/* The Scripts/tb-usage-sink.js source: only written while the terminal CLI's
 * status line is actually rendering (see the class-header comment for why
 * that stopped being true for days at a time). */
+ (nullable VPClaudeUsageReading *)readStatuslineSink {
    NSData *data = [NSData dataWithContentsOfFile:[self path]];
    if (!data) return nil;

    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = (NSDictionary *)obj;

    VPLimitRow *fiveHour = nil;
    NSDate *updated = nil;

    NSNumber *pct = VPNumberFromAny(dict[@"used_percentage"]);
    if (pct) {
        NSNumber *resetsNum = VPNumberFromAny(dict[@"resets_at"]);
        NSDate *resets = resetsNum ? [NSDate dateWithTimeIntervalSince1970:resetsNum.doubleValue] : nil;
        fiveHour = [[VPLimitRow alloc] initWithLabel:@"Sesión actual" usedPercent:pct.doubleValue resetsAt:resets];
    }

    NSNumber *updatedAtNum = VPNumberFromAny(dict[@"updated_at"]);
    if (updatedAtNum) {
        updated = [NSDate dateWithTimeIntervalSince1970:updatedAtNum.doubleValue];
    }

    VPLimitRow *sevenDay = nil;
    id weekObj = dict[@"seven_day"];
    if ([weekObj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *week = (NSDictionary *)weekObj;
        NSNumber *weekPct = VPNumberFromAny(week[@"used_percentage"]);
        if (weekPct) {
            NSNumber *resetsNum = VPNumberFromAny(week[@"resets_at"]);
            NSDate *resets = resetsNum ? [NSDate dateWithTimeIntervalSince1970:resetsNum.doubleValue] : nil;
            sevenDay = [[VPLimitRow alloc] initWithLabel:@"Esta semana · todos los modelos"
                                              usedPercent:weekPct.doubleValue
                                                 resetsAt:resets];
        }
    }

    if (!fiveHour && !sevenDay) return nil;

    VPClaudeUsageReading *reading = [VPClaudeUsageReading new];
    reading.fiveHour = fiveHour;
    reading.sevenDay = sevenDay;
    reading.updatedAt = updated;
    return reading;
}

/* The desktop app's own log: appended by that app itself, roughly every
 * 15 minutes, independently of the terminal CLI or any hook. No resets_at in
 * its samples, so rows built from it carry a nil resetsAt rather than an
 * invented one — the reset-time line simply does not show for that row,
 * exactly like the "no invented numbers" rule everywhere else in this
 * reader. */
+ (nullable VPClaudeUsageReading *)readDesktopAppHistory {
    NSData *data = [NSData dataWithContentsOfFile:[self desktopAppHistoryPath]];
    if (!data) return nil;

    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *samples = ((NSDictionary *)obj)[@"samples"];
    if (![samples isKindOfClass:[NSArray class]] || samples.count == 0) return nil;

    id last = samples.lastObject;
    if (![last isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *sample = (NSDictionary *)last;

    NSNumber *tMillis = VPNumberFromAny(sample[@"t"]);
    if (!tMillis) return nil;
    NSDate *updated = [NSDate dateWithTimeIntervalSince1970:(tMillis.doubleValue / 1000.0)];

    NSDictionary *u = [sample[@"u"] isKindOfClass:[NSDictionary class]] ? sample[@"u"] : nil;
    if (!u) return nil;

    VPLimitRow *fiveHour = nil;
    NSNumber *fh = VPNumberFromAny(u[@"fh"]);
    if (fh) {
        fiveHour = [[VPLimitRow alloc] initWithLabel:@"Sesión actual" usedPercent:fh.doubleValue resetsAt:nil];
    }

    VPLimitRow *sevenDay = nil;
    NSNumber *sd = VPNumberFromAny(u[@"sd"]);
    if (sd) {
        sevenDay = [[VPLimitRow alloc] initWithLabel:@"Esta semana · todos los modelos" usedPercent:sd.doubleValue resetsAt:nil];
    }

    if (!fiveHour && !sevenDay) return nil;

    VPClaudeUsageReading *reading = [VPClaudeUsageReading new];
    reading.fiveHour = fiveHour;
    reading.sevenDay = sevenDay;
    reading.updatedAt = updated;
    return reading;
}

/* Reads both sources and keeps whichever is actually fresher, so the rows
 * stay live no matter which client (terminal CLI or desktop app) is the one
 * actually running right now — see the class-header comment, 29-sep-2026. */
+ (nullable VPClaudeUsageReading *)readWithNow:(NSDate *)now {
    VPClaudeUsageReading *fromSink = [self readStatuslineSink];
    VPClaudeUsageReading *fromDesktopApp = [self readDesktopAppHistory];

    VPClaudeUsageReading *chosen;
    if (fromSink && fromDesktopApp) {
        chosen = ([fromDesktopApp.updatedAt compare:fromSink.updatedAt] == NSOrderedDescending) ? fromDesktopApp : fromSink;
    } else {
        chosen = fromSink ?: fromDesktopApp;
    }
    if (!chosen) return nil;

    chosen.isStale = chosen.updatedAt ? ([now timeIntervalSinceDate:chosen.updatedAt] > [self staleAfter]) : YES;
    return chosen;
}

@end

@implementation VPSessionFlags
@end

@implementation VPSessionState

+ (NSString *)home {
    return NSHomeDirectory();
}

+ (BOOL)mtimeWithinPath:(NSString *)path seconds:(NSTimeInterval)seconds now:(NSDate *)now {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *mtime = attrs[NSFileModificationDate];
    if (!mtime) return NO;
    return [now timeIntervalSinceDate:mtime] < seconds;
}

/* CEO-reported bug, 3-oct-2026 ("no se actualiza el estado", after several
 * earlier fixes): this used to guess "working" from whether any
 * ~/.claude/sessions/<pid>.json had been modified in the last 90 s. Claude
 * Code rewrites that file only when the session's status CHANGES, so a long
 * turn (one tool running for minutes) went quiet after 90 s and the ring
 * dropped to idle while Claude was busy, and a turn that had just ended kept
 * reading as working for another 90 s. Files left by crashed sessions counted
 * too. The original Swift Codenotch (Sources/Sessions/ClaudeSessionRecord.swift)
 * never had this bug: it reads the record's own `status` field and checks the
 * pid is alive. This is a port of that logic. */

typedef NS_ENUM(NSInteger, VPRecordState) {
    VPRecordStateUnknown = 0,   /* no status, or a word we do not know */
    VPRecordStateIdle,
    VPRecordStateBusy,
    VPRecordStateWaiting,
};

/* Same mapping as ClaudeSessionRecord.init: `tempo` is the normalised form
 * when present, `status` the raw one. */
+ (VPRecordState)stateOfRecord:(NSDictionary *)json {
    NSString *tempo = [json[@"tempo"] isKindOfClass:[NSString class]] ? json[@"tempo"] : nil;
    NSString *raw = [json[@"status"] isKindOfClass:[NSString class]] ? json[@"status"] : nil;
    if ([tempo isEqualToString:@"blocked"] || [raw isEqualToString:@"waiting"]) return VPRecordStateWaiting;
    if ([tempo isEqualToString:@"active"] || [raw isEqualToString:@"busy"]) return VPRecordStateBusy;
    if ([tempo isEqualToString:@"idle"] || [raw isEqualToString:@"idle"]) return VPRecordStateIdle;
    return VPRecordStateUnknown;
}

/* kill(pid, 0) succeeds (or fails with EPERM) only for a live process. A file
 * a crashed session left behind must not keep the ring busy forever. */
+ (BOOL)isProcessAlive:(pid_t)pid {
    if (pid <= 0) return NO;
    if (kill(pid, 0) == 0) return YES;
    return errno == EPERM;
}

/* Fallback for a live record that reports no status we understand: the
 * original reads the transcript tail to tell a turn in flight from a finished
 * one. Cheaper and good enough for a ring: the transcript is appended as the
 * turn goes, so a write in the last 20 s means a turn is running. */
+ (BOOL)transcriptRecentlyWrittenForRecord:(NSDictionary *)json now:(NSDate *)now {
    NSString *cwd = [json[@"cwd"] isKindOfClass:[NSString class]] ? json[@"cwd"] : nil;
    NSString *sessionID = [json[@"sessionId"] isKindOfClass:[NSString class]] ? json[@"sessionId"] : nil;
    if (!cwd.length || !sessionID.length) return NO;
    NSString *slug = [[cwd stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
                          stringByReplacingOccurrencesOfString:@"." withString:@"-"];
    NSString *path = [NSString stringWithFormat:@"%@/.claude/projects/%@/%@.jsonl", [self home], slug, sessionID];
    return [self mtimeWithinPath:path seconds:20 now:now];
}

+ (VPSessionFlags *)currentClaudeFlags {
    return [self currentClaudeFlagsWithNow:[NSDate date]];
}

+ (VPSessionFlags *)currentClaudeFlagsWithNow:(NSDate *)now {
    VPSessionFlags *flags = [VPSessionFlags new];
    NSString *dir = [[self home] stringByAppendingString:@"/.claude/sessions"];
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    BOOL anyLive = NO, anyBusy = NO;
    for (NSString *name in names) {
        if (![name hasSuffix:@".json"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
        if (!data) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *json = obj;
        NSNumber *pid = [json[@"pid"] isKindOfClass:[NSNumber class]] ? json[@"pid"] : nil;
        if (!pid || ![self isProcessAlive:pid.intValue]) continue;
        anyLive = YES;
        switch ([self stateOfRecord:json]) {
            case VPRecordStateWaiting: flags.isWaiting = YES; break;
            case VPRecordStateBusy:    anyBusy = YES; break;
            case VPRecordStateIdle:    break;
            case VPRecordStateUnknown:
                if ([self transcriptRecentlyWrittenForRecord:json now:now]) anyBusy = YES;
                break;
        }
    }
    /* needs-user.flag (tb-codenotch-waiting-flag.py, set on Notification) is
     * still honoured: it covers a prompt the record does not report. Only
     * while some session is alive, so a flag stranded by a closed session
     * cannot pulse the ring forever. */
    if (anyLive && !flags.isWaiting) {
        NSString *flag = [[self home] stringByAppendingString:@"/.claude/state/needs-user.flag"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:flag] && !anyBusy) flags.isWaiting = YES;
    }
    flags.isWorking = anyBusy;
    return flags;
}

@end
