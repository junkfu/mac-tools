import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController!
    private var statusItem: NSStatusItem!
    private var moveToggleItem: NSMenuItem!
    private let store = ShelfStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.reload()
        controller = NotchWindowController(store: store)
        controller.show()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        controller.repositionToNotchScreen()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "NotchShelf")
            button.toolTip = "NotchShelf"
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "展開／收合暫存格", action: #selector(toggleShelf), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let openItem = NSMenuItem(title: "打開暫存資料夾", action: #selector(openStashFolder), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let moveItem = NSMenuItem(title: "拖出後從暫存移除（搬移模式）", action: #selector(toggleMoveOut), keyEquivalent: "")
        moveItem.target = self
        moveItem.state = store.removeAfterDrop ? .on : .off
        moveToggleItem = moveItem
        menu.addItem(moveItem)

        let clearItem = NSMenuItem(title: "清空暫存", action: #selector(clearStash), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "結束 NotchShelf", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleShelf() { controller.toggleExpand() }

    @objc private func openStashFolder() {
        NSWorkspace.shared.open(store.stashURL)
    }

    @objc private func toggleMoveOut() {
        store.removeAfterDrop.toggle()
        moveToggleItem.state = store.removeAfterDrop ? .on : .off
    }

    @objc private func clearStash() {
        store.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
