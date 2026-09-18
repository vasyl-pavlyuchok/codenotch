/* audience: machine */
/* The notch pill window, its two provider ring cells, and the hover tooltip
 * card. Ported from VP/NotchPillPath.swift, VP/Layout.swift,
 * VP/ProviderCellView.swift, VP/TooltipCardView.swift,
 * VP/NotchContentView.swift and VP/NotchWindowController.swift. Kept as one
 * pair (header+impl) per the ObjC port's file plan — Objective-C does not
 * need Swift's one-type-per-file granularity, and one pair here compiles and
 * links faster than the six-file Swift original. */
#import <AppKit/AppKit.h>
#import "UsageModel.h"
#import "Glyphs.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Layout constants

/* Every pixel constant the notch pill and cells use, quoted from the
 * mockup's CSS (mockup-pestana-claude-codex.html) rather than invented.
 * Ported from VP/Layout.swift. */
@interface VPLayout : NSObject

/* Live size control (CEO request, 18-sep-2026): every pill dimension below
 * is multiplied by this factor. 1.0 is the already-reduced ~55% baseline,
 * not the original mockup's size. Clamped to [0.7, 1.4] on write. Does not
 * affect the hover card, which has its own fixed size. */
@property (class, nonatomic) CGFloat scale;

/* Pill body */
@property (class, nonatomic, readonly) CGFloat pillDepth;      /* .notch width */
@property (class, nonatomic, readonly) CGFloat curl;            /* ::before/::after 22x22 */
@property (class, nonatomic, readonly) CGFloat cornerRadius;    /* border-radius 24px on the far side */
@property (class, nonatomic, readonly) CGFloat paddingTop;
@property (class, nonatomic, readonly) CGFloat paddingBottom;
@property (class, nonatomic, readonly) CGFloat cellGap;         /* gap between .prov cells */

/* A provider cell */
@property (class, nonatomic, readonly) CGFloat ringDiameter;    /* .ring 56x56 */
@property (class, nonatomic, readonly) CGFloat ringStroke;
@property (class, nonatomic, readonly) CGFloat ringRadius;      /* circle r=24 inside a 56x56 box */
@property (class, nonatomic, readonly) CGFloat glyphSize;       /* .ring .glyph svg 22x22 */
@property (class, nonatomic, readonly) CGFloat ringToLabelGap;  /* .prov gap:10 */
@property (class, nonatomic, readonly) CGFloat labelFontSize;
@property (class, nonatomic, readonly) CGFloat labelHeight;

@property (class, nonatomic, readonly) CGFloat cellHeight;

/* Height depends on how many provider cells are actually shown — a provider
 * can be hidden from its own toggle in the settings menu (CEO request,
 * 18-sep-2026: "si yo desactivo Codex, tiene que desaparecer de esa barra"),
 * so the pill must shrink/grow rather than always assuming both cells. */
+ (CGFloat)pillContentHeightForVisibleCells:(NSInteger)count;
+ (CGFloat)pillTotalHeightForVisibleCells:(NSInteger)count;

/* Tooltip card */
@property (class, nonatomic, readonly) CGFloat cardWidth;
@property (class, nonatomic, readonly) CGFloat cardCornerRadius;
@property (class, nonatomic, readonly) CGFloat cardPaddingH;
@property (class, nonatomic, readonly) CGFloat cardPaddingTop;
@property (class, nonatomic, readonly) CGFloat cardPaddingBottom;
@property (class, nonatomic, readonly) CGFloat cardGapToNotch;  /* clears the pointer triangle */
@property (class, nonatomic, readonly) CGFloat cardTitleHeight;
@property (class, nonatomic, readonly) CGFloat cardRowLabelHeight;
@property (class, nonatomic, readonly) CGFloat cardBarHeight;
@property (class, nonatomic, readonly) CGFloat cardBarGap;
@property (class, nonatomic, readonly) CGFloat cardUsedHeight;
@property (class, nonatomic, readonly) CGFloat cardRowSpacingTop; /* .lr margin-top on non-first rows */
@property (class, nonatomic, readonly) CGFloat cardSectionGap;

/* Divider + settings-gear strip below the two provider cells (CEO request,
 * 18-sep-2026: moved down from a top header band; opens the same menu that
 * quits the app and will hold future settings). */
@property (class, nonatomic, readonly) CGFloat dividerGap;       /* space above and below the divider line */
@property (class, nonatomic, readonly) CGFloat dividerThickness;
@property (class, nonatomic, readonly) CGFloat footerHeight;     /* strip holding the centred gear icon */
@property (class, nonatomic, readonly) CGFloat footerIconSize;

@end

#pragma mark - Pill geometry

/* The pill shape: rounded on the far (left) side, flush and concave-flared
 * where it meets the screen's right edge. Ported 1:1 into a y-down,
 * top-left-origin coordinate space (this app's views all set
 * isFlipped = YES), matching the Swift original's own CGPath convention.
 * Returned path is +1 retained — caller must CGPathRelease. */
CGPathRef VPNotchPillPathCreate(CGSize size, CGFloat curl, CGFloat cornerRadius);

/* A plain rounded-rect card path (the tooltip), radius on all four corners.
 * Returned path is +1 retained — caller must CGPathRelease. */
CGPathRef VPRoundedRectPathCreate(CGSize size, CGFloat radius);

#pragma mark - Provider cell

/* One provider's ring + glyph + percentage. Plain Core Graphics drawing in a
 * flipped (top-left origin, y-down) NSView. Ported from
 * VP/ProviderCellView.swift.
 *
 * Review fix #1 consumption: `isStale` dims the ring + label when the
 * headline reading is older than the 30-minute staleness window, instead of
 * showing a frozen number as if it were fresh. */
@interface VPProviderCellView : NSView
@property (nonatomic) VPGlyphKind kind;
/* nil = not installed (Codex today): draw a grey ring and "—". */
@property (nonatomic, strong, nullable) NSNumber *headlinePercent;
@property (nonatomic, getter=isWorking) BOOL working;
@property (nonatomic, getter=isWaiting) BOOL waiting;
@property (nonatomic, getter=isInstalled) BOOL installed;
/* Review fix #1: when YES, the ring and its label are dimmed to signal the
 * reading is older than 30 minutes rather than a live number. */
@property (nonatomic, getter=isStale) BOOL stale;
@end

#pragma mark - Tooltip card

/* The black hover card: title with glyph, then one row per VPLimitRow
 * (label + reset time, a thin bar, "N % usado"). Height is computed from the
 * row count so both the one-row Codex card and the three-row Claude card
 * size correctly. Ported from VP/TooltipCardView.swift.
 *
 * Review fix #1 consumption: a row whose staleness flag is set (passed via
 * staleRowLabels) draws its "N % usado" text and reset label dimmed, plus a
 * trailing "(desactualizado)" marker, instead of presenting an old number as
 * current. */
@interface VPTooltipCardView : NSView
@property (nonatomic, copy) NSString *title;
/* Plan name shown right-aligned on the title row, e.g. "Max 5x" (CEO
 * request, 18-sep-2026). nil draws nothing -- Codex has no such concept. */
@property (nonatomic, copy, nullable) NSString *subtitle;
/* Account email, its own line right under the title (CEO request,
 * 18-sep-2026: "por si tuviera mas de una cuenta"). nil draws nothing and
 * costs no vertical space -- Codex has no such concept. */
@property (nonatomic, copy, nullable) NSString *accountEmail;
@property (nonatomic) VPGlyphKind glyph;
@property (nonatomic, copy) NSArray<VPLimitRow *> *rows;
/* Labels (VPLimitRow.label) of rows that should render as stale/dimmed. */
@property (nonatomic, copy) NSSet<NSString *> *staleRowLabels;
@property (nonatomic, copy, nullable) NSString *emptyMessage; /* e.g. "Codex no está instalado" */
/* Y (in this view's own flipped coordinates) where the pointer triangle on
 * the right edge should be centred — set to the hovered ring's centre. */
@property (nonatomic, nullable) NSNumber *pointerY;

/* Height accounts for each row's real label/reset-time text: a row whose
 * label is long enough to collide with its reset time (e.g. "Fable esta
 * semana · límite propio") stacks the reset time onto its own line instead
 * of overlapping it — CEO-reported bug, 18-sep-2026. `hasEmailLine` must
 * match whether `accountEmail` will be set before this card is shown. */
+ (CGFloat)heightForRows:(NSArray<VPLimitRow *> *)rows hasEmptyMessage:(BOOL)hasEmptyMessage hasEmailLine:(BOOL)hasEmailLine;

/* How far the pointer triangle reaches past the card's own right edge. The
 * view's frame is cardWidth + pointerReach wide so the triangle has room to
 * draw without being clipped. */
@property (class, nonatomic, readonly) CGFloat pointerReach;
@end

#pragma mark - Content view (the pill body + two cells)

@class VPNotchContentView;

@protocol VPNotchContentViewDelegate <NSObject>
- (void)notchContentView:(VPNotchContentView *)view hoverChangedProvider:(nullable NSNumber *)providerKind; /* boxed VPGlyphKind, nil = no hover */
/* The gear icon (or a right-click anywhere on the pill) was pressed —
 * CEO request, 18-sep-2026: build and show the settings menu (name+version,
 * per-provider show/hide toggles, opacity slider, quit) from the
 * controller, which owns the persisted state, rather than from the view
 * itself. */
- (void)notchContentView:(VPNotchContentView *)view showSettingsMenuForEvent:(NSEvent *)event;
/* Mouse went down on the divider strip (CEO request, 18-sep-2026: "arrastrar
 * por ese lateral la ventana... pegada al borde"). The controller runs its
 * own drag loop from here since it owns the panel being moved. */
- (void)notchContentView:(VPNotchContentView *)view beginDividerDragWithEvent:(NSEvent *)event;
@end

/* The pill body: draws the black flared-corner shape and hosts the two
 * provider cells, with a tracking area per cell so the window controller can
 * show/hide the right hover card. Ported from VP/NotchContentView.swift. */
@interface VPNotchContentView : NSView
@property (nonatomic, weak, nullable) id<VPNotchContentViewDelegate> hoverDelegate;
@property (nonatomic, strong, readonly) VPProviderCellView *claudeCell;
@property (nonatomic, strong, readonly) VPProviderCellView *codexCell;
/* Per-provider show/hide (CEO request, 18-sep-2026): hiding a provider drops
 * its cell from layout and hit-testing, and the pill shrinks to fit. */
@property (nonatomic, getter=isClaudeVisible) BOOL claudeVisible;
@property (nonatomic, getter=isCodexVisible) BOOL codexVisible;
@property (nonatomic, readonly) NSInteger visibleCellCount;
@end

#pragma mark - Window controller

/* Owns the two floating panels: the notch pill itself, pinned to the right
 * screen edge, and the hover tooltip card that appears/disappears beside it.
 * Both are borderless, non-activating NSPanels so they never take focus or
 * show a Dock icon interaction, and both float above normal windows on
 * every Space. Ported from VP/NotchWindowController.swift. */
@interface VPNotchWindowController : NSObject <VPNotchContentViewDelegate>

- (void)show;

/* Reading updates. `isStale` is review fix #1: the coordinator passes
 * whether the Claude file reading is older than 30 minutes so the ring can
 * dim instead of showing a frozen number as fresh. */
- (void)updateClaudeWithHeadlinePercent:(nullable NSNumber *)headlinePercent
                               isWorking:(BOOL)isWorking
                               isWaiting:(BOOL)isWaiting
                                 isStale:(BOOL)isStale;

- (void)updateCodexWithHeadlinePercent:(nullable NSNumber *)headlinePercent
                              installed:(BOOL)installed;

- (void)setClaudeCardRows:(NSArray<VPLimitRow *> *)rows staleLabels:(NSSet<NSString *> *)staleLabels;
/* The account's plan, e.g. "Max 5x" (CEO request, 18-sep-2026), shown on the
 * Claude card's title row. nil hides it. */
- (void)setClaudePlanLabel:(nullable NSString *)planLabel;
/* The logged-in account's email, e.g. "vasyl@techbooster.io" (CEO request,
 * 18-sep-2026), shown on its own line under the Claude card's title. */
- (void)setClaudeAccountEmail:(nullable NSString *)accountEmail;
- (void)setCodexCardRows:(NSArray<VPLimitRow *> *)rows installed:(BOOL)installed;

@end

NS_ASSUME_NONNULL_END
