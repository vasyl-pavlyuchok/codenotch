/* audience: machine */
#import "NotchWindow.h"

#pragma mark - VPLayout

@implementation VPLayout

+ (CGFloat)pillDepth { return 92; }
+ (CGFloat)curl { return 22; }
+ (CGFloat)cornerRadius { return 24; }
+ (CGFloat)paddingTop { return 26; }
+ (CGFloat)paddingBottom { return 22; }
+ (CGFloat)cellGap { return 26; }

+ (CGFloat)ringDiameter { return 56; }
+ (CGFloat)ringStroke { return 4; }
+ (CGFloat)ringRadius { return 24; }
+ (CGFloat)glyphSize { return 22; }
+ (CGFloat)ringToLabelGap { return 10; }
+ (CGFloat)labelFontSize { return 16; }
+ (CGFloat)labelHeight { return 20; }

+ (CGFloat)cellHeight { return self.ringDiameter + self.ringToLabelGap + self.labelHeight; }
+ (CGFloat)pillContentHeight { return self.paddingTop + self.cellHeight * 2 + self.cellGap + self.paddingBottom; }
+ (CGFloat)pillTotalHeight { return self.pillContentHeight + self.curl * 2; }

+ (CGFloat)cardWidth { return 300; }
+ (CGFloat)cardCornerRadius { return 18; }
+ (CGFloat)cardPaddingH { return 16; }
+ (CGFloat)cardPaddingTop { return 14; }
+ (CGFloat)cardPaddingBottom { return 16; }
+ (CGFloat)cardGapToNotch { return 24; }
+ (CGFloat)cardTitleHeight { return 24; }
+ (CGFloat)cardRowLabelHeight { return 17; }
+ (CGFloat)cardBarHeight { return 6; }
+ (CGFloat)cardBarGap { return 6; }
+ (CGFloat)cardUsedHeight { return 17; }
+ (CGFloat)cardRowSpacingTop { return 8; }
+ (CGFloat)cardSectionGap { return 6; }

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
@property (nonatomic) CGFloat spinAngle;
@property (nonatomic) CGFloat pulsePhase;
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
        self.spinAngle = 0;
        self.pulsePhase = 0;
        self.needsDisplay = YES;
    }
}

- (void)tick {
    /* Spin: one full turn every 1.6s, matching the mockup's `.spin` keyframe. */
    if (self.working) {
        self.spinAngle += (2 * M_PI) / (1.6 * 30);
        if (self.spinAngle > 2 * M_PI) self.spinAngle -= 2 * M_PI;
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

    /* Progress arc, from the top, clockwise, by headlinePercent. Rotates
     * continuously while working (spinAngle), independent of the pct sweep.
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
        CGFloat start = -M_PI / 2 + self.spinAngle;
        CGFloat end = start + 2 * M_PI * fraction;
        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, color.CGColor);
        CGContextSetLineWidth(ctx, VPLayout.ringStroke);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextAddArc(ctx, center.x, center.y, radius, start, end, 0);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }

    /* Glyph, centred in the ring. */
    CGRect glyphRect = CGRectMake(center.x - VPLayout.glyphSize / 2, center.y - VPLayout.glyphSize / 2,
                                   VPLayout.glyphSize, VPLayout.glyphSize);
    NSColor *glyphColor = self.installed
        ? (self.stale ? [[VPPalette textPrimary] colorWithAlphaComponent:0.6] : [VPPalette textPrimary])
        : [[VPPalette textPrimary] colorWithAlphaComponent:0.4];
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

+ (CGFloat)pointerReach { return 14; }

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

+ (CGFloat)heightForRowCount:(NSInteger)count hasEmptyMessage:(BOOL)hasEmptyMessage {
    CGFloat top = VPLayout.cardPaddingTop;
    CGFloat title = VPLayout.cardTitleHeight;
    if (hasEmptyMessage) {
        return top + title + 8 + VPLayout.cardRowLabelHeight + VPLayout.cardPaddingBottom;
    }
    CGFloat rowBlock = VPLayout.cardRowLabelHeight + VPLayout.cardBarGap + VPLayout.cardBarHeight
                      + VPLayout.cardBarGap + VPLayout.cardUsedHeight + VPLayout.cardRowSpacingTop;
    return top + title + (CGFloat)count * rowBlock + VPLayout.cardPaddingBottom;
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
        CGPathMoveToPoint(triangle, NULL, cardBox.size.width, pointerY - 9);
        CGPathAddLineToPoint(triangle, NULL, tipX, pointerY);
        CGPathAddLineToPoint(triangle, NULL, cardBox.size.width, pointerY + 9);
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
    CGFloat glyphSize = 18;
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
        NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [VPPalette textPrimary]
    };
    CGRect titleRect = CGRectMake(x + glyphSize + 8, y, contentWidth - glyphSize - 8, VPLayout.cardTitleHeight);
    [self.title drawInRect:[self centeredVertically:titleRect textHeight:19] withAttributes:titleAttrs];
    y += VPLayout.cardTitleHeight;

    if (self.emptyMessage) {
        y += 8;
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13],
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
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: primaryColor
        };
        NSDictionary *resetAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: secondaryColor
        };
        [row.label drawAtPoint:CGPointMake(x, y) withAttributes:labelAttrs];
        if (row.resetsAt) {
            NSString *text = VPResetTimeLabel(row.resetsAt, [NSDate date]);
            NSSize size = [text sizeWithAttributes:resetAttrs];
            [text drawAtPoint:CGPointMake(x + contentWidth - size.width, y) withAttributes:resetAttrs];
        }
        y += VPLayout.cardRowLabelHeight + VPLayout.cardBarGap;

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
            NSFontAttributeName: [NSFont systemFontOfSize:13],
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

- (void)layoutCells {
    CGFloat cellWidth = VPLayout.pillDepth;
    CGFloat cellHeight = VPLayout.cellHeight;
    CGFloat x = 0;
    CGFloat firstY = VPLayout.curl + VPLayout.paddingTop;
    CGFloat secondY = firstY + cellHeight + VPLayout.cellGap;
    self.claudeCell.frame = CGRectMake(x, firstY, cellWidth, cellHeight);
    self.codexCell.frame = CGRectMake(x, secondY, cellWidth, cellHeight);
}

- (void)rebuildTrackingAreas {
    if (self.claudeTrackingArea) [self removeTrackingArea:self.claudeTrackingArea];
    if (self.codexTrackingArea) [self removeTrackingArea:self.codexTrackingArea];

    NSTrackingArea *claudeArea = [[NSTrackingArea alloc] initWithRect:self.claudeCell.frame
        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
        owner:self
        userInfo:@{@"provider": @(VPGlyphKindClaude)}];
    NSTrackingArea *codexArea = [[NSTrackingArea alloc] initWithRect:self.codexCell.frame
        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
        owner:self
        userInfo:@{@"provider": @(VPGlyphKindOpenAI)}];
    [self addTrackingArea:claudeArea];
    [self addTrackingArea:codexArea];
    self.claudeTrackingArea = claudeArea;
    self.codexTrackingArea = codexArea;
}

- (void)mouseEntered:(NSEvent *)event {
    NSNumber *kind = event.trackingArea.userInfo[@"provider"];
    if (!kind) return;
    [self.hoverDelegate notchContentView:self hoverChangedProvider:kind];
}

- (void)mouseExited:(NSEvent *)event {
    [self.hoverDelegate notchContentView:self hoverChangedProvider:nil];
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
@property (nonatomic, copy) NSArray<VPLimitRow *> *codexRows;
@property (nonatomic) BOOL codexInstalled;
@end

@implementation VPNotchWindowController

static NSString *const kVPYOffsetDefaultsKey = @"VPNotchYOffset";

- (instancetype)init {
    self = [super init];
    if (self) {
        _claudeRows = @[];
        _claudeStaleLabels = [NSSet set];
        _codexRows = @[];

        CGSize size = CGSizeMake(VPLayout.pillDepth, VPLayout.pillTotalHeight);
        _contentView = [[VPNotchContentView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];

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

        CGSize tooltipSize = CGSizeMake(VPLayout.cardWidth + VPTooltipCardView.pointerReach,
                                         [VPTooltipCardView heightForRowCount:3 hasEmptyMessage:NO]);
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
}

- (void)positionPanel {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (!screen) return;
    CGRect full = screen.frame;
    double offset = [[NSUserDefaults standardUserDefaults] doubleForKey:kVPYOffsetDefaultsKey];
    CGSize size = self.panel.frame.size;
    CGFloat x = CGRectGetMaxX(full) - size.width;
    CGFloat y = CGRectGetMidY(full) - size.height / 2 + offset;
    y = MIN(MAX(y, CGRectGetMinY(full)), CGRectGetMaxY(full) - size.height);
    [self.panel setFrame:CGRectMake(x, y, size.width, size.height) display:YES];
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
        self.tooltipView.glyph = VPGlyphKindClaude;
        self.tooltipView.rows = self.claudeRows;
        self.tooltipView.staleRowLabels = self.claudeStaleLabels;
        self.tooltipView.emptyMessage = self.claudeRows.count == 0 ? @"Esperando la primera lectura…" : nil;
        [self showTooltipAnchoredAtCell:self.contentView.claudeCell rowCount:self.claudeRows.count hasEmptyMessage:self.claudeRows.count == 0];
    } else {
        self.tooltipView.title = @"Uso de Codex";
        self.tooltipView.glyph = VPGlyphKindOpenAI;
        self.tooltipView.rows = self.codexRows;
        self.tooltipView.staleRowLabels = [NSSet set];
        self.tooltipView.emptyMessage = self.codexInstalled
            ? (self.codexRows.count == 0 ? @"Esperando la primera lectura…" : nil)
            : @"Codex no está instalado";
        BOOL hasEmpty = !self.codexInstalled || self.codexRows.count == 0;
        [self showTooltipAnchoredAtCell:self.contentView.codexCell rowCount:self.codexRows.count hasEmptyMessage:hasEmpty];
    }
}

- (void)showTooltipAnchoredAtCell:(VPProviderCellView *)anchorCell rowCount:(NSInteger)rowCount hasEmptyMessage:(BOOL)hasEmptyMessage {
    CGFloat height = [VPTooltipCardView heightForRowCount:rowCount hasEmptyMessage:hasEmptyMessage];
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
