import AppKit
import UniformTypeIdentifiers

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onRequestPermission: (() -> Void)?

    private let store: BindingStore
    private var config: AppJumpConfig
    private var failedHotKeyIDs = Set<UUID>()
    private var editor: BindingEditorController?

    private let permissionStatus = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()
    private let triggerPopup = NSPopUpButton()
    private let repeatPopup = NSPopUpButton()
    private let launchMissingCheckbox = NSButton(checkboxWithTitle: "App 未執行時自動開啟", target: nil, action: nil)
    private let overlayCheckbox = NSButton(checkboxWithTitle: "按住觸發鍵時顯示快捷提示", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "登入時自動啟動 AppJump", target: nil, action: nil)
    private let tableView = NSTableView()
    private let editButton = NSButton(title: "編輯…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "移除", target: nil, action: nil)

    init(store: BindingStore) {
        self.store = store
        self.config = store.config

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppJump 設定"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 460)
        window.center()

        super.init(window: window)
        buildInterface(in: window)
        reload(config: config, failedHotKeyIDs: [])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(config: AppJumpConfig, failedHotKeyIDs: Set<UUID>) {
        self.config = config
        self.failedHotKeyIDs = failedHotKeyIDs

        triggerPopup.selectItem(at: TriggerModifier.allCases.firstIndex(of: config.triggerModifier) ?? 0)
        repeatPopup.selectItem(at: RepeatAction.allCases.firstIndex(of: config.defaultRepeatAction) ?? 0)
        launchMissingCheckbox.state = config.launchIfNotRunning ? .on : .off
        overlayCheckbox.state = config.overlayEnabled ? .on : .off
        loginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

        if AXPermission.isTrusted {
            permissionStatus.stringValue = "輔助使用權限：已允許"
            permissionStatus.textColor = .secondaryLabelColor
            permissionButton.title = "系統設定…"
        } else {
            permissionStatus.stringValue = "輔助使用權限：尚未允許，\(config.triggerModifier.displayName) 快捷鍵暫停"
            permissionStatus.textColor = .systemOrange
            permissionButton.title = "前往允許…"
        }

        tableView.reloadData()
        updateSelectionButtons()
    }

    // MARK: - UI

    private func buildInterface(in window: NSWindow) {
        guard let content = window.contentView else { return }

        permissionButton.target = self
        permissionButton.action = #selector(permissionTapped)
        permissionButton.bezelStyle = .rounded
        permissionStatus.font = .systemFont(ofSize: 12)
        let permissionRow = NSStackView(views: [permissionStatus, flexibleSpace(), permissionButton])
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        permissionRow.spacing = 10

        for modifier in TriggerModifier.allCases {
            triggerPopup.addItem(withTitle: modifier.displayName)
        }
        triggerPopup.target = self
        triggerPopup.action = #selector(globalSettingChanged)

        for action in RepeatAction.allCases {
            repeatPopup.addItem(withTitle: action.displayName)
        }
        repeatPopup.target = self
        repeatPopup.action = #selector(globalSettingChanged)

        launchMissingCheckbox.target = self
        launchMissingCheckbox.action = #selector(globalSettingChanged)
        overlayCheckbox.target = self
        overlayCheckbox.action = #selector(globalSettingChanged)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginSettingChanged)

        let triggerLabel = rightAlignedLabel("觸發鍵：")
        let repeatLabel = rightAlignedLabel("再次按下：")
        let grid = NSGridView(views: [
            [triggerLabel, triggerPopup],
            [repeatLabel, repeatPopup]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        let optionStack = NSStackView(views: [launchMissingCheckbox, overlayCheckbox, loginCheckbox])
        optionStack.orientation = .vertical
        optionStack.alignment = .leading
        optionStack.spacing = 8

        let globalBoxContent = NSStackView(views: [grid, optionStack])
        globalBoxContent.orientation = .horizontal
        globalBoxContent.alignment = .top
        globalBoxContent.spacing = 36
        globalBoxContent.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        let globalBox = box(title: "一般", content: globalBoxContent)

        configureTable()
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let bindingsTitle = NSTextField(labelWithString: "應用程式綁定")
        bindingsTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let addButton = NSButton(title: "＋ 新增 App", target: self, action: #selector(addTapped(_:)))
        editButton.target = self
        editButton.action = #selector(editTapped)
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        let buttonRow = NSStackView(views: [bindingsTitle, flexibleSpace(), addButton, editButton, deleteButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let root = NSStackView(views: [permissionRow, globalBox, buttonRow, scroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.setCustomSpacing(16, after: permissionRow)
        root.setCustomSpacing(16, after: globalBox)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            permissionRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            globalBox.widthAnchor.constraint(equalTo: root.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
    }

    private func configureTable() {
        let enabled = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabled.title = "啟用"
        enabled.width = 48
        enabled.minWidth = 48
        enabled.maxWidth = 48

        let app = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        app.title = "應用程式"
        app.width = 245
        app.minWidth = 170

        let trigger = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("trigger"))
        trigger.title = "快捷鍵"
        trigger.width = 205
        trigger.minWidth = 150

        let repeatAction = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repeat"))
        repeatAction.title = "已在最前面時"
        repeatAction.width = 140
        repeatAction.minWidth = 120

        tableView.addTableColumn(enabled)
        tableView.addTableColumn(app)
        tableView.addTableColumn(trigger)
        tableView.addTableColumn(repeatAction)
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 40
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editTapped)
    }

    private func box(title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.boxType = .primary
        box.contentView = content
        // NSBox 不會把替換後 contentView 的 intrinsic height 自動算進自己的高度。
        // 若沒有這條關係，外層 NSStackView 會把 box 壓到只剩標題框的 14pt，
        // 但 content 仍照原尺寸畫出來，於是和上下區塊重疊。
        box.heightAnchor.constraint(greaterThanOrEqualTo: content.heightAnchor, constant: 28).isActive = true
        return box
    }

    private func rightAlignedLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        config.bindings.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard config.bindings.indices.contains(row), let identifier = tableColumn?.identifier.rawValue else { return nil }
        let binding = config.bindings[row]

        switch identifier {
        case "enabled":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(enabledChanged(_:)))
            checkbox.state = binding.isEnabled ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(binding.id.uuidString)
            return cell(checkbox, centerHorizontally: true)

        case "app":
            let image = NSImageView()
            image.image = AppCatalog.icon(forBundleIdentifier: binding.bundleIdentifier, size: 28)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: 28),
                image.heightAnchor.constraint(equalToConstant: 28)
            ])
            let label = NSTextField(labelWithString: binding.appName)
            label.lineBreakMode = .byTruncatingTail
            let stack = NSStackView(views: [image, label])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            return cell(stack)

        case "trigger":
            let text = binding.triggerDisplay(modifier: config.triggerModifier)
            let label = NSTextField(labelWithString: failedHotKeyIDs.contains(binding.id) ? text + "  ⚠︎" : text)
            label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            if failedHotKeyIDs.contains(binding.id) {
                label.textColor = .systemOrange
                label.toolTip = "這組一般全域快捷鍵可能已被其他 App 使用"
            }
            return cell(label)

        case "repeat":
            let label = NSTextField(labelWithString: binding.repeatAction?.displayName ?? "跟隨全域")
            label.textColor = binding.repeatAction == nil ? .secondaryLabelColor : .labelColor
            return cell(label)

        default:
            return nil
        }
    }

    /// 表格列高 40pt，直接回傳裸元件的話內容會貼在儲存格左上角，所以統一包一層置中容器。
    private func cell(_ view: NSView, centerHorizontally: Bool = false) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        var constraints = [view.centerYAnchor.constraint(equalTo: container.centerYAnchor)]
        if centerHorizontally {
            constraints.append(view.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        } else {
            constraints.append(view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2))
            constraints.append(view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionButtons()
    }

    private func updateSelectionButtons() {
        let hasSelection = config.bindings.indices.contains(tableView.selectedRow)
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }

    // MARK: - Actions

    @objc private func permissionTapped() {
        onRequestPermission?()
    }

    @objc private func globalSettingChanged() {
        guard let trigger = TriggerModifier.allCases[safe: triggerPopup.indexOfSelectedItem],
              let repeatAction = RepeatAction.allCases[safe: repeatPopup.indexOfSelectedItem] else { return }
        store.update { config in
            config.triggerModifier = trigger
            config.defaultRepeatAction = repeatAction
            config.launchIfNotRunning = launchMissingCheckbox.state == .on
            config.overlayEnabled = overlayCheckbox.state == .on
        }
    }

    @objc private func loginSettingChanged() {
        let requested = loginCheckbox.state == .on
        do {
            try LaunchAtLogin.setEnabled(requested)
        } catch {
            loginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
            presentError(title: "無法更新登入項目", message: error.localizedDescription)
        }
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        store.update { config in
            guard let index = config.bindings.firstIndex(where: { $0.id == id }) else { return }
            config.bindings[index].isEnabled = sender.state == .on
        }
    }

    @objc private func addTapped(_ sender: NSButton) {
        let menu = NSMenu()
        let choose = NSMenuItem(title: "選擇應用程式…", action: #selector(chooseApplication), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)

        let running = AppCatalog.runningApps().filter { app in
            app.bundleIdentifier != Bundle.main.bundleIdentifier
                && !config.bindings.contains(where: { $0.bundleIdentifier == app.bundleIdentifier })
        }
        if !running.isEmpty {
            menu.addItem(.separator())
            let heading = NSMenuItem(title: "正在執行", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for app in running.prefix(12) {
                let item = NSMenuItem(title: app.name, action: #selector(addRunningApplication(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.url as NSURL
                let icon = app.icon.copy() as? NSImage
                icon?.size = NSSize(width: 18, height: 18)
                item.image = icon
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func chooseApplication() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "選擇要快速切換的應用程式"
        panel.prompt = "選擇"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard let app = AppCatalog.info(at: url) else {
                self?.presentError(title: "無法加入", message: "選取的項目不是有效的 macOS 應用程式。")
                return
            }
            self?.beginEditing(app: app)
        }
    }

    @objc private func addRunningApplication(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? NSURL,
              let app = AppCatalog.info(at: url as URL) else { return }
        beginEditing(app: app)
    }

    @objc private func editTapped() {
        let row = tableView.selectedRow
        guard config.bindings.indices.contains(row) else { return }
        let binding = config.bindings[row]
        let app = AppCatalog.info(forBundleIdentifier: binding.bundleIdentifier)
            ?? InstalledApp(
                name: binding.appName,
                bundleIdentifier: binding.bundleIdentifier,
                url: URL(fileURLWithPath: binding.appPath ?? "/Applications")
            )
        beginEditing(app: app, binding: binding)
    }

    @objc private func deleteTapped() {
        let row = tableView.selectedRow
        guard config.bindings.indices.contains(row), let window else { return }
        let binding = config.bindings[row]
        let alert = NSAlert()
        alert.messageText = "移除 \(binding.appName) 的快捷鍵？"
        alert.informativeText = "這只會刪除 AppJump 綁定，不會刪除應用程式。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.update { $0.bindings.removeAll { $0.id == binding.id } }
        }
    }

    private func beginEditing(app: InstalledApp, binding: AppBinding? = nil) {
        guard let window, editor == nil else { return }

        if binding == nil,
           let existing = config.bindings.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            if let row = config.bindings.firstIndex(where: { $0.id == existing.id }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            }
            beginEditing(app: app, binding: existing)
            return
        }

        var draft = binding ?? AppBinding(
            bundleIdentifier: app.bundleIdentifier,
            appName: app.name,
            appPath: app.url.path
        )
        if binding == nil {
            let taken = Set(config.bindings.compactMap { binding in
                binding.chordKeyCode.map { CGKeyCode($0) }
            })
            draft.chordKeyCode = AppCatalog.suggestKeyCode(for: app.name, taken: taken).map { UInt16($0) }
        }

        let controller = BindingEditorController(
            parentWindow: window,
            app: app,
            draft: draft,
            config: config
        )
        controller.onFinish = { [weak self] saved in
            guard let self else { return }
            self.editor = nil
            guard let saved else { return }
            self.store.update { config in
                if let index = config.bindings.firstIndex(where: { $0.id == saved.id }) {
                    config.bindings[index] = saved
                } else {
                    config.bindings.append(saved)
                }
            }
            if let row = self.store.config.bindings.firstIndex(where: { $0.id == saved.id }) {
                self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.tableView.scrollRowToVisible(row)
            }
        }
        editor = controller
        controller.present()
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - Binding editor

private final class BindingEditorController {
    var onFinish: ((AppBinding?) -> Void)?

    private weak var parentWindow: NSWindow?
    private let panel: NSPanel
    private let config: AppJumpConfig
    private var draft: AppBinding

    private let chordRecorder: HotKeyRecorderButton
    private let classicRecorder = HotKeyRecorderButton(mode: .classic)
    private let repeatPopup = NSPopUpButton()
    private let enabledCheckbox = NSButton(checkboxWithTitle: "啟用這組綁定", target: nil, action: nil)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(parentWindow: NSWindow, app: InstalledApp, draft: AppBinding, config: AppJumpConfig) {
        self.parentWindow = parentWindow
        self.draft = draft
        self.config = config
        chordRecorder = HotKeyRecorderButton(mode: .chord(prefix: { config.triggerModifier.chordPrefix }))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.bindingTitle(app: app, isNew: !config.bindings.contains(where: { $0.id == draft.id }))

        buildInterface(app: app)
        configureValues()
    }

    func present() {
        guard let parentWindow else { return }
        parentWindow.beginSheet(panel)
    }

    private func buildInterface(app: InstalledApp) {
        let icon = NSImageView(image: app.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52)
        ])
        let name = NSTextField(labelWithString: app.name)
        name.font = .systemFont(ofSize: 18, weight: .semibold)
        let bundleID = NSTextField(labelWithString: app.bundleIdentifier)
        bundleID.textColor = .secondaryLabelColor
        bundleID.font = .systemFont(ofSize: 11)
        let names = NSStackView(views: [name, bundleID])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 3
        let appRow = NSStackView(views: [icon, names])
        appRow.orientation = .horizontal
        appRow.alignment = .centerY
        appRow.spacing = 12

        chordRecorder.onCapture = { [weak self] result in
            guard case let .chord(code) = result else { return }
            self?.draft.chordKeyCode = code
            self?.clearError()
        }
        classicRecorder.onCapture = { [weak self] result in
            guard case let .classic(hotKey) = result else { return }
            self?.draft.hotKey = hotKey
            self?.clearError()
        }
        chordRecorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        classicRecorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let clearChord = NSButton(title: "清除", target: self, action: #selector(clearChordTapped))
        let clearClassic = NSButton(title: "清除", target: self, action: #selector(clearClassicTapped))
        let chordRow = NSStackView(views: [chordRecorder, clearChord])
        chordRow.orientation = .horizontal
        chordRow.spacing = 6
        let classicRow = NSStackView(views: [classicRecorder, clearClassic])
        classicRow.orientation = .horizontal
        classicRow.spacing = 6

        repeatPopup.addItem(withTitle: "跟隨全域設定")
        for action in RepeatAction.allCases { repeatPopup.addItem(withTitle: action.displayName) }

        let grid = NSGridView(views: [
            [rightAlignedLabel("\(config.triggerModifier.displayName) ＋ 按鍵："), chordRow],
            [rightAlignedLabel("一般全域快捷鍵："), classicRow],
            [rightAlignedLabel("已在最前面時："), repeatPopup]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        let hint = NSTextField(wrappingLabelWithString: "點按鈕後直接按下想要的鍵。一般全域快捷鍵需包含 ⌘、⌥ 或 ⌃；按 Esc 取消錄製。")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "儲存", target: self, action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let actions = NSStackView(views: [flexibleSpace(), cancel, save])
        actions.orientation = .horizontal
        actions.spacing = 8

        let root = NSStackView(views: [appRow, grid, enabledCheckbox, hint, errorLabel, actions])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.setCustomSpacing(20, after: appRow)
        root.translatesAutoresizingMaskIntoConstraints = false
        guard let content = panel.contentView else { return }
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            grid.widthAnchor.constraint(equalTo: root.widthAnchor),
            hint.widthAnchor.constraint(equalTo: root.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            actions.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func configureValues() {
        chordRecorder.showChord(keyCode: draft.chordKeyCode)
        classicRecorder.showClassic(draft.hotKey)
        if let repeatAction = draft.repeatAction,
           let index = RepeatAction.allCases.firstIndex(of: repeatAction) {
            repeatPopup.selectItem(at: index + 1)
        } else {
            repeatPopup.selectItem(at: 0)
        }
        enabledCheckbox.state = draft.isEnabled ? .on : .off
    }

    @objc private func clearChordTapped() {
        draft.chordKeyCode = nil
        chordRecorder.showChord(keyCode: nil)
        clearError()
    }

    @objc private func clearClassicTapped() {
        draft.hotKey = nil
        classicRecorder.showClassic(nil)
        clearError()
    }

    @objc private func cancelTapped() {
        finish(nil)
    }

    @objc private func saveTapped() {
        draft.isEnabled = enabledCheckbox.state == .on
        if repeatPopup.indexOfSelectedItem == 0 {
            draft.repeatAction = nil
        } else {
            draft.repeatAction = RepeatAction.allCases[safe: repeatPopup.indexOfSelectedItem - 1]
        }

        guard draft.chordKeyCode != nil || draft.hotKey != nil else {
            showError("請至少設定一組快捷鍵。")
            return
        }
        if let key = draft.chordKeyCode,
           let conflict = config.bindings.first(where: { $0.id != draft.id && $0.chordKeyCode == key }) {
            showError("\(config.triggerModifier.chordPrefix)\(KeyCodeMap.displayName(for: CGKeyCode(key))) 已經指定給 \(conflict.appName)。")
            return
        }
        if let hotKey = draft.hotKey,
           let conflict = config.bindings.first(where: { $0.id != draft.id && $0.hotKey == hotKey }) {
            showError("\(hotKey.displayString) 已經指定給 \(conflict.appName)。")
            return
        }
        finish(draft)
    }

    private func finish(_ result: AppBinding?) {
        if let parentWindow {
            parentWindow.endSheet(panel)
        } else {
            panel.orderOut(nil)
        }
        onFinish?(result)
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        NSSound.beep()
    }

    private func clearError() {
        errorLabel.stringValue = ""
    }

    private func rightAlignedLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private static func bindingTitle(app: InstalledApp, isNew: Bool) -> String {
        isNew ? "新增 \(app.name) 快捷鍵" : "編輯 \(app.name) 快捷鍵"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
