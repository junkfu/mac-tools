import AppKit

final class PreferencesWindowController: NSWindowController {
    private let recorder = HotKeyRecorderControl()

    /// 快捷鍵變更後呼叫，讓 AppDelegate 拿新的 keyCode/modifiers 去更新 HotKeyManager。
    var onHotKeyChanged: ((UInt32, UInt32) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacCut 偏好設定"
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)

        let label = NSTextField(labelWithString: "截圖快捷鍵：")
        recorder.configure(display: HotKeyStore.displayString)
        recorder.onCapture = { [weak self] keyCode, modifiers, display in
            HotKeyStore.save(keyCode: keyCode, modifiers: modifiers, display: display)
            self?.onHotKeyChanged?(keyCode, modifiers)
        }

        let resetButton = NSButton(title: "還原預設值", target: self, action: #selector(resetTapped))

        let row = NSStackView(views: [label, recorder, resetButton])
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString: "點按鈕後按下想要的組合鍵，至少要包含 ⌘／⌥／⌃ 其中一個；按 Esc 取消錄製。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 130))
        container.addSubview(row)
        container.addSubview(hint)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),

            hint.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
        window.contentView = container
    }

    @objc private func resetTapped() {
        HotKeyStore.resetToDefault()
        recorder.configure(display: HotKeyStore.displayString)
        onHotKeyChanged?(HotKeyStore.keyCode, HotKeyStore.modifiers)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
