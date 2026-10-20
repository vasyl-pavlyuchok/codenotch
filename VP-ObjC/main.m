/* audience: machine */
/* Plain AppKit main, no storyboard/xib — this is a clang-built binary, not
 * an Xcode target. Ported from VP/main.swift. */
#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#include <sys/stat.h>
#include <stdio.h>
#include <unistd.h>

/* Opening the app by double-click (Finder) starts it outside the LaunchAgent,
 * where stderr is /dev/null and nothing it logs survives. Send it to the same
 * file the LaunchAgent uses, so every copy of the app is diagnosable. */
static void VPRedirectStderrIfDiscarded(void) {
    struct stat st;
    if (fstat(STDERR_FILENO, &st) == 0 && S_ISCHR(st.st_mode) && !isatty(STDERR_FILENO)) {
        freopen("/tmp/codenotch-vp.err.log", "a", stderr);
    }
}

/* Only one copy may run: a second double-click, or the LaunchAgent starting
 * next to a hand-opened copy, used to draw two pills on top of each other. */
static BOOL VPAnotherCopyIsRunning(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID.length) return NO;
    pid_t me = getpid();
    for (NSRunningApplication *other in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        if (other.processIdentifier != me) return YES;
    }
    return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        VPRedirectStderrIfDiscarded();
        if (VPAnotherCopyIsRunning()) {
            fprintf(stderr, "codenotch-vp: another copy is already running, this one exits\n");
            return 0;
        }
        NSApplication *app = [NSApplication sharedApplication];
        VPAppDelegate *delegate = [VPAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
