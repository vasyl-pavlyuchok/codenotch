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

- (void)start {
    [self refreshClaudeFile];
    [self refreshSessionState];
    [self refreshCodex];
    [self pollFable];
    [self.window setClaudePlanLabel:[VPClaudeOAuthUsage planLabel]];
    [self.window setClaudeAccountEmail:[VPClaudeOAuthUsage accountEmail]];

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
    [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf pollFable];
    }];
}

- (void)refreshClaudeFile {
    self.claudeFileReading = [VPClaudeUsageFile read];
    [self pushClaudeUpdate];
}

/* The live OAuth "Sesión actual" row, if the last successful poll had one. */
- (nullable VPLimitRow *)oauthSessionRow {
    for (VPLimitRow *row in self.oauthRows) {
        if ([row.label isEqualToString:@"Sesión actual"]) return row;
    }
    return nil;
}

- (void)refreshSessionState {
    VPSessionFlags *flags = [VPSessionState currentClaudeFlags];
    VPLimitRow *sessionRow = self.oauthSessionRow;
    NSNumber *headline = sessionRow ? @(sessionRow.usedPercent)
        : (self.claudeFileReading.fiveHour ? @(self.claudeFileReading.fiveHour.usedPercent) : nil);
    BOOL isStale = sessionRow ? NO : self.claudeFileReading.isStale;
    [self.window updateClaudeWithHeadlinePercent:headline
                                        isWorking:flags.isWorking
                                        isWaiting:flags.isWaiting
                                          isStale:isStale];
}

- (void)pollFable {
    /* CEO-reported bug, 22-sep-2026: the plan label ("Max 5x", "Pro"...) was
     * only ever read once in -start, so a plan change on the account (e.g.
     * downgrading from Max to Pro) never showed up without quitting and
     * relaunching the app. It reads the same keychain item this poll
     * already hits every 60s, so riding along here is free — no new timer. */
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

- (void)pushClaudeUpdate {
    NSMutableArray<VPLimitRow *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *staleLabels = [NSMutableSet set];

    /* Session row: prefer the live OAuth reading (never stale — refreshed by
     * its own 60s poll) over the local file, which is only a fallback until
     * the first successful poll lands (e.g. right at launch). */
    VPLimitRow *sessionRow = self.oauthSessionRow;
    VPClaudeUsageReading *reading = self.claudeFileReading;
    if (sessionRow) {
        [rows addObject:sessionRow];
    } else if (reading.fiveHour) {
        [rows addObject:reading.fiveHour];
        if (reading.isStale) [staleLabels addObject:reading.fiveHour.label];
    }
    /* weekly_all + Fable ride along in the same oauthRows array. */
    for (VPLimitRow *row in self.oauthRows) {
        if (row != sessionRow) [rows addObject:row];
    }
    [self.window setClaudeCardRows:rows staleLabels:staleLabels];

    VPSessionFlags *flags = [VPSessionState currentClaudeFlags];
    NSNumber *headline = sessionRow ? @(sessionRow.usedPercent)
        : (reading.fiveHour ? @(reading.fiveHour.usedPercent) : nil);
    BOOL isStale = sessionRow ? NO : reading.isStale;
    [self.window updateClaudeWithHeadlinePercent:headline
                                        isWorking:flags.isWorking
                                        isWaiting:flags.isWaiting
                                          isStale:isStale];
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
