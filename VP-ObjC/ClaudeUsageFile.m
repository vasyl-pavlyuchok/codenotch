/* audience: machine */
#import "ClaudeUsageFile.h"

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

+ (BOOL)anySessionFileFreshSeconds:(NSTimeInterval)seconds now:(NSDate *)now {
    NSString *dir = [[self home] stringByAppendingString:@"/.claude/sessions"];
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    if (!names) return NO;
    for (NSString *name in names) {
        if (![name hasSuffix:@".json"]) continue;
        NSString *full = [dir stringByAppendingPathComponent:name];
        if ([self mtimeWithinPath:full seconds:seconds now:now]) return YES;
    }
    return NO;
}

+ (BOOL)isClaudeWorkingWithNow:(NSDate *)now {
    NSString *domainFlag = [[self home] stringByAppendingString:@"/.claude/state/tb-domain-flag.json"];
    if ([self mtimeWithinPath:domainFlag seconds:60 now:now]) return YES;
    return [self anySessionFileFreshSeconds:90 now:now];
}

+ (BOOL)isClaudeWaiting {
    NSString *flag = [[self home] stringByAppendingString:@"/.claude/state/needs-user.flag"];
    return [[NSFileManager defaultManager] fileExistsAtPath:flag];
}

+ (VPSessionFlags *)currentClaudeFlags {
    return [self currentClaudeFlagsWithNow:[NSDate date]];
}

+ (VPSessionFlags *)currentClaudeFlagsWithNow:(NSDate *)now {
    VPSessionFlags *flags = [VPSessionFlags new];
    flags.isWorking = [self isClaudeWorkingWithNow:now];
    flags.isWaiting = [self isClaudeWaiting];
    return flags;
}

@end
