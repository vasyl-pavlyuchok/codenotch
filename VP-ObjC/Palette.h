/* audience: machine */
/* Plain AppKit colours, matching VP/Palette.swift exactly (same hexes and
 * alphas) but without the SwiftUI/dark-light adaptive machinery — this notch
 * is always pure black, on every appearance, per spec. Ported from
 * VP/Palette.swift and VP/UsageBand.swift. */
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (VPHex)
+ (NSColor *)vp_colorWithSRGBHex:(uint32_t)hex alpha:(CGFloat)alpha;
@end

@interface VPPalette : NSObject
+ (NSColor *)notchBlack;
+ (NSColor *)ringTrack;
+ (NSColor *)barTrack;
+ (NSColor *)ample;
+ (NSColor *)watch;
+ (NSColor *)critical;
+ (NSColor *)textPrimary;
+ (NSColor *)textSecondary;
@end

/* Colour band for a used-fraction, exactly like upstream VP/UsageBand.swift:
 * under 50% is ample, under 70% is watch, 70% and over is critical. */
typedef NS_ENUM(NSInteger, VPUsageBand) {
    VPUsageBandAmple,
    VPUsageBandWatch,
    VPUsageBandCritical
};

VPUsageBand VPUsageBandForPercent(double pct);
NSColor *VPUsageBandColor(VPUsageBand band);

NS_ASSUME_NONNULL_END
