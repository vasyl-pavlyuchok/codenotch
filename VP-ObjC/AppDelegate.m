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
@property (nonatomic, strong, nullable) VPLimitRow *fableRow;
@property (nonatomic, strong, nullable) VPClaudeUsageReading *claudeFileReading;
@property (nonatomic, strong, nullable) VPLimitRow *codexRow;
@property (nonatomic) BOOL codexInstalled;
@end

@implementation VPUsageCoordinator

- (instancetype)initWithWindow:(VPNotchWindowController *)window {
    self = [super init];
    if (self) {
        _window = window;
    }
    return self;
}

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
    [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *_Nonnull timer) {
        [weakSelf pollFable];
    }];
}

- (void)refreshClaudeFile {
    self.claudeFileReading = [VPClaudeUsageFile read];
    [self pushClaudeUpdate];
}

- (void)refreshSessionState {
    VPSessionFlags *flags = [VPSessionState currentClaudeFlags];
    NSNumber *headline = self.claudeFileReading.fiveHour ? @(self.claudeFileReading.fiveHour.usedPercent) : nil;
    [self.window updateClaudeWithHeadlinePercent:headline
                                        isWorking:flags.isWorking
                                        isWaiting:flags.isWaiting
                                          isStale:self.claudeFileReading.isStale];
}

- (void)pollFable {
    __weak typeof(self) weakSelf = self;
    [VPClaudeOAuthUsage pollWithCompletion:^(VPLimitRow *_Nullable row) {
        weakSelf.fableRow = row;
        [weakSelf pushClaudeUpdate];
    }];
}

- (void)pushClaudeUpdate {
    NSMutableArray<VPLimitRow *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *staleLabels = [NSMutableSet set];

    VPClaudeUsageReading *reading = self.claudeFileReading;
    if (reading.fiveHour) {
        [rows addObject:reading.fiveHour];
        if (reading.isStale) [staleLabels addObject:reading.fiveHour.label];
    }
    if (reading.sevenDay) {
        [rows addObject:reading.sevenDay];
        if (reading.isStale) [staleLabels addObject:reading.sevenDay.label];
    }
    if (self.fableRow) {
        /* The Fable row comes from its own live poll each time it is shown,
         * so it is never marked stale by the file's staleness window. */
        [rows addObject:self.fableRow];
    }
    [self.window setClaudeCardRows:rows staleLabels:staleLabels];

    VPSessionFlags *flags = [VPSessionState currentClaudeFlags];
    NSNumber *headline = reading.fiveHour ? @(reading.fiveHour.usedPercent) : nil;
    [self.window updateClaudeWithHeadlinePercent:headline
                                        isWorking:flags.isWorking
                                        isWaiting:flags.isWaiting
                                          isStale:reading.isStale];
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
