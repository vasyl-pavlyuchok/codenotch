/* audience: machine */
#import "ClaudeUsageFile.h"

@implementation VPClaudeUsageReading
@end

@implementation VPClaudeUsageFile

+ (NSString *)path {
    return [NSHomeDirectory() stringByAppendingString:@"/.claude/state/usage-5h.json"];
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

+ (nullable VPClaudeUsageReading *)readWithNow:(NSDate *)now {
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

    BOOL stale;
    if (updated) {
        stale = [now timeIntervalSinceDate:updated] > [self staleAfter];
    } else {
        stale = YES;
    }

    if (!fiveHour && !sevenDay) return nil;

    VPClaudeUsageReading *reading = [VPClaudeUsageReading new];
    reading.fiveHour = fiveHour;
    reading.sevenDay = sevenDay;
    reading.updatedAt = updated;
    reading.isStale = stale;
    return reading;
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
