// audience: machine
// Plain AppKit main, no storyboard/xib — this is a swiftc-built binary, not
// an Xcode target.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
