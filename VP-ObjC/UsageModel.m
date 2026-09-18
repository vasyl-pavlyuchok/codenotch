/* audience: machine */
#import "UsageModel.h"

@implementation VPLimitRow

- (instancetype)initWithLabel:(NSString *)label
                   usedPercent:(double)usedPercent
                      resetsAt:(nullable NSDate *)resetsAt {
    self = [super init];
    if (self) {
        _label = [label copy];
        _usedPercent = usedPercent;
        _resetsAt = resetsAt;
    }
    return self;
}

- (VPUsageBand)band {
    return VPUsageBandForPercent(self.usedPercent);
}

- (BOOL)isEqualToRow:(VPLimitRow *)other {
    if (!other) return NO;
    if (self.usedPercent != other.usedPercent) return NO;
    if (![self.label isEqualToString:other.label]) return NO;
    if (self.resetsAt == other.resetsAt) return YES;
    return [self.resetsAt isEqualToDate:other.resetsAt];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[VPLimitRow class]]) return NO;
    return [self isEqualToRow:(VPLimitRow *)object];
}

- (NSUInteger)hash {
    return self.label.hash ^ (NSUInteger)(self.usedPercent * 1000);
}

- (id)copyWithZone:(NSZone *)zone {
    return [[VPLimitRow alloc] initWithLabel:self.label usedPercent:self.usedPercent resetsAt:self.resetsAt];
}

@end

@implementation VPProviderReading

+ (instancetype)notInstalled {
    VPProviderReading *r = [VPProviderReading new];
    r.state = VPProviderStateNotInstalled;
    r.headlinePercent = nil;
    r.cardRows = @[];
    return r;
}

+ (instancetype)unavailable {
    VPProviderReading *r = [VPProviderReading new];
    r.state = VPProviderStateUnavailable;
    r.headlinePercent = nil;
    r.cardRows = @[];
    return r;
}

@end

/* Same algorithm as gsd-statusline.js's fmtReset (the "↻4h" / "↻1d7h" the CEO
 * already sees in his terminal statusline) -- CEO request, 18-sep-2026: show
 * the same relative countdown in the hover card, alongside the absolute
 * time, "para comprender rapido que a uno le faltan mas de 2 horas". */
static NSString *VPRelativeResetLabel(NSDate *date, NSDate *now) {
    NSInteger s = MAX(0, (NSInteger)[date timeIntervalSinceDate:now]);
    NSInteger h = s / 3600;
    NSInteger m = (s % 3600) / 60;
    if (h >= 24) return [NSString stringWithFormat:@"%ldd%ldh", (long)(h / 24), (long)(h % 24)];
    if (h >= 1) return [NSString stringWithFormat:@"%ldh", (long)h];
    return [NSString stringWithFormat:@"%ldm", (long)m];
}

NSString *VPResetTimeLabel(NSDate *date, NSDate *now) {
    NSString *relative = VPRelativeResetLabel(date, now);
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDate:date inSameDayAsDate:now]) {
        NSDateFormatter *f = [[NSDateFormatter alloc] init];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"es_ES"];
        f.dateFormat = @"H:mm";
        return [NSString stringWithFormat:@"Se reinicia a las %@ (↻%@)", [f stringFromDate:date], relative];
    }
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"es_ES"];
    f.dateFormat = @"EEE HH:mm";
    NSString *text = [[f stringFromDate:date] stringByReplacingOccurrencesOfString:@"." withString:@""];
    return [NSString stringWithFormat:@"Se reinicia %@ (↻%@)", text, relative];
}
