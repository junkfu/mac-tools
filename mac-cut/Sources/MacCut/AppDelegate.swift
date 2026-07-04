import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var openWindows: [AnnotationWindowController] = []
    private var preferencesWindowController: PreferencesWindowController?
    private var captureMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        hotKeyManager = HotKeyManager(keyCode: HotKeyStore.keyCode, modifiers: HotKeyStore.modifiers) { [weak self] in
            self?.startCapture()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "MacCut")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "截圖 (\(HotKeyStore.displayString))", action: #selector(captureFromMenu), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        captureMenuItem = captureItem

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "偏好設定…", action: #selector(openPreferences), keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func captureFromMenu() {
        startCapture()
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            let controller = PreferencesWindowController()
            controller.onHotKeyChanged = { [weak self] keyCode, modifiers in
                self?.hotKeyManager?.updateHotKey(keyCode: keyCode, modifiers: modifiers)
                self?.captureMenuItem?.title = "截圖 (\(HotKeyStore.displayString))"
            }
            preferencesWindowController = controller
        }
        preferencesWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startCapture() {
        CaptureController.capture { [weak self] image in
            guard let self, let image else { return }
            let controller = AnnotationWindowController(image: image)
            controller.onFinish = { [weak self, weak controller] in
                guard let controller else { return }
                self?.openWindows.removeAll { $0 === controller }
            }
            self.openWindows.append(controller)
            controller.show()
        }
    }
}
