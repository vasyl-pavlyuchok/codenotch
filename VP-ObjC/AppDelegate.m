/* audience: machine */
#import "AppDelegate.h"
#import "NotchWindow.h"
#import "ClaudeUsageFile.h"
#import "ClaudeOAuthUsage.h"
#import "CodexUsageReader.h"

#pragma mark - VPUsageCoordinator

/* Ties the readers to the window controller: polls each source on its own
 * interval and pushes whatever it gets to the rings and the hover card. No
 * view logic lives here, only scheduling and merging. Ported from
 * VP/UsageCoordinator.swift.
 *
 * Review fix #1 consumption: pushClaudeUpdate reads claudeFileReading.isStale
 * and passes it through to the window controller (both the ring's `isStale`
 * flag and the card rows' stale-label set), so a reading older than the
 * 30-minute window is visibly marked instead of shown as if it were fresh. */
@interface VPUsageCoordinator : NSObject
- (instancetype)initWithWindow:(VPNotchWindowController *)window;
- (void)start;
@end

@interface VPUsageCoordinator ()
@property (nonatomic, weak) VPNotchWindowController *window;
/* session + weekly_all + Fable, straight from the live OAuth usage call —
 * see ClaudeOAuthUsage.h for why this replaced the local file (dead:
 * nothing writes it, so its frozen session resets_at eventually falls into
 * the past, and it never had weekly_all at all). */
@property (nonatomic, copy) NSArray<VPLimitRow *> *oauthRows;
/* Fallback only, used for the session row until the first successful OAuth
 * poll lands (e.g. right at launch) — see pushClaudeUpdate. */
@property (nonatomic, strong, nullable) VPClaudeUsageReading *claudeFileReading;
@property (nonatomic, strong, nullable) VPLimitRow *codexRow;
@property (nonatomic) BOOL codexInstalled;
/* Last card shape written to stderr, so the same shape is not logged twice. */
@property (nonatomic, copy, nullable) NSString *lastLoggedCardShape;
@end

@implementation VPUsageCoordinator

- (instancetype)initWithWindow:(VPNotchWindowController *)window {
    self = [super init];
    if (self) {
        _window = window;
        _oauthRows = @[];
    }
    return self;
}

/* How often the keychain-backed OAuth call runs. Was 60s until 23-sep-2026.
 *
 * That 60s cadence was the multiplier on the password-dialog bug: every tick
 * did TWO keychain reads (planLabel + pollWithCompletion), so once the
 * `claude` CLI's token refresh had reset the item's partition list, the user
 * got two dialogs a minute until they gave up. The dialog itself is now
 * impossible (see +disableKeychainUserInteraction), and the two rows the user
 * looks at most — "Sesión actual" and "Esta semana · todos los modelos" — no
 * longer come from here at all: they come from ~/.claude/state/usage-5h.json,
 * refreshed every 15s with no keychain and no network.
 *
 * So this call is now only responsible for the third row (Fable's own weekly
 * limit), which genuinely has no other source — it is not in the status
 * line's payload (checked live 23-sep-2026: `rate_limits` carries exactly
 * `five_hour` and `seven_day`, with no per-model breakdown). A weekly quota
 * does not move meaningfully in 60 seconds, so 15 minutes is plenty. */
static const NSTimeInterval kVPOAuthPollInterval = 15 * 60;

- (void)start {
    [self refreshClaudeFile];
    [self refreshSessionState];
    [self refreshCodex];
    [self pollFable];

    __weak typeof(self) weakSelf = self;
    [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf refreshClaudeFile];
    }];
    [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf refreshSessionState];
    }];
    [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf refreshCodex];
    }];
    [NSTimer scheduledTimerWithTimeInterval:kVPOAuthPollInterval repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf pollFable];
    }];
}

- (void)refreshClaudeFile {
    self.claudeFileReading = [VPClaudeUsageFile read];
    [self pushClaudeUpdate];
}

/* The live OAuth "Sesión actual" row, if the last successful poll had one. */
- (nullable VPLimitRow *)oauthSessionRow {
    return [self oauthRowWithLabel:@"Sesión actual"];
}

- (nullable VPLimitRow *)oauthRowWithLabel:(NSString *)label {
    for (VPLimitRow *row in self.oauthRows) {
        if ([row.label isEqualToString:label]) return row;
    }
    return nil;
}

/* Which row the "Sesión actual" ring and card should show, and whether it is
 * stale. 23-sep-2026: the local file is now the PRIMARY source, not the
 * fallback — it refreshes every 15s from the status line with no keychain and
 * no network, whereas the OAuth call now only runs every 15 min and stops
 * entirely when the keychain is unreadable. The OAuth reading is kept as the
 * fallback for the case the file is missing or has gone stale (nobody has
 * used Claude Code for over 30 minutes, so nothing has written it). */
- (nullable VPLimitRow *)sessionRowIsStale:(BOOL *)outStale {
    VPClaudeUsageReading *reading = self.claudeFileReading;
    if (reading.fiveHour && !reading.isStale) {
        if (outStale) *outStale = NO;
        return reading.fiveHour;
    }
    VPLimitRow *oauthRow = [self oauthSessionRow];
    if (oauthRow) {
        if (outStale) *outStale = NO;
        return oauthRow;
    }
    /* Nothing fresh anywhere: show the old file reading, marked stale, rather
     * than an empty ring. Never a made-up number. */
    if (outStale) *outStale = reading.fiveHour ? reading.isStale : NO;
    return reading.fiveHour;
}

/* Same rule for "Esta semana · todos los modelos": the status line's
 * `seven_day` block covers it, so it no longer needs the keychain either. */
- (nullable VPLimitRow *)weeklyAllRowIsStale:(BOOL *)outStale {
    NSString *label = @"Esta semana · todos los modelos";
    VPClaudeUsageReading *reading = self.claudeFileReading;
    if (reading.sevenDay && !reading.isStale) {
        if (outStale) *outStale = NO;
        return reading.sevenDay;
    }
    VPLimitRow *oauthRow = [self oauthRowWithLabel:label];
    if (oauthRow) {
        if (outStale) *outStale = NO;
        return oauthRow;
    }
    if (outStale) *outStale = reading.sevenDay ? reading.isStale : NO;
    return reading.sevenDay;
}

- (void)refreshSessionState {
    VPSessionFlags *flags = [VPSessionState currentClaudeFlags];
    BOOL isStale = NO;
    VPLimitRow *sessionRow = [self sessionRowIsStale:&isStale];
    [self.window updateClaudeWithHeadlinePercent:(sessionRow ? @(sessionRow.usedPercent) : nil)
                                        isWorking:flags.isWorking
                                        isWaiting:flags.isWaiting
                                          isStale:isStale];
}

- (void)pollFable {
    /* CEO-reported bug, 22-sep-2026: the plan label ("Max 5x", "Pro"...) was
     * only ever read once in -start, so a plan change on the account (e.g.
     * downgrading from Max to Pro) never showed up without quitting and
     * relaunching the app. It reads the same keychain item this poll already
     * hits, so riding along here still costs nothing — no new timer.
     *
     * 23-sep-2026: this now runs every 15 min rather than every 60s, and
     * +planLabel falls back to the last value it really read when the
     * keychain is unreadable, so a plan change shows up within a quarter of
     * an hour instead of instantly. That is the right trade: the alternative
     * was two keychain touches a minute, which is what made the password
     * dialog unbearable. */
    [self.window setClaudePlanLabel:[VPClaudeOAuthUsage planLabel]];
    [self.window setClaudeAccountEmail:[VPClaudeOAuthUsage accountEmail]];

    __weak typeof(self) weakSelf = self;
    [VPClaudeOAuthUsage pollWithCompletion:^(NSArray<VPLimitRow *> *rows) {
        /* CEO-reported bug, 18-sep-2026: the card flickered between showing
         * only "Sesión actual" and the full 3-row panel. Root cause — this
         * fires every 60s, and ClaudeOAuthUsage completes with an EMPTY
         * array on any transient hiccup (its own 60s throttle racing this
         * timer, a 429, a network blip), which was overwriting the last good
         * reading with nothing. An empty result means "no update this
         * round," not "there is no data," so only a non-empty result may
         * replace what's already showing. */
        if (rows.count > 0) {
            weakSelf.oauthRows = rows;
        }
        [weakSelf pushClaudeUpdate];
    }];
}

/* One line on stderr (so it lands in /tmp/codenotch-vp.err.log) whenever the
 * SHAPE of the card changes — a row appearing, disappearing, or going stale.
 * Not per-refresh chatter: percentages move constantly and logging those
 * would drown the file.
 *
 * This exists because the 23-sep-2026 rework moved rows 1 and 2 off the
 * keychain and onto a file, and there was no way to tell from outside the app
 * whether the rows were actually being filled — "it compiled" is not evidence
 * that the card renders. Now there is a record. */
- (void)logCardRowsIfChanged:(NSArray<VPLimitRow *> *)rows
                 staleLabels:(NSSet<NSString *> *)staleLabels {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (VPLimitRow *row in rows) {
        [parts addObject:[NSString stringWithFormat:@"%@%@",
                          row.label, [staleLabels containsObject:row.label] ? @" (stale)" : @""]];
    }
    NSString *shape = parts.count > 0 ? [parts componentsJoinedByString:@" | "] : @"(no rows)";
    if ([shape isEqualToString:self.lastLoggedCardShape]) return;
    self.lastLoggedCardShape = shape;
    fprintf(stderr, "codenotch-vp: Claude card rows -> %s\n", shape.UTF8String);
}

/* Builds the three-row Claude card in the approved order. 23-sep-2026: rows 1
 * and 2 now come from ~/.claude/state/usage-5h.json (no keychain, no network)
 * and only row 3 still depends on the OAuth call. When the keychain is
 * unreadable — which is the normal state after the `claude` CLI refreshes its
 * token and wipes the item's partition list — row 3 simply does not appear,
 * rather than the app inventing a number or nagging for a password. */
- (void)pushClaudeUpdate {
    NSMutableArray<VPLimitRow *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *staleLabels = [NSMutableSet set];

    BOOL sessionStale = NO;
    VPLimitRow *sessionRow = [self sessionRowIsStale:&sessionStale];
    if (sessionRow) {
        [rows addObject:sessionRow];
        if (sessionStale) [staleLabels addObject:sessionRow.label];
    }

    BOOL weeklyStale = NO;
    VPLimitRow *weeklyRow = [self weeklyAllRowIsStale:&weeklyStale];
    if (weeklyRow) {
        [rows addObject:weeklyRow];
        if (weeklyStale) [staleLabels addObject:weeklyRow.label];
    }

    /* Row 3: Fable's own weekly limit. Only the OAuth call has it — the
     * status line's payload carries no per-model breakdown (verified live,
     * 23-sep-2026). Omitted entirely when we have never managed to read it. */
    for (VPLimitRow *row in self.oauthRows) {
        if (row == sessionRow || row == weeklyRow) continue;
        if ([row.label isEqualToString:@"Sesión actual"]) continue;
        if ([row.label isEqualToString:@"Esta semana · todos los modelos"]) continue;
        [rows addObject:row];
    }
    [self.window setClaudeCardRows:rows staleLabels:staleLabels];
    [self logCardRowsIfChanged:rows staleLabels:staleLabels];

    VPSessionFlags *flags = [VPSessionState currentClaudeFlags];
    [self.window updateClaudeWithHeadlinePercent:(sessionRow ? @(sessionRow.usedPercent) : nil)
                                        isWorking:flags.isWorking
                                        isWaiting:flags.isWaiting
                                          isStale:sessionStale];
}

- (void)refreshCodex {
    self.codexInstalled = [VPCodexUsageReader isInstalled];
    if (!self.codexInstalled) {
        self.codexRow = nil;
        [self.window updateCodexWithHeadlinePercent:nil installed:NO];
        [self.window setCodexCardRows:@[] installed:NO];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [VPCodexUsageReader pollWithCompletion:^(VPLimitRow *_Nullable row) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.codexRow = row;
        NSNumber *pct = row ? @(row.usedPercent) : nil;
        [strongSelf.window updateCodexWithHeadlinePercent:pct installed:YES];
        [strongSelf.window setCodexCardRows:(row ? @[row] : @[]) installed:YES];
    }];
}

@end

#pragma mark - VPAppDelegate

@interface VPAppDelegate ()
@property (nonatomic, strong, nullable) VPNotchWindowController *windowController;
@property (nonatomic, strong, nullable) VPUsageCoordinator *coordinator;
@end

@implementation VPAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    /* FIRST thing this app does, before any window or timer exists: make it
     * impossible for this process to ever put a keychain password dialog on
     * the user's screen. See ClaudeOAuthUsage.m for the measured root cause
     * and A/B. A status widget in the notch has no business interrupting
     * anyone, least of all at 3am. */
    [VPClaudeOAuthUsage disableKeychainUserInteraction];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    /* No menu-bar icon (CEO feedback, 18-sep-2026: keeps the top bar
     * uncluttered) -- the menu (Salir) lives on the pill itself now, via
     * right-click, in VPNotchContentView.rightMouseDown:. */
    VPNotchWindowController *controller = [VPNotchWindowController new];
    self.windowController = controller;
    [controller show];

    VPUsageCoordinator *coordinator = [[VPUsageCoordinator alloc] initWithWindow:controller];
    self.coordinator = coordinator;
    [coordinator start];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end
