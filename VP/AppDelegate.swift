// audience: machine
// Entry point wiring: no Dock icon (accessory activation policy, backed by
// Info.plist's LSUIElement for a proper .app bundle launch), one notch panel,
// one coordinator polling every data source.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var coordinator: UsageCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchWindowController()
        windowController = controller
        controller.show()

        let coordinator = UsageCoordinator(window: controller)
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
