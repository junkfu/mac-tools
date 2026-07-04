import Carbon.HIToolbox
import AppKit

/// 一顆按鈕：點下去進入錄製模式，按下想要的組合鍵就抓下來。
/// 用「local monitor」而不是 global monitor —— 錄製時偏好設定視窗本來就是 key window，
/// 不需要額外要求 Accessibility 權限，也不會誤吃系統其他地方的按鍵。
final class HotKeyRecorderControl: NSButton {
    /// keyCode 給 Carbon 用；carbonModifiers 給 Carbon 用；display 是給 UI 顯示的組合鍵文字。
    var onCapture: ((_ keyCode: UInt32, _ carbonModifiers: UInt32, _ display: String) -> Void)?

    private var isRecording = false
    private var monitor: Any?
    private var savedTitle: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(display: String) {
        title = display
        savedTitle = display
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        savedTitle = title
        title = "請按下新的快捷鍵…"

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
            return nil // 吃掉這個按鍵事件，不要繼續往下傳
        }
    }

    private func handle(event: NSEvent) {
        defer { stopRecording() }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = UInt32(event.keyCode)

        if keyCode == UInt32(kVK_Escape), mods.isEmpty {
            title = savedTitle
            return
        }

        let hasRequiredModifier = mods.contains(.command) || mods.contains(.option) || mods.contains(.control)
        guard hasRequiredModifier else {
            title = savedTitle
            NSSound.beep()
            return
        }

        let carbonMods = HotKeyStore.carbonModifiers(from: mods)
        let display = HotKeyStore.modifierSymbols(carbonMods) + (event.charactersIgnoringModifiers?.uppercased() ?? "?")
        title = display
        savedTitle = display
        onCapture?(keyCode, carbonMods, display)
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        stopRecording()
    }
}
