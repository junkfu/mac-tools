import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = BindingStore.shared
    private let triggerTap = TriggerTap()
    private let classicHotKeys = ClassicHotKeyManager()
    private let overlay = ShortcutOverlayController()

    private var statusItem: NSStatusItem?
    private var preferences: PreferencesWindowController?
    private var permissionTimer: Timer?
    private var failedHotKeyIDs = Set<UUID>()
    private var didPromptForPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAlreadyRunning() else { return }

        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        wireEvents()
        apply(config: store.config)

        if let loadError = store.loadError {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "設定檔讀不懂，先用預設值啟動"
            alert.informativeText = "\(store.fileURL.path)\n\n\(loadError)\n\n原檔沒有被動。修好再重開 AppJump 就會回來；若在修好前改了任何設定，原檔會先被改名成 config.json.broken-<時間> 備份。"
            alert.runModal()
        }

        if store.config.bindings.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPreferences()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        triggerTap.stop()
    }

    /// 兩份 AppJump 同時跑（例如 /Applications 一份、開發目錄一份）會各自架一組 event tap，
    /// 同一次按鍵被處理兩次，看起來就像「切過去又切回來」。留先啟動的那份就好。
    private func terminateIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        guard !others.isEmpty else { return false }

        NSLog("[AppJump] 已有另一份 AppJump 在執行，結束這一份")
        NSApp.terminate(nil)
        return true
    }

    private func wireEvents() {
        triggerTap.onChord = { [weak self] keyCode in
            guard let self, let binding = self.store.config.binding(forChordKey: keyCode) else { return }
            self.overlay.hide()
            self.perform(binding)
        }
        triggerTap.onHoldChanged = { [weak self] isHolding in
            guard let self else { return }
            self.overlay.handleHold(isHolding, config: self.store.config)
        }
        classicHotKeys.onHotKey = { [weak self] id in
            guard let self,
                  let binding = self.store.config.bindings.first(where: { $0.id == id && $0.isEnabled }) else { return }
            self.perform(binding)
        }
        store.onChange = { [weak self] config in
            self?.apply(config: config)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "AppJump")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "AppJump — 快速切換應用程式"
        }
        statusItem = item
    }

    private func apply(config: AppJumpConfig) {
        let chordKeys = Set(config.bindings.compactMap { binding -> CGKeyCode? in
            guard binding.isEnabled, let code = binding.chordKeyCode else { return nil }
            return CGKeyCode(code)
        })
        triggerTap.update(modifier: config.triggerModifier, chordKeys: chordKeys)

        failedHotKeyIDs = Set(classicHotKeys.reload(bindings: config.bindings).map(\.id))
        ensureTriggerTapIfNeeded(hasChordBindings: !chordKeys.isEmpty)
        rebuildMenu(config: config)
        preferences?.reload(config: config, failedHotKeyIDs: failedHotKeyIDs)
    }

    private func ensureTriggerTapIfNeeded(hasChordBindings: Bool) {
        guard hasChordBindings else {
            triggerTap.stop()
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }

        if AXPermission.isTrusted {
            if !triggerTap.start() {
                NSLog("[AppJump] 已取得輔助使用權限，但仍無法建立鍵盤事件監聽")
            }
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else {
            triggerTap.stop()
            if !didPromptForPermission {
                didPromptForPermission = true
                AXPermission.requestWithPrompt()
            }
            startWaitingForPermission()
        }
    }

    /// 使用者可能隨時在系統設定裡打開開關，輪詢到之後整組重新套用即可，不需要重開 App。
    private func startWaitingForPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = AXPermission.waitForGrant { [weak self] in
            guard let self else { return }
            self.permissionTimer = nil
            self.apply(config: self.store.config)
        }
    }

    private func perform(_ binding: AppBinding) {
        AppSwitcher.perform(
            binding: binding,
            repeatAction: store.config.effectiveRepeatAction(for: binding),
            launchIfNotRunning: store.config.launchIfNotRunning
        )
    }

    private func rebuildMenu(config: AppJumpConfig) {
        let menu = NSMenu()

        if !config.bindings.isEmpty {
            for binding in config.bindings where binding.isEnabled {
                let title = "\(binding.triggerDisplay(modifier: config.triggerModifier))  \(binding.appName)"
                let item = NSMenuItem(title: title, action: #selector(switchFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = binding.id.uuidString
                item.image = AppCatalog.icon(forBundleIdentifier: binding.bundleIdentifier, size: 18)
                if failedHotKeyIDs.contains(binding.id) {
                    item.title += "  ⚠︎ 快捷鍵衝突"
                }
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        if config.bindings.contains(where: { $0.isEnabled && $0.chordKeyCode != nil }), !AXPermission.isTrusted {
            let permission = NSMenuItem(title: "⚠︎ 允許輔助使用權限…", action: #selector(requestPermission), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
            menu.addItem(.separator())
        }

        let preferencesItem = NSMenuItem(title: "設定…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let configItem = NSMenuItem(title: "在 Finder 顯示設定檔", action: #selector(revealConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "結束 AppJump", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func switchFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw),
              let binding = store.config.bindings.first(where: { $0.id == id }) else { return }
        perform(binding)
    }

    @objc private func openPreferences() {
        showPreferences()
    }

    private func showPreferences() {
        if preferences == nil {
            let controller = PreferencesWindowController(store: store)
            controller.onRequestPermission = { [weak self] in self?.requestPermission() }
            preferences = controller
        }
        preferences?.reload(config: store.config, failedHotKeyIDs: failedHotKeyIDs)
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
        // macOS 14 起 ignoringOtherApps 已被標記為即將淘汰，新系統走無參數版本。
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func requestPermission() {
        didPromptForPermission = true
        AXPermission.requestWithPrompt()
        AXPermission.openSystemSettings()
        startWaitingForPermission()
    }

    @objc private func revealConfig() {
        // 還沒動過設定的話檔案可能尚未落地，先寫一次再開 Finder。
        store.save()
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
