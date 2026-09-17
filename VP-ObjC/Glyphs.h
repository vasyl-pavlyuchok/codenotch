/* audience: machine */
/* Minimal SVG path ("d" attribute) parser plus the two provider glyph paths,
 * ported from VP/SVGPath.swift + VP/Glyphs.swift. Supports the commands
 * those two paths actually use: M/m, L/l, H/h, V/v, C/c, Z/z. Not a general
 * SVG engine — no arcs, no quadratic/smooth curves, because the source
 * glyphs never need them. */
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Parses a "d" attribute string into a CGPath, in the SVG's own (y-down)
 * coordinate space. The caller is responsible for scaling/translating.
 * Returned path is +1 retained (CF create rule) — caller must CGPathRelease. */
CGPathRef VPSVGPathCreate(NSString *d);

/* Returns a new path scaled and centred to fit `size`, preserving aspect
 * ratio, given the path's own coordinate space is `viewBox`. Returned path
 * is +1 retained — caller must CGPathRelease. */
CGPathRef VPSVGPathCreateFitted(CGPathRef path, CGSize viewBox, CGSize size);

typedef NS_ENUM(NSInteger, VPGlyphKind) {
    VPGlyphKindClaude,
    VPGlyphKindOpenAI
};

/* The glyph's own coordinate space, as declared by the source SVG's viewBox. */
CGSize VPGlyphViewBox(VPGlyphKind kind);

/* A CGPath fitted (aspect-preserved, centred) into `size`. Returned path is
 * +1 retained — caller must CGPathRelease. */
CGPathRef VPGlyphPathCreateFitted(VPGlyphKind kind, CGSize size);

NS_ASSUME_NONNULL_END
