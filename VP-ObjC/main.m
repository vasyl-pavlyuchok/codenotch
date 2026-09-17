/* audience: machine */
/* Plain AppKit main, no storyboard/xib — this is a clang-built binary, not
 * an Xcode target. Ported from VP/main.swift. */
#import <AppKit/AppKit.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        VPAppDelegate *delegate = [VPAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
