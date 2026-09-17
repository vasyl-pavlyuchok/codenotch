/* audience: machine */
#import "Palette.h"

@implementation NSColor (VPHex)
+ (NSColor *)vp_colorWithSRGBHex:(uint32_t)hex alpha:(CGFloat)alpha {
    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat b = (hex & 0xFF) / 255.0;
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:alpha];
}
@end

@implementation VPPalette

+ (NSColor *)notchBlack { return [NSColor blackColor]; }
+ (NSColor *)ringTrack { return [[NSColor whiteColor] colorWithAlphaComponent:0.188]; }
+ (NSColor *)barTrack { return [[NSColor whiteColor] colorWithAlphaComponent:0.176]; }
+ (NSColor *)ample { return [NSColor vp_colorWithSRGBHex:0x00FF88 alpha:1.0]; }
+ (NSColor *)watch { return [NSColor vp_colorWithSRGBHex:0xF2FF00 alpha:1.0]; }
+ (NSColor *)critical { return [NSColor vp_colorWithSRGBHex:0xFF3F00 alpha:1.0]; }
+ (NSColor *)textPrimary { return [NSColor whiteColor]; }
+ (NSColor *)textSecondary { return [NSColor vp_colorWithSRGBHex:0x808080 alpha:1.0]; }

@end

VPUsageBand VPUsageBandForPercent(double pct) {
    /* Thresholds per upstream VP/UsageBand.swift: <50 ample, <70 watch, else critical. */
    if (pct < 50.0) return VPUsageBandAmple;
    if (pct < 70.0) return VPUsageBandWatch;
    return VPUsageBandCritical;
}

NSColor *VPUsageBandColor(VPUsageBand band) {
    switch (band) {
        case VPUsageBandAmple: return [VPPalette ample];
        case VPUsageBandWatch: return [VPPalette watch];
        case VPUsageBandCritical: return [VPPalette critical];
    }
    return [VPPalette ample];
}
