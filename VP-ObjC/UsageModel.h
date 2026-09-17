/* audience: machine */
/* The small shared data shapes every reader (session file, OAuth endpoint,
 * Codex) produces, and the view layer consumes. Kept provider-agnostic on
 * purpose: the ring and the card only ever draw a VPLimitRow. Ported from
 * VP/UsageModel.swift, VP/UsageBand.swift and VP/ResetTime.swift. */
#import <Foundation/Foundation.h>
#import "Palette.h"

NS_ASSUME_NONNULL_BEGIN

@interface VPLimitRow : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *label;
/* 0...100 */
@property (nonatomic, readonly) double usedPercent;
@property (nonatomic, strong, readonly, nullable) NSDate *resetsAt;

- (instancetype)initWithLabel:(NSString *)label
                   usedPercent:(double)usedPercent
                      resetsAt:(nullable NSDate *)resetsAt;

@property (nonatomic, readonly) VPUsageBand band;

- (BOOL)isEqualToRow:(VPLimitRow *)other;
@end

/* What the ring shows for one provider right now. Ported verbatim from
 * VP/UsageModel.swift's ProviderReading — currently unused by the
 * coordinator/window controller in the upstream Swift too (kept for data
 * parity with the reference, not wired further than the reference wires
 * it). */
typedef NS_ENUM(NSInteger, VPProviderState) {
    VPProviderStateOK,
    VPProviderStateNotInstalled,
    VPProviderStateUnavailable
};

@interface VPProviderReading : NSObject
@property (nonatomic) VPProviderState state;
@property (nonatomic, nullable) NSNumber *headlinePercent; /* double, boxed so nil means "no value" */
@property (nonatomic, copy) NSArray<VPLimitRow *> *cardRows;
@property (nonatomic) BOOL isWorking;
@property (nonatomic) BOOL isWaitingForUser;

+ (instancetype)notInstalled;
+ (instancetype)unavailable;
@end

/* Spanish reset-time wording for the tooltip card rows: "Se reinicia a las
 * 8:20" when the reset lands today, "Se reinicia mar 14:00" otherwise. */
NSString *VPResetTimeLabel(NSDate *date, NSDate *now);

NS_ASSUME_NONNULL_END
