// audience: machine
// Builds the macOS icon masters for Codenotch VP from a square, full-bleed source image.
// Applies the standard macOS grid (824x824 artwork inside a 1024 canvas, ~185 px corner
// radius, soft drop shadow) and writes AppIcon.iconset/ (16..1024 @1x/@2x) next to the
// output path. Objective-C because Swift+AppKit is broken on this Mac (see README-VP.md).
//
//   clang -fobjc-arc -framework AppKit make-icon.m -o make-icon
//   ./make-icon <source-image> <output-iconset-dir>
#import <AppKit/AppKit.h>

static NSBitmapImageRep *Render(NSImage *src, int px) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:px pixelsHigh:px bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];
    ctx.imageInterpolation = NSImageInterpolationHigh;
    CGFloat s = px / 1024.0;
    NSRect art = NSMakeRect(100 * s, 100 * s, 824 * s, 824 * s);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:art xRadius:185 * s yRadius:185 * s];
    // Drop shadow under the artwork.
    [NSGraphicsContext saveGraphicsState];
    NSShadow *sh = [NSShadow new];
    sh.shadowColor = [NSColor colorWithCalibratedWhite:0 alpha:0.45];
    sh.shadowBlurRadius = 22 * s;
    sh.shadowOffset = NSMakeSize(0, -10 * s);
    [sh set];
    [[NSColor blackColor] setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];
    // Artwork clipped to the shape.
    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    [src drawInRect:art fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    // Hairline inner edge for definition on light backgrounds.
    [[NSColor colorWithCalibratedWhite:1 alpha:0.10] setStroke];
    shape.lineWidth = MAX(1.0, 2 * s);
    [shape stroke];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: make-icon <source> <iconset-dir>\n"); return 2; }
        NSImage *src = [[NSImage alloc] initWithContentsOfFile:@(argv[1])];
        if (!src) { fprintf(stderr, "cannot read %s\n", argv[1]); return 1; }
        NSString *dir = @(argv[2]);
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        int sizes[] = {16, 32, 128, 256, 512};
        for (int i = 0; i < 5; i++) {
            for (int scale = 1; scale <= 2; scale++) {
                int px = sizes[i] * scale;
                NSData *png = [Render(src, px) representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString *name = scale == 1 ? [NSString stringWithFormat:@"icon_%dx%d.png", sizes[i], sizes[i]]
                                            : [NSString stringWithFormat:@"icon_%dx%d@2x.png", sizes[i], sizes[i]];
                [png writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
            }
        }
    }
    return 0;
}
