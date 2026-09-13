import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HotkeyStore.shared
    private let holdMonitor = OptionHoldMonitor()
    private let overlay = OverlayWindowController()

    private var statusItem: NSStatusItem?
    private var fileWatcher: HotkeyFileWatcher?
    private var permissionTimer: Timer?
    private var didPromptForPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAlreadyRunning() else { return }

        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        wireEvents()
        fileWatcher = HotkeyFileWatcher(url: store.fileURL) { [weak self] in
            self?.store.reload()
        }
        ensureMonitorIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        holdMonitor.stop()
    }

    /// 兩份 KeyLegend 同時跑，長按判定會各報一次，看起來就像面板閃爍。留先啟動的那份就好。
    private func terminateIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        guard !others.isEmpty else { return false }

        NSLog("[KeyLegend] 已有另一份 KeyLegend 在執行，結束這一份")
        NSApp.terminate(nil)
        return true
    }

    private func wireEvents() {
        holdMonitor.onHoldChanged = { [weak self] isHolding in
            if isHolding {
                self?.overlay.show()
            } else {
                self?.overlay.hide()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "option", accessibilityDescription: "KeyLegend")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "KeyLegend — 長按 Option 看熱鍵筆記"
        }
        rebuildMenu()
        statusItem = item
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let editItem = NSMenuItem(title: "編輯熱鍵筆記…", action: #selector(editNotes), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let revealItem = NSMenuItem(title: "在 Finder 顯示筆記檔", action: #selector(revealNotes), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        if !AXPermission.isTrusted {
            let permissionItem = NSMenuItem(title: "⚠︎ 允許輔助使用權限…", action: #selector(requestPermission), keyEquivalent: "")
            permissionItem.target = self
            menu.addItem(permissionItem)
            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(title: "結束 KeyLegend", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func ensureMonitorIfNeeded() {
        if AXPermission.isTrusted {
            if !holdMonitor.start() {
                NSLog("[KeyLegend] 已取得輔助使用權限，但仍無法建立鍵盤事件監聽")
            }
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else {
            holdMonitor.stop()
            if !didPromptForPermission {
                didPromptForPermission = true
                AXPermission.requestWithPrompt()
            }
            startWaitingForPermission()
        }
        rebuildMenu()
    }

    /// 使用者可能隨時在系統設定裡打開開關，輪詢到之後重新套用即可，不需要重開 App。
    private func startWaitingForPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = AXPermission.waitForGrant { [weak self] in
            guard let self else { return }
            self.permissionTimer = nil
            self.ensureMonitorIfNeeded()
        }
    }

    @objc private func editNotes() {
        // 還沒動過的話檔案這時候一定已經存在（HotkeyStore 啟動時就會補上預設內容）。
        NSWorkspace.shared.open(store.fileURL)
    }

    @objc private func revealNotes() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func requestPermission() {
        didPromptForPermission = true
        AXPermission.requestWithPrompt()
        AXPermission.openSystemSettings()
        startWaitingForPermission()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
