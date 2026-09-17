/* audience: machine */
/* Entry point wiring: no Dock icon (accessory activation policy, backed by
 * Info.plist's LSUIElement for a proper .app bundle launch), one notch
 * panel, one coordinator polling every data source. Ported from
 * VP/AppDelegate.swift and VP/UsageCoordinator.swift. */
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VPAppDelegate : NSObject <NSApplicationDelegate>
@end

NS_ASSUME_NONNULL_END
