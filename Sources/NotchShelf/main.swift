import AppKit

// Pure-AppKit entry point (no @main / SwiftUI) so we can build as a plain
// SwiftPM executable and wrap it in a .app bundle ourselves.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon; menu-bar / floating panel only
app.run()
