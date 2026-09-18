/* audience: machine */
#import "NotchWindow.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - VPLayout

@implementation VPLayout

/* Live size control (CEO request, 18-sep-2026: "un menu para poder aumentar
 * y hacer mas pequeña esa ventana flotante") -- every pill dimension below
 * is quoted at its 100% value and multiplied by this factor, so the slider
 * in the settings menu just changes one number instead of every constant.
 * Scoped to the pill only; the hover card's own size is unaffected. */
static CGFloat gVPPillScale = 1.0;
+ (CGFloat)scale { return gVPPillScale; }
+ (void)setScale:(CGFloat)scale { gVPPillScale = MAX(0.7, MIN(1.4, scale)); }

/* Reducido a ~55% (CEO feedback, 18-sep-2026: "esa ventana es enorme,
 * debemos hacerla sutil, como la barra de menus" -- mismo concepto, mucho
 * menos protagonismo en pantalla). This is the scale's 100% baseline. */
+ (CGFloat)pillDepth { return 56 * self.scale; }
+ (CGFloat)curl { return 13 * self.scale; }
+ (CGFloat)cornerRadius { return 14 * self.scale; }
+ (CGFloat)paddingTop { return 14 * self.scale; }
+ (CGFloat)paddingBottom { return 12 * self.scale; }
+ (CGFloat)cellGap { return 14 * self.scale; }

+ (CGFloat)ringDiameter { return 32 * self.scale; }
+ (CGFloat)ringStroke { return 2.5 * self.scale; }
+ (CGFloat)ringRadius { return 13.5 * self.scale; }
+ (CGFloat)glyphSize { return 13 * self.scale; }
+ (CGFloat)ringToLabelGap { return 6 * self.scale; }
+ (CGFloat)labelFontSize { return 10 * self.scale; }
+ (CGFloat)labelHeight { return 13 * self.scale; }

+ (CGFloat)cellHeight { return self.ringDiameter + self.ringToLabelGap + self.labelHeight; }

/* A provider can be hidden from the settings menu (CEO request,
 * 18-sep-2026), so the cell stack's height depends on how many are actually
 * shown -- 0 cells collapses the stack to nothing rather than reserving
 * space for cells that aren't there. */
+ (CGFloat)pillContentHeightForVisibleCells:(NSInteger)count {
    CGFloat cellsHeight = count > 0 ? (self.cellHeight * count + self.cellGap * (count - 1)) : 0;
    return self.paddingTop + cellsHeight
         + self.dividerGap * 2 + self.dividerThickness + self.footerHeight
         + self.paddingBottom;
}
+ (CGFloat)pillTotalHeightForVisibleCells:(NSInteger)count {
    return [self pillContentHeightForVisibleCells:count] + self.curl * 2;
}

/* Separador + icono de ajustes debajo de los dos anillos (CEO feedback,
 * 18-sep-2026: bajado de una franja superior a este lugar; el mismo menu
 * cierra la app y alojara mas ajustes). */
+ (CGFloat)dividerGap { return 10 * self.scale; }
+ (CGFloat)dividerThickness { return 1 * self.scale; }
+ (CGFloat)footerHeight { return 20 * self.scale; }
+ (CGFloat)footerIconSize { return 13 * self.scale; }

/* Reducida a ~75% (CEO feedback, 18-sep-2026: "hay que reducir tambien el
 * tamaño de lo otro" -- misma logica que la pastilla al 55%, la tarjeta
 * aparecia demasiado grande al lado). */
+ (CGFloat)cardWidth { return 225; }
+ (CGFloat)cardCornerRadius { return 14; }
+ (CGFloat)cardPaddingH { return 12; }
+ (CGFloat)cardPaddingTop { return 11; }
+ (CGFloat)cardPaddingBottom { return 12; }
+ (CGFloat)cardGapToNotch { return 18; }
+ (CGFloat)cardTitleHeight { return 18; }
+ (CGFloat)cardRowLabelHeight { return 13; }
+ (CGFloat)cardBarHeight { return 5; }
+ (CGFloat)cardBarGap { return 5; }
+ (CGFloat)cardUsedHeight { return 13; }
+ (CGFloat)cardRowSpacingTop { return 6; }
+ (CGFloat)cardSectionGap { return 5; }

@end

#pragma mark - Pill geometry

CGPathRef VPNotchPillPathCreate(CGSize size, CGFloat curl, CGFloat cornerRadius) {
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    CGFloat wanted = MAX(0, MIN(cornerRadius, rect.size.width / 2));
    CGFloat c = MAX(0, MIN(curl, MIN(rect.size.height / 2, rect.size.width - wanted)));
    CGFloat corner = MAX(0, MIN(wanted, (rect.size.height - 2 * c) / 2));
    CGFloat bodyTop = CGRectGetMinY(rect) + c;
    CGFloat bodyBottom = CGRectGetMaxY(rect) - c;

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, CGRectGetMaxX(rect), CGRectGetMinY(rect));
    if (c > 0) {
        CGPathAddArc(path, NULL, CGRectGetMaxX(rect) - c, CGRectGetMinY(rect), c, 0, M_PI / 2, false);
    }
    CGPathAddLineToPoint(path, NULL, CGRectGetMinX(rect) + corner, bodyTop);
    if (corner > 0) {
        CGPathAddArc(path, NULL, CGRectGetMinX(rect) + corner, bodyTop + corner, corner, 3 * M_PI / 2, M_PI, true);
    }
    CGPathAddLineToPoint(path, NULL, CGRectGetMinX(rect), bodyBottom - corner);
    if (corner > 0) {
        CGPathAddArc(path, NULL, CGRectGetMinX(rect) + corner, bodyBottom - corner, corner, M_PI, M_PI / 2, true);
    }
    CGPathAddLineToPoint(path, NULL, CGRectGetMaxX(rect) - c, bodyBottom);
    if (c > 0) {
        CGPathAddArc(path, NULL, CGRectGetMaxX(rect) - c, CGRectGetMaxY(rect), c, 3 * M_PI / 2, 2 * M_PI, false);
    }
    CGPathCloseSubpath(path);
    return path;
}

CGPathRef VPRoundedRectPathCreate(CGSize size, CGFloat radius) {
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    return CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
}

#pragma mark - VPProviderCellView

@interface VPProviderCellView ()
@property (nonatomic) CGFloat pulsePhase;
/* Slow breathing pulse on the glyph itself while working (CEO feedback,
 * 18-sep-2026: the spinning progress ring "distrae demasiado" and made no
 * sense — replaced by the glyph fading up to the provider's brand colour and
 * back, a ~3s cycle, instead of the ring rotating). */
@property (nonatomic) CGFloat workingPulsePhase;
@property (nonatomic, strong, nullable) NSTimer *animationTimer;
@end

@implementation VPProviderCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _installed = YES;
    }
    return self;
}

- (void)dealloc {
    [_animationTimer invalidate];
}

- (BOOL)isFlipped { return YES; }

- (void)setWorking:(BOOL)working {
    if (_working == working) return;
    _working = working;
    [self updateAnimationTimer];
}

- (void)setWaiting:(BOOL)waiting {
    if (_waiting == waiting) return;
    _waiting = waiting;
    [self updateAnimationTimer];
}

- (void)updateAnimationTimer {
    BOOL needsTimer = self.working || self.waiting;
    if (needsTimer && !self.animationTimer) {
        __weak typeof(self) weakSelf = self;
        self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *_Nonnull timer) {
            [weakSelf tick];
        }];
    } else if (!needsTimer && self.animationTimer) {
        [self.animationTimer invalidate];
        self.animationTimer = nil;
        self.workingPulsePhase = 0;
        self.pulsePhase = 0;
        self.needsDisplay = YES;
    }
}

- (void)tick {
    /* Working: the glyph breathes up to the provider's brand colour and back
     * every 3s, instead of the ring spinning (CEO feedback, 18-sep-2026). */
    if (self.working) {
        self.workingPulsePhase += (2 * M_PI) / (3.0 * 30);
        if (self.workingPulsePhase > 2 * M_PI) self.workingPulsePhase -= 2 * M_PI;
    }
    /* Pulse: 1.4s ease-in-out cycle between full opacity and .35, like `.pulse`. */
    if (self.waiting) {
        self.pulsePhase += (2 * M_PI) / (1.4 * 30);
        if (self.pulsePhase > 2 * M_PI) self.pulsePhase -= 2 * M_PI;
    }
    self.needsDisplay = YES;
}

- (CGFloat)pulseAlpha {
    /* (cos+1)/2 goes 1 -> 0 -> 1 across a cycle; scaled to land on .35 at the
     * trough, matching the CSS keyframe's midpoint value. */
    CGFloat t = (cos(self.pulsePhase) + 1) / 2;
    return 0.35 + t * 0.65;
}

/* 0 at rest, 1 at the brightest point of the breath, easing both ways —
 * cosine gives a free ease-in-out with no extra curve math. */
- (CGFloat)workingPulseAmount {
    return (1 - cos(self.workingPulsePhase)) / 2;
}

/* Each provider's own brand colour, the glyph's target hue at the peak of
 * its working pulse. Claude's is the brand's terracotta orange; Codex/OpenAI
 * has no working signal wired yet ("lo configuraremos" -- CEO, 18-sep-2026),
 * so it falls back to the same white the glyph already rests at. */
static NSColor *VPWorkingPulseColor(VPGlyphKind kind) {
    switch (kind) {
        case VPGlyphKindClaude:
            return [NSColor colorWithSRGBRed:218.0/255.0 green:119.0/255.0 blue:86.0/255.0 alpha:1.0];
        case VPGlyphKindOpenAI:
        default:
            return [NSColor whiteColor];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    if (!ctx) return;

    CGRect ringRect = CGRectMake((self.bounds.size.width - VPLayout.ringDiameter) / 2, 0,
                                  VPLayout.ringDiameter, VPLayout.ringDiameter);
    CGPoint center = CGPointMake(CGRectGetMidX(ringRect), CGRectGetMidY(ringRect));
    CGFloat radius = VPLayout.ringRadius;

    /* Track */
    CGContextSaveGState(ctx);
    NSColor *trackColor;
    CGFloat trackAlpha;
    if (self.waiting) {
        trackColor = [VPPalette watch];
        trackAlpha = self.pulseAlpha;
    } else {
        trackColor = [VPPalette ringTrack];
        trackAlpha = 1;
    }
    CGContextSetStrokeColorWithColor(ctx, [trackColor colorWithAlphaComponent:trackColor.alphaComponent * trackAlpha].CGColor);
    CGContextSetLineWidth(ctx, VPLayout.ringStroke);
    CGContextAddArc(ctx, center.x, center.y, radius, 0, 2 * M_PI, 0);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);

    /* Progress arc, from the top, clockwise, by headlinePercent. Static —
     * it no longer spins while working (CEO feedback, 18-sep-2026: "no
     * tiene sentido que gire eso", distracted from the number). The glyph
     * pulses instead; see workingPulseAmount below.
     * Review fix #1: a stale reading draws at half alpha instead of a full,
     * confident color — the ring still shows the last known number but
     * visibly marks it as not current. */
    if (self.headlinePercent != nil) {
        double pct = self.headlinePercent.doubleValue;
        CGFloat fraction = MAX(0, MIN(1, pct / 100.0));
        VPUsageBand band = VPUsageBandForPercent(pct);
        NSColor *color;
        if (!self.installed) {
            color = [[NSColor whiteColor] colorWithAlphaComponent:0.3];
        } else if (self.stale) {
            color = [VPUsageBandColor(band) colorWithAlphaComponent:0.5];
        } else {
            color = VPUsageBandColor(band);
        }
        CGFloat start = -M_PI / 2;
        CGFloat end = start + 2 * M_PI * fraction;
        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, color.CGColor);
        CGContextSetLineWidth(ctx, VPLayout.ringStroke);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextAddArc(ctx, center.x, center.y, radius, start, end, 0);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }

    /* Glyph, centred in the ring. While working, it breathes from its resting
     * colour up to the provider's brand colour and back (CEO feedback,
     * 18-sep-2026), instead of the ring spinning. */
    CGRect glyphRect = CGRectMake(center.x - VPLayout.glyphSize / 2, center.y - VPLayout.glyphSize / 2,
                                   VPLayout.glyphSize, VPLayout.glyphSize);
    NSColor *glyphColor = self.installed
        ? (self.stale ? [[VPPalette textPrimary] colorWithAlphaComponent:0.6] : [VPPalette textPrimary])
        : [[VPPalette textPrimary] colorWithAlphaComponent:0.4];
    if (self.working) {
        glyphColor = [glyphColor blendedColorWithFraction:self.workingPulseAmount
                                                    ofColor:VPWorkingPulseColor(self.kind)];
    }
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, glyphRect.origin.x, glyphRect.origin.y);
    CGPathRef glyphPath = VPGlyphPathCreateFitted(self.kind, glyphRect.size);
    CGContextAddPath(ctx, glyphPath);
    CGPathRelease(glyphPath);
    CGContextSetFillColorWithColor(ctx, glyphColor.CGColor);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);

    /* Percentage / placeholder label, below the ring. Stale readings dim the
     * label text too (review fix #1). */
    NSString *text = self.installed ? (self.headlinePercent ? [NSString stringWithFormat:@"%ld%%", (long)lround(self.headlinePercent.doubleValue)] : @"—") : @"—";
    NSColor *labelColor = (self.installed && self.stale) ? [[VPPalette textPrimary] colorWithAlphaComponent:0.6] : [VPPalette textPrimary];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:VPLayout.labelFontSize weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: labelColor
    };
    NSSize size = [text sizeWithAttributes:attrs];
    CGRect labelRect = CGRectMake((self.bounds.size.width - size.width) / 2,
                                   VPLayout.ringDiameter + VPLayout.ringToLabelGap,
                                   size.width, VPLayout.labelHeight);
    [text drawInRect:labelRect withAttributes:attrs];
}

@end

#pragma mark - VPTooltipCardView

@implementation VPTooltipCardView

+ (CGFloat)pointerReach { return 11; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _rows = @[];
        _staleRowLabels = [NSSet set];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setRows:(NSArray<VPLimitRow *> *)rows {
    _rows = [rows copy];
    self.needsDisplay = YES;
}

/* A row's label and its right-aligned reset time collide when both are long
 * (e.g. "Fable esta semana · límite propio" + "Se reinicia mar 14:00") —
 * CEO-reported bug, 18-sep-2026 (screenshot showed the two texts printed on
 * top of each other). Measured with the exact font both are drawn with. */
static NSDictionary *VPRowMeasureAttrs(void) {
    return @{ NSFontAttributeName: [NSFont systemFontOfSize:10] };
}

static CGFloat const kVPRowLabelResetGap = 8;

static BOOL VPRowNeedsStackedReset(VPLimitRow *row, CGFloat contentWidth) {
    if (!row.resetsAt) return NO;
    NSDictionary *attrs = VPRowMeasureAttrs();
    CGFloat labelW = [row.label sizeWithAttributes:attrs].width;
    CGFloat resetW = [VPResetTimeLabel(row.resetsAt, [NSDate date]) sizeWithAttributes:attrs].width;
    return (labelW + kVPRowLabelResetGap + resetW) > contentWidth;
}

+ (CGFloat)heightForRows:(NSArray<VPLimitRow *> *)rows hasEmptyMessage:(BOOL)hasEmptyMessage {
    CGFloat top = VPLayout.cardPaddingTop;
    CGFloat title = VPLayout.cardTitleHeight;
    if (hasEmptyMessage) {
        return top + title + VPLayout.cardRowSpacingTop + VPLayout.cardRowLabelHeight + VPLayout.cardPaddingBottom;
    }
    CGFloat contentWidth = VPLayout.cardWidth - 2 * VPLayout.cardPaddingH;
    CGFloat total = top + title;
    for (VPLimitRow *row in rows) {
        CGFloat labelBlockHeight = VPLayout.cardRowLabelHeight;
        if (VPRowNeedsStackedReset(row, contentWidth)) labelBlockHeight += VPLayout.cardRowLabelHeight;
        total += VPLayout.cardRowSpacingTop + labelBlockHeight + VPLayout.cardBarGap
                + VPLayout.cardBarHeight + VPLayout.cardBarGap + VPLayout.cardUsedHeight;
    }
    return total + VPLayout.cardPaddingBottom;
}

- (CGRect)centeredVertically:(CGRect)rect textHeight:(CGFloat)textHeight {
    return CGRectMake(rect.origin.x, rect.origin.y + (rect.size.height - textHeight) / 2, rect.size.width, textHeight);
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    if (!ctx) return;
    CGRect cardBox = CGRectMake(0, 0, VPLayout.cardWidth, self.bounds.size.height);

    /* Card body. */
    CGContextSaveGState(ctx);
    CGPathRef bodyPath = VPRoundedRectPathCreate(cardBox.size, VPLayout.cardCornerRadius);
    CGContextAddPath(ctx, bodyPath);
    CGPathRelease(bodyPath);
    CGContextSetFillColorWithColor(ctx, [VPPalette notchBlack].CGColor);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);

    if (self.pointerY != nil) {
        CGFloat pointerY = self.pointerY.doubleValue;
        CGFloat tipX = cardBox.size.width + VPTooltipCardView.pointerReach;
        CGMutablePathRef triangle = CGPathCreateMutable();
        CGPathMoveToPoint(triangle, NULL, cardBox.size.width, pointerY - 7);
        CGPathAddLineToPoint(triangle, NULL, tipX, pointerY);
        CGPathAddLineToPoint(triangle, NULL, cardBox.size.width, pointerY + 7);
        CGPathCloseSubpath(triangle);
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, triangle);
        CGPathRelease(triangle);
        CGContextSetFillColorWithColor(ctx, [VPPalette notchBlack].CGColor);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
    }

    CGFloat y = VPLayout.cardPaddingTop;
    CGFloat x = VPLayout.cardPaddingH;
    CGFloat contentWidth = cardBox.size.width - 2 * x;

    /* Title: glyph + text. */
    CGFloat glyphSize = 14;
    CGRect glyphRect = CGRectMake(x, y + (VPLayout.cardTitleHeight - glyphSize) / 2, glyphSize, glyphSize);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, glyphRect.origin.x, glyphRect.origin.y);
    CGPathRef titleGlyphPath = VPGlyphPathCreateFitted(self.glyph, glyphRect.size);
    CGContextAddPath(ctx, titleGlyphPath);
    CGPathRelease(titleGlyphPath);
    CGContextSetFillColorWithColor(ctx, [VPPalette textPrimary].CGColor);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [VPPalette textPrimary]
    };
    CGRect titleRect = CGRectMake(x + glyphSize + 6, y, contentWidth - glyphSize - 6, VPLayout.cardTitleHeight);
    [self.title drawInRect:[self centeredVertically:titleRect textHeight:15] withAttributes:titleAttrs];

    /* Plan name, right-aligned on the same row (CEO request, 18-sep-2026:
     * "que aparezca el tipo de suscripcion... Claude Max (5x)"). Skips
     * drawing rather than overlapping the title if the two ever don't fit
     * side by side -- same principle as the row label/reset-time fix. */
    if (self.subtitle.length > 0) {
        NSDictionary *subtitleAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [VPPalette textSecondary]
        };
        CGFloat titleTextW = [self.title sizeWithAttributes:titleAttrs].width;
        CGFloat subtitleW = [self.subtitle sizeWithAttributes:subtitleAttrs].width;
        CGFloat available = titleRect.size.width - titleTextW - 8;
        if (subtitleW <= available) {
            CGRect subtitleRect = CGRectMake(x + contentWidth - subtitleW, y, subtitleW, VPLayout.cardTitleHeight);
            [self.subtitle drawInRect:[self centeredVertically:subtitleRect textHeight:12] withAttributes:subtitleAttrs];
        }
    }
    y += VPLayout.cardTitleHeight;

    if (self.emptyMessage) {
        y += VPLayout.cardRowSpacingTop;
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [VPPalette textSecondary]
        };
        [self.emptyMessage drawInRect:CGRectMake(x, y, contentWidth, VPLayout.cardRowLabelHeight) withAttributes:attrs];
        return;
    }

    for (VPLimitRow *row in self.rows) {
        BOOL isStaleRow = [self.staleRowLabels containsObject:row.label];
        y += VPLayout.cardRowSpacingTop;

        /* Review fix #1: a stale row dims its label/reset/usage text and
         * appends a "(desactualizado)" marker, instead of presenting a
         * frozen percentage as current. */
        NSColor *primaryColor = isStaleRow ? [[VPPalette textPrimary] colorWithAlphaComponent:0.5] : [VPPalette textPrimary];
        NSColor *secondaryColor = isStaleRow ? [[VPPalette textSecondary] colorWithAlphaComponent:0.6] : [VPPalette textSecondary];

        NSDictionary *labelAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: primaryColor
        };
        NSDictionary *resetAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: secondaryColor
        };
        NSString *resetText = row.resetsAt ? VPResetTimeLabel(row.resetsAt, [NSDate date]) : nil;
        BOOL stackReset = resetText && VPRowNeedsStackedReset(row, contentWidth);
        [row.label drawAtPoint:CGPointMake(x, y) withAttributes:labelAttrs];
        if (resetText && !stackReset) {
            NSSize size = [resetText sizeWithAttributes:resetAttrs];
            [resetText drawAtPoint:CGPointMake(x + contentWidth - size.width, y) withAttributes:resetAttrs];
        }
        y += VPLayout.cardRowLabelHeight;
        if (stackReset) {
            NSSize size = [resetText sizeWithAttributes:resetAttrs];
            [resetText drawAtPoint:CGPointMake(x + contentWidth - size.width, y) withAttributes:resetAttrs];
            y += VPLayout.cardRowLabelHeight;
        }
        y += VPLayout.cardBarGap;

        /* Bar. */
        CGRect barRect = CGRectMake(x, y, contentWidth, VPLayout.cardBarHeight);
        CGContextSaveGState(ctx);
        CGPathRef barTrackPath = CGPathCreateWithRoundedRect(barRect, barRect.size.height / 2, barRect.size.height / 2, NULL);
        CGContextAddPath(ctx, barTrackPath);
        CGPathRelease(barTrackPath);
        CGContextSetFillColorWithColor(ctx, [VPPalette barTrack].CGColor);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);

        CGFloat fraction = MAX(0, MIN(1, row.usedPercent / 100.0));
        if (fraction > 0) {
            CGRect fillRect = CGRectMake(x, y, contentWidth * fraction, VPLayout.cardBarHeight);
            CGContextSaveGState(ctx);
            CGPathRef fillPath = CGPathCreateWithRoundedRect(fillRect, fillRect.size.height / 2, fillRect.size.height / 2, NULL);
            CGContextAddPath(ctx, fillPath);
            CGPathRelease(fillPath);
            NSColor *barColor = VPUsageBandColor(row.band);
            if (isStaleRow) barColor = [barColor colorWithAlphaComponent:0.5];
            CGContextSetFillColorWithColor(ctx, barColor.CGColor);
            CGContextFillPath(ctx);
            CGContextRestoreGState(ctx);
        }
        y += VPLayout.cardBarHeight + VPLayout.cardBarGap;

        NSString *usedText = [NSString stringWithFormat:@"%ld %% usado", (long)lround(row.usedPercent)];
        if (isStaleRow) usedText = [usedText stringByAppendingString:@" · desactualizado"];
        NSDictionary *usedAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: primaryColor
        };
        [usedText drawAtPoint:CGPointMake(x, y) withAttributes:usedAttrs];
        y += VPLayout.cardUsedHeight;
    }
}

@end

#pragma mark - VPNotchContentView

@interface VPNotchContentView ()
@property (nonatomic, strong) NSTrackingArea *claudeTrackingArea;
@property (nonatomic, strong) NSTrackingArea *codexTrackingArea;
@end

@implementation VPNotchContentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _claudeCell = [[VPProviderCellView alloc] initWithFrame:NSZeroRect];
        _codexCell = [[VPProviderCellView alloc] initWithFrame:NSZeroRect];
        _claudeCell.kind = VPGlyphKindClaude;
        _codexCell.kind = VPGlyphKindOpenAI;
        _codexCell.installed = NO;
        [self addSubview:_claudeCell];
        [self addSubview:_codexCell];
        [self layoutCells];
        [self rebuildTrackingAreas];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)layout {
    [super layout];
    [self layoutCells];
    [self rebuildTrackingAreas];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    [self rebuildTrackingAreas];
}

/* Only visible cells occupy space in the stack -- a hidden provider (CEO
 * request, 18-sep-2026, per-provider show/hide) leaves no gap behind it. */
- (NSInteger)visibleCellCount {
    return (self.claudeCell.hidden ? 0 : 1) + (self.codexCell.hidden ? 0 : 1);
}

- (CGFloat)cellsStackHeight {
    NSInteger n = self.visibleCellCount;
    return n > 0 ? (VPLayout.cellHeight * n + VPLayout.cellGap * (n - 1)) : 0;
}

- (void)layoutCells {
    CGFloat cellWidth = VPLayout.pillDepth;
    CGFloat cellHeight = VPLayout.cellHeight;
    CGFloat x = 0;
    CGFloat y = VPLayout.curl + VPLayout.paddingTop;
    if (!self.claudeCell.hidden) {
        self.claudeCell.frame = CGRectMake(x, y, cellWidth, cellHeight);
        y += cellHeight + VPLayout.cellGap;
    }
    if (!self.codexCell.hidden) {
        self.codexCell.frame = CGRectMake(x, y, cellWidth, cellHeight);
    }
}

/* Y (en las coordenadas de esta vista, flipped) del borde superior de la
 * linea separadora, justo debajo de los anillos visibles. */
- (CGFloat)dividerTopY {
    return VPLayout.curl + VPLayout.paddingTop + self.cellsStackHeight + VPLayout.dividerGap;
}

- (BOOL)isClaudeVisible { return !self.claudeCell.hidden; }
- (void)setClaudeVisible:(BOOL)visible {
    if (self.claudeCell.hidden == !visible) return;
    self.claudeCell.hidden = !visible;
    [self layoutCells];
    [self rebuildTrackingAreas];
    self.needsDisplay = YES;
}

- (BOOL)isCodexVisible { return !self.codexCell.hidden; }
- (void)setCodexVisible:(BOOL)visible {
    if (self.codexCell.hidden == !visible) return;
    self.codexCell.hidden = !visible;
    [self layoutCells];
    [self rebuildTrackingAreas];
    self.needsDisplay = YES;
}

/* Rect del icono de ajustes en la franja inferior, centrado horizontalmente,
 * debajo del separador (CEO feedback, 18-sep-2026: bajado de la franja
 * superior a aqui, tras los dos anillos). */
- (CGRect)gearIconRect {
    CGFloat size = VPLayout.footerIconSize;
    CGFloat stripTop = self.dividerTopY + VPLayout.dividerThickness + VPLayout.dividerGap;
    CGFloat y = stripTop + (VPLayout.footerHeight - size) / 2;
    return CGRectMake((self.bounds.size.width - size) / 2, y, size, size);
}

/* Grabbable band around the divider line, taller than the 1px line itself so
 * it's actually easy to catch with the cursor (CEO request, 18-sep-2026:
 * drag the pill up/down along the screen edge from here). */
- (CGRect)dividerHitRect {
    CGFloat y = self.dividerTopY;
    return CGRectMake(0, y - 6, self.bounds.size.width, VPLayout.dividerThickness + 12);
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:[self dividerHitRect] cursor:[NSCursor resizeUpDownCursor]];
}

/* A hidden provider gets no tracking area at all -- otherwise its old empty
 * spot would still trigger a hover card for content that isn't shown. */
- (void)rebuildTrackingAreas {
    if (self.claudeTrackingArea) [self removeTrackingArea:self.claudeTrackingArea];
    if (self.codexTrackingArea) [self removeTrackingArea:self.codexTrackingArea];
    self.claudeTrackingArea = nil;
    self.codexTrackingArea = nil;

    if (!self.claudeCell.hidden) {
        NSTrackingArea *claudeArea = [[NSTrackingArea alloc] initWithRect:self.claudeCell.frame
            options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
            owner:self
            userInfo:@{@"provider": @(VPGlyphKindClaude)}];
        [self addTrackingArea:claudeArea];
        self.claudeTrackingArea = claudeArea;
    }
    if (!self.codexCell.hidden) {
        NSTrackingArea *codexArea = [[NSTrackingArea alloc] initWithRect:self.codexCell.frame
            options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
            owner:self
            userInfo:@{@"provider": @(VPGlyphKindOpenAI)}];
        [self addTrackingArea:codexArea];
        self.codexTrackingArea = codexArea;
    }
}

- (void)mouseEntered:(NSEvent *)event {
    NSNumber *kind = event.trackingArea.userInfo[@"provider"];
    if (!kind) return;
    [self.hoverDelegate notchContentView:self hoverChangedProvider:kind];
}

- (void)mouseExited:(NSEvent *)event {
    [self.hoverDelegate notchContentView:self hoverChangedProvider:nil];
}

/* El panel no se activa (NSNonactivatingPanelMask), así que sin esto el
 * primer clic mientras otra app tiene el foco no llegaría a la vista. */
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

/* Icono de ajustes visible bajo el separador (CEO feedback, 18-sep-2026: un
 * boton que se vea y se pueda pulsar, no un clic derecho escondido). El clic
 * derecho en cualquier parte de la pill se deja tambien como atajo. The menu
 * itself is built by the window controller (it owns the persisted
 * visibility state), not here. */
- (void)mouseDown:(NSEvent *)event {
    CGPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (CGRectContainsPoint([self dividerHitRect], p)) {
        [self.hoverDelegate notchContentView:self beginDividerDragWithEvent:event];
        return;
    }
    if (CGRectContainsPoint(CGRectInset([self gearIconRect], -4, -4), p)) {
        [self.hoverDelegate notchContentView:self showSettingsMenuForEvent:event];
        return;
    }
    [super mouseDown:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self.hoverDelegate notchContentView:self showSettingsMenuForEvent:event];
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    if (!ctx) return;
    CGContextSaveGState(ctx);
    CGPathRef path = VPNotchPillPathCreate(self.bounds.size, VPLayout.curl, VPLayout.cornerRadius);
    CGContextAddPath(ctx, path);
    CGPathRelease(path);
    CGContextSetFillColorWithColor(ctx, [VPPalette notchBlack].CGColor);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);

    /* Separador entre los dos anillos y el icono de ajustes (CEO feedback,
     * 18-sep-2026: "un divider y debajo un icono de settings"), mismo tono
     * que el track de los anillos para no competir con ellos. */
    CGFloat dividerY = [self dividerTopY];
    CGRect dividerRect = CGRectMake(VPLayout.cellGap, dividerY,
                                     self.bounds.size.width - VPLayout.cellGap * 2, VPLayout.dividerThickness);
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, [VPPalette ringTrack].CGColor);
    CGContextFillRect(ctx, dividerRect);
    CGContextRestoreGState(ctx);

    /* Icono de ajustes debajo del separador (Lucide "settings", monocromo
     * blanco -- iconos-ui skill: un solo set, un solo color heredado del
     * contexto). CEO feedback, 18-sep-2026. */
    static NSImage *gearIcon = nil;
    static BOOL gearTried = NO;
    if (!gearTried) {
        gearTried = YES;
        /* Loaded straight from the Lucide SVG (AppKit renders SVG natively
         * since macOS 12) -- the earlier rasterized PNG came out as a blank
         * white square, CEO-reported bug, 18-sep-2026. */
        NSString *path = [[NSBundle mainBundle] pathForResource:@"icon-settings" ofType:@"svg"];
        if (path) gearIcon = [[NSImage alloc] initWithContentsOfFile:path];
    }
    if (gearIcon) {
        [gearIcon drawInRect:[self gearIconRect] fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver fraction:0.65];
    }
}

@end

#pragma mark - VPSliderMenuItemView

/* A labeled NSSlider embedded as an NSMenuItem's view (the same pattern
 * macOS's own volume/brightness menu-bar items use) -- CEO request,
 * 18-sep-2026: "con un slider... ajustar la transparencia", and later the
 * same control for pill size. Plain frame layout; menus don't need Auto
 * Layout for one fixed-width row. */
@interface VPSliderMenuItemView : NSView
@property (nonatomic, strong, readonly) NSTextField *label;
@property (nonatomic, strong, readonly) NSSlider *slider;
@end

@implementation VPSliderMenuItemView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _label = [NSTextField labelWithString:@""];
        _label.font = [NSFont menuFontOfSize:0];
        _label.textColor = [NSColor secondaryLabelColor];
        _label.frame = CGRectMake(18, frameRect.size.height - 18, frameRect.size.width - 32, 16);
        [self addSubview:_label];

        /* CEO feedback, 18-sep-2026: the default control size's knob reads as
         * too big for a compact menu row -- small, like the system's own
         * volume/brightness menu-bar sliders, not a full-size Aqua control. */
        _slider = [[NSSlider alloc] initWithFrame:CGRectMake(18, 6, frameRect.size.width - 32, 16)];
        _slider.controlSize = NSControlSizeSmall;
        [_slider.cell setControlSize:NSControlSizeSmall];
        [self addSubview:_slider];
    }
    return self;
}
@end

#pragma mark - VPNotchWindowController

@interface VPNotchWindowController ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) VPNotchContentView *contentView;
@property (nonatomic, strong) NSPanel *tooltipPanel;
@property (nonatomic, strong) VPTooltipCardView *tooltipView;
@property (nonatomic, copy) NSArray<VPLimitRow *> *claudeRows;
@property (nonatomic, copy) NSSet<NSString *> *claudeStaleLabels;
@property (nonatomic, copy, nullable) NSString *claudePlanLabel;
@property (nonatomic, copy) NSArray<VPLimitRow *> *codexRows;
@property (nonatomic) BOOL codexInstalled;
/* Auto-hide (CEO request, 18-sep-2026: "de la misma manera en la que
 * funciona la barra Dock cuando se oculta automáticamente"). */
@property (nonatomic) BOOL autoHideEnabled;
@property (nonatomic) BOOL pillRevealed;
@property (nonatomic) CGRect vp_homeFrame;
@property (nonatomic, strong, nullable) NSDate *lastNearEdgeAt;
@property (nonatomic, strong, nullable) NSTimer *autoHideTimer;
@property (nonatomic) BOOL isDraggingDivider;
@end

@implementation VPNotchWindowController

static NSString *const kVPYOffsetDefaultsKey = @"VPNotchYOffset";
/* Per-provider show/hide, settings-menu toggles (CEO request, 18-sep-2026):
 * "si yo desactivo Codex, tiene que desaparecer de esa barra". Registered
 * both YES so a fresh install shows everything. */
static NSString *const kVPClaudeVisibleDefaultsKey = @"VPProviderVisible.claude";
static NSString *const kVPCodexVisibleDefaultsKey = @"VPProviderVisible.codex";
/* Pill opacity (CEO request, 18-sep-2026: "un poquito" of see-through, "con
 * la opacidad al 95% ... dejar ver ligeramente lo que hay detrás"). Applied
 * to the pill panel only -- the hover card stays fully opaque. */
static NSString *const kVPOpacityDefaultsKey = @"VPPillOpacity";
static double const kVPDefaultOpacity = 0.95;
/* Live pill size (CEO request, 18-sep-2026). */
static NSString *const kVPScaleDefaultsKey = @"VPPillScale";
/* Auto-hide toggle + geometry (CEO request, 18-sep-2026). Defaults to ON,
 * matching "aplica lo mismo [que el Dock] a esta ventana" -- the CEO's own
 * Dock is auto-hide right now and he asked for the same behaviour here. */
static NSString *const kVPAutoHideDefaultsKey = @"VPPillAutoHide";
static CGFloat const kVPEdgeHotMargin = 4;    /* how close to the true screen edge counts as "at the edge" */
static CGFloat const kVPProximityPad = 40;    /* vertical slack around the pill's own band */
static NSTimeInterval const kVPHideDelay = 0.35; /* grace period before sliding away, avoids flicker */

- (instancetype)init {
    self = [super init];
    if (self) {
        _claudeRows = @[];
        _claudeStaleLabels = [NSSet set];
        _codexRows = @[];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{kVPClaudeVisibleDefaultsKey: @YES, kVPCodexVisibleDefaultsKey: @YES,
                                      kVPOpacityDefaultsKey: @(kVPDefaultOpacity),
                                      kVPScaleDefaultsKey: @1.0, kVPAutoHideDefaultsKey: @YES}];
        VPLayout.scale = [defaults doubleForKey:kVPScaleDefaultsKey];
        _autoHideEnabled = [defaults boolForKey:kVPAutoHideDefaultsKey];
        _pillRevealed = YES;
        BOOL claudeVisible = [defaults boolForKey:kVPClaudeVisibleDefaultsKey];
        BOOL codexVisible = [defaults boolForKey:kVPCodexVisibleDefaultsKey];
        NSInteger visibleCount = (claudeVisible ? 1 : 0) + (codexVisible ? 1 : 0);

        CGSize size = CGSizeMake(VPLayout.pillDepth, [VPLayout pillTotalHeightForVisibleCells:visibleCount]);
        _contentView = [[VPNotchContentView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
        _contentView.claudeVisible = claudeVisible;
        _contentView.codexVisible = codexVisible;

        _panel = [[NSPanel alloc] initWithContentRect:CGRectMake(0, 0, size.width, size.height)
                                             styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        _panel.opaque = NO;
        _panel.backgroundColor = [NSColor clearColor];
        _panel.hasShadow = NO;
        _panel.level = NSStatusWindowLevel;
        _panel.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces
                                     | NSWindowCollectionBehaviorStationary
                                     | NSWindowCollectionBehaviorFullScreenAuxiliary
                                     | NSWindowCollectionBehaviorIgnoresCycle);
        _panel.ignoresMouseEvents = NO;
        _panel.movableByWindowBackground = NO;
        _panel.contentView = _contentView;
        _panel.alphaValue = [defaults doubleForKey:kVPOpacityDefaultsKey];

        CGSize tooltipSize = CGSizeMake(VPLayout.cardWidth + VPTooltipCardView.pointerReach,
                                         [VPTooltipCardView heightForRows:@[] hasEmptyMessage:NO]);
        _tooltipView = [[VPTooltipCardView alloc] initWithFrame:CGRectMake(0, 0, tooltipSize.width, tooltipSize.height)];
        _tooltipPanel = [[NSPanel alloc] initWithContentRect:CGRectMake(0, 0, tooltipSize.width, tooltipSize.height)
                                                     styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
        _tooltipPanel.opaque = NO;
        _tooltipPanel.backgroundColor = [NSColor clearColor];
        _tooltipPanel.hasShadow = YES;
        _tooltipPanel.level = NSStatusWindowLevel;
        _tooltipPanel.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces
                                            | NSWindowCollectionBehaviorStationary
                                            | NSWindowCollectionBehaviorFullScreenAuxiliary
                                            | NSWindowCollectionBehaviorIgnoresCycle);
        _tooltipPanel.ignoresMouseEvents = YES;
        _tooltipPanel.contentView = _tooltipView;

        _contentView.hoverDelegate = self;
    }
    return self;
}

- (void)show {
    [self positionPanel];
    [self.panel orderFrontRegardless];
    [self vp_startAutoHideTimer];
}

/* Recomputes where the pill belongs (right edge, vertically per the saved
 * drag offset) and snaps it there, fully revealed. Used by every context
 * where the pill should unambiguously be on screen right now: first launch,
 * a visibility/size change, and mid-drag -- never by the auto-hide tick,
 * which animates instead via vp_setPillRevealed:animated:. */
- (void)positionPanel {
    self.vp_homeFrame = [self vp_computeHomeFrame];
    self.pillRevealed = YES;
    [self.panel setFrame:self.vp_homeFrame display:YES];
}

- (CGRect)vp_computeHomeFrame {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (!screen) return self.panel.frame;
    CGRect full = screen.frame;
    double offset = [[NSUserDefaults standardUserDefaults] doubleForKey:kVPYOffsetDefaultsKey];
    CGSize size = self.panel.frame.size;
    CGFloat x = CGRectGetMaxX(full) - size.width;
    CGFloat y = CGRectGetMidY(full) - size.height / 2 + offset;
    y = MIN(MAX(y, CGRectGetMinY(full)), CGRectGetMaxY(full) - size.height);
    return CGRectMake(x, y, size.width, size.height);
}

#pragma mark Auto-hide (Dock-style)

/* CEO request, 18-sep-2026: "de la misma manera en la que funciona la barra
 * Dock cuando se oculta automáticamente... aplica lo mismo a esta ventana".
 * Polls the mouse position (no Accessibility permission needed, unlike a
 * global CGEventTap) instead of a global event monitor, since a 1/15s timer
 * is simple, cheap, and automatically pauses during menu tracking and the
 * divider-drag loop (both run their own nested run loop modes), so neither
 * of those can be interrupted by a hide firing mid-interaction. */
- (void)vp_startAutoHideTimer {
    if (self.autoHideTimer) return;
    __weak typeof(self) weakSelf = self;
    self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 15.0) repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf vp_autoHideTick];
    }];
}

- (void)vp_autoHideTick {
    if (!self.autoHideEnabled) {
        if (!self.pillRevealed) [self vp_setPillRevealed:YES animated:YES];
        return;
    }
    if (self.isDraggingDivider) { self.lastNearEdgeAt = [NSDate date]; return; }

    self.vp_homeFrame = [self vp_computeHomeFrame];
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (!screen) return;

    CGPoint mouse = [NSEvent mouseLocation];
    CGFloat edgeX = CGRectGetMaxX(screen.frame) - kVPEdgeHotMargin;
    BOOL nearEdgeX = mouse.x >= edgeX;
    CGRect band = CGRectInset(self.vp_homeFrame, 0, -kVPProximityPad);
    BOOL withinBand = mouse.y >= CGRectGetMinY(band) && mouse.y <= CGRectGetMaxY(band);
    /* Anywhere over the already-revealed pill (not just the hairline edge)
     * also counts, so hovering a ring for its tooltip never gets cut short. */
    BOOL overRevealedPill = self.pillRevealed && CGRectContainsPoint(CGRectInset(self.panel.frame, -8, -8), mouse);
    BOOL isNear = (nearEdgeX && withinBand) || overRevealedPill;

    if (isNear) {
        self.lastNearEdgeAt = [NSDate date];
        if (!self.pillRevealed) [self vp_setPillRevealed:YES animated:YES];
    } else if (self.pillRevealed) {
        NSTimeInterval sinceNear = self.lastNearEdgeAt ? -[self.lastNearEdgeAt timeIntervalSinceNow] : (kVPHideDelay + 1);
        if (sinceNear >= kVPHideDelay) [self vp_setPillRevealed:NO animated:YES];
    }
}

- (CGRect)vp_hiddenFrameFromHome:(CGRect)home {
    return CGRectMake(CGRectGetMinX(home) + home.size.width, home.origin.y, home.size.width, home.size.height);
}

- (void)vp_setPillRevealed:(BOOL)revealed animated:(BOOL)animated {
    if (self.pillRevealed == revealed) return;
    self.pillRevealed = revealed;
    CGRect target = revealed ? self.vp_homeFrame : [self vp_hiddenFrameFromHome:self.vp_homeFrame];
    if (!revealed) [self.tooltipPanel orderOut:nil];
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.22;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self.panel.animator setFrame:target display:YES];
        } completionHandler:nil];
    } else {
        [self.panel setFrame:target display:YES];
    }
}

#pragma mark Settings menu

- (void)notchContentView:(VPNotchContentView *)view showSettingsMenuForEvent:(NSEvent *)event {
    [NSMenu popUpContextMenu:[self vp_settingsMenu] withEvent:event forView:self.contentView];
}

- (nullable NSImage *)vp_quitIcon {
    static NSImage *icon = nil;
    static BOOL tried = NO;
    if (!tried) {
        tried = YES;
        NSString *path = [[NSBundle mainBundle] pathForResource:@"icon-quit" ofType:@"svg"];
        if (path) {
            NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
            img.size = NSMakeSize(16, 16);
            img.template = YES;
            icon = img;
        }
    }
    return icon;
}

/* Name + version at the top (CEO request, 18-sep-2026: "tiene sentido que
 * aparezcan las diferentes versiones que vamos mejorando", copying the
 * pattern of Whisper Dictation VP's own menu), then a show/hide toggle per
 * provider, then quit -- same icon set as Whisper Dictation VP's menu, per
 * "esos iconos se pueden copiar tal cual". */
- (NSMenu *)vp_settingsMenu {
    NSMenu *menu = [NSMenu new];

    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *name = info[@"CFBundleName"] ?: @"Codenotch VP";
    NSString *version = info[@"CFBundleShortVersionString"];
    NSString *titleText = version.length ? [NSString stringWithFormat:@"%@ v%@", name, version] : name;
    NSMenuItem *titleItem = [menu addItemWithTitle:titleText action:NULL keyEquivalent:@""];
    titleItem.enabled = NO;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *claudeItem = [menu addItemWithTitle:@"Claude" action:@selector(vp_toggleClaudeVisible:) keyEquivalent:@""];
    claudeItem.target = self;
    claudeItem.state = self.contentView.isClaudeVisible ? NSControlStateValueOn : NSControlStateValueOff;

    NSMenuItem *codexItem = [menu addItemWithTitle:@"Codex" action:@selector(vp_toggleCodexVisible:) keyEquivalent:@""];
    codexItem.target = self;
    codexItem.state = self.contentView.isCodexVisible ? NSControlStateValueOn : NSControlStateValueOff;

    [menu addItem:[NSMenuItem separatorItem]];

    /* Size + transparency sliders (CEO request, 18-sep-2026: "con un slider
     * o con un control numérico" for transparency, and later the same
     * control for pill size) -- an NSSlider embedded as the menu item's own
     * view, same pattern as the system volume/brightness menu items. */
    VPSliderMenuItemView *sizeView = [[VPSliderMenuItemView alloc] initWithFrame:CGRectMake(0, 0, 190, 40)];
    sizeView.slider.minValue = 0.7;
    sizeView.slider.maxValue = 1.4;
    sizeView.slider.doubleValue = VPLayout.scale;
    sizeView.slider.target = self;
    sizeView.slider.action = @selector(vp_scaleChanged:);
    sizeView.label.stringValue = [NSString stringWithFormat:@"Tamaño · %ld%%", (long)lround(VPLayout.scale * 100)];
    NSMenuItem *sizeItem = [NSMenuItem new];
    sizeItem.view = sizeView;
    [menu addItem:sizeItem];

    double opacity = self.panel.alphaValue;
    VPSliderMenuItemView *opacityView = [[VPSliderMenuItemView alloc] initWithFrame:CGRectMake(0, 0, 190, 40)];
    opacityView.slider.minValue = 0.5;
    opacityView.slider.maxValue = 1.0;
    opacityView.slider.doubleValue = opacity;
    opacityView.slider.target = self;
    opacityView.slider.action = @selector(vp_opacityChanged:);
    opacityView.label.stringValue = [NSString stringWithFormat:@"Transparencia · %ld%%", (long)lround(opacity * 100)];
    NSMenuItem *opacityItem = [NSMenuItem new];
    opacityItem.view = opacityView;
    [menu addItem:opacityItem];

    [menu addItem:[NSMenuItem separatorItem]];

    /* Auto-hide (CEO request, 18-sep-2026: "de la misma manera en la que
     * funciona la barra Dock cuando se oculta automáticamente"). */
    NSMenuItem *autoHideItem = [menu addItemWithTitle:@"Ocultar automáticamente" action:@selector(vp_toggleAutoHide:) keyEquivalent:@""];
    autoHideItem.target = self;
    autoHideItem.state = self.autoHideEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [menu addItemWithTitle:@"Salir de Codenotch VP" action:@selector(terminate:) keyEquivalent:@""];
    quit.target = NSApp;
    quit.image = [self vp_quitIcon];
    return menu;
}

- (void)vp_toggleClaudeVisible:(id)sender {
    BOOL newValue = !self.contentView.isClaudeVisible;
    self.contentView.claudeVisible = newValue;
    [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:kVPClaudeVisibleDefaultsKey];
    [self vp_relayoutPill];
}

- (void)vp_toggleCodexVisible:(id)sender {
    BOOL newValue = !self.contentView.isCodexVisible;
    self.contentView.codexVisible = newValue;
    [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:kVPCodexVisibleDefaultsKey];
    [self vp_relayoutPill];
}

- (void)vp_opacityChanged:(NSSlider *)sender {
    double value = sender.doubleValue;
    self.panel.alphaValue = value;
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:kVPOpacityDefaultsKey];
    if ([sender.superview isKindOfClass:[VPSliderMenuItemView class]]) {
        ((VPSliderMenuItemView *)sender.superview).label.stringValue =
            [NSString stringWithFormat:@"Transparencia · %ld%%", (long)lround(value * 100)];
    }
}

- (void)vp_scaleChanged:(NSSlider *)sender {
    VPLayout.scale = sender.doubleValue;
    [[NSUserDefaults standardUserDefaults] setDouble:VPLayout.scale forKey:kVPScaleDefaultsKey];
    [self vp_relayoutPill];
    if ([sender.superview isKindOfClass:[VPSliderMenuItemView class]]) {
        ((VPSliderMenuItemView *)sender.superview).label.stringValue =
            [NSString stringWithFormat:@"Tamaño · %ld%%", (long)lround(VPLayout.scale * 100)];
    }
}

- (void)vp_toggleAutoHide:(id)sender {
    self.autoHideEnabled = !self.autoHideEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:self.autoHideEnabled forKey:kVPAutoHideDefaultsKey];
    if (!self.autoHideEnabled && !self.pillRevealed) {
        [self vp_setPillRevealed:YES animated:YES];
    }
}

/* Shared by both the provider toggles and the size slider -- either can
 * change the pill's overall dimensions, so both need the same re-layout:
 * new content size, re-run the (scale- and visibility-aware) cell layout
 * and tracking areas, then snap back to the right edge. */
- (void)vp_relayoutPill {
    CGSize size = CGSizeMake(VPLayout.pillDepth,
                              [VPLayout pillTotalHeightForVisibleCells:self.contentView.visibleCellCount]);
    [self.panel setContentSize:size];
    [self.contentView layoutCells];
    [self.contentView rebuildTrackingAreas];
    self.contentView.needsDisplay = YES;
    [self positionPanel];
    [self.contentView.window invalidateCursorRectsForView:self.contentView];
}

#pragma mark Divider drag (reposition along the screen edge)

/* CEO request, 18-sep-2026: "arrastrar por ese lateral la ventana, que
 * siempre se quede flotando, pero pegada al borde". Runs its own local event
 * loop for the duration of the drag -- the standard AppKit pattern for a
 * draggable divider -- reading the mouse in SCREEN coordinates each tick so
 * the delta stays correct even as the panel itself moves under the cursor. */
- (void)notchContentView:(VPNotchContentView *)view beginDividerDragWithEvent:(NSEvent *)event {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double startOffset = [defaults doubleForKey:kVPYOffsetDefaultsKey];
    CGFloat startScreenY = [NSEvent mouseLocation].y;
    self.isDraggingDivider = YES;

    for (;;) {
        NSEvent *next = [self.panel nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) break;
        CGFloat deltaY = [NSEvent mouseLocation].y - startScreenY;
        [defaults setDouble:(startOffset + deltaY) forKey:kVPYOffsetDefaultsKey];
        [self positionPanel];
    }
    self.isDraggingDivider = NO;
}

#pragma mark Reading updates

- (void)updateClaudeWithHeadlinePercent:(nullable NSNumber *)headlinePercent
                               isWorking:(BOOL)isWorking
                               isWaiting:(BOOL)isWaiting
                                 isStale:(BOOL)isStale {
    self.contentView.claudeCell.headlinePercent = headlinePercent;
    self.contentView.claudeCell.working = isWorking;
    self.contentView.claudeCell.waiting = isWaiting;
    self.contentView.claudeCell.stale = isStale;
    self.contentView.claudeCell.needsDisplay = YES;
}

- (void)updateCodexWithHeadlinePercent:(nullable NSNumber *)headlinePercent installed:(BOOL)installed {
    self.contentView.codexCell.installed = installed;
    self.contentView.codexCell.headlinePercent = headlinePercent;
    self.contentView.codexCell.needsDisplay = YES;
}

- (void)setClaudeCardRows:(NSArray<VPLimitRow *> *)rows staleLabels:(NSSet<NSString *> *)staleLabels {
    self.claudeRows = rows;
    self.claudeStaleLabels = staleLabels;
}

- (void)setCodexCardRows:(NSArray<VPLimitRow *> *)rows installed:(BOOL)installed {
    self.codexRows = rows;
    self.codexInstalled = installed;
}

#pragma mark Hover

- (void)notchContentView:(VPNotchContentView *)view hoverChangedProvider:(nullable NSNumber *)providerKind {
    if (!providerKind) {
        [self.tooltipPanel orderOut:nil];
        return;
    }
    VPGlyphKind kind = (VPGlyphKind)providerKind.integerValue;
    if (kind == VPGlyphKindClaude) {
        self.tooltipView.title = @"Uso de Claude";
        self.tooltipView.subtitle = self.claudePlanLabel;
        self.tooltipView.glyph = VPGlyphKindClaude;
        self.tooltipView.rows = self.claudeRows;
        self.tooltipView.staleRowLabels = self.claudeStaleLabels;
        self.tooltipView.emptyMessage = self.claudeRows.count == 0 ? @"Esperando la primera lectura…" : nil;
        [self showTooltipAnchoredAtCell:self.contentView.claudeCell rows:self.claudeRows hasEmptyMessage:self.claudeRows.count == 0];
    } else {
        self.tooltipView.title = @"Uso de Codex";
        self.tooltipView.subtitle = nil;
        self.tooltipView.glyph = VPGlyphKindOpenAI;
        self.tooltipView.rows = self.codexRows;
        self.tooltipView.staleRowLabels = [NSSet set];
        self.tooltipView.emptyMessage = self.codexInstalled
            ? (self.codexRows.count == 0 ? @"Esperando la primera lectura…" : nil)
            : @"Codex no está instalado";
        BOOL hasEmpty = !self.codexInstalled || self.codexRows.count == 0;
        [self showTooltipAnchoredAtCell:self.contentView.codexCell rows:self.codexRows hasEmptyMessage:hasEmpty];
    }
}

- (void)showTooltipAnchoredAtCell:(VPProviderCellView *)anchorCell rows:(NSArray<VPLimitRow *> *)rows hasEmptyMessage:(BOOL)hasEmptyMessage {
    CGFloat height = [VPTooltipCardView heightForRows:rows hasEmptyMessage:hasEmptyMessage];
    CGFloat width = VPLayout.cardWidth + VPTooltipCardView.pointerReach;
    self.tooltipView.frame = CGRectMake(0, 0, width, height);

    /* Anchor the pointer at the ring's vertical centre. contentView is
     * flipped (top-left origin) but the panel's own frame is in AppKit's
     * bottom-left screen space, so the cell's y offset from the panel's top
     * is what carries over. */
    CGFloat panelScreenTop = CGRectGetMaxY(self.panel.frame);
    CGFloat pointerScreenY = panelScreenTop - (CGRectGetMinY(anchorCell.frame) + VPLayout.ringDiameter / 2);

    CGFloat screenX = CGRectGetMinX(self.panel.frame) - width - VPLayout.cardGapToNotch + VPTooltipCardView.pointerReach;
    CGFloat screenY = pointerScreenY - height / 2;
    [self.tooltipPanel setFrame:CGRectMake(screenX, screenY, width, height) display:NO];
    self.tooltipView.pointerY = @(height / 2); /* triangle points at the card's own vertical middle,
                                                   which the frame above already aligned with the ring. */
    self.tooltipView.needsDisplay = YES;
    [self.tooltipPanel orderFrontRegardless];
}

@end
