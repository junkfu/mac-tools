import AppKit
import Carbon.HIToolbox

/// 在設定視窗裡錄製「單鍵」或「一般全域組合鍵」的按鈕。
///
/// 只監聽 AppJump 自己的 key window，不需要額外權限。Esc 取消錄製；一般全域
/// 組合鍵至少要包含 ⌘／⌥／⌃ 其中一個，避免把普通打字鍵整顆搶走。
final class HotKeyRecorderButton: NSButton {
    enum Mode {
        case chord(prefix: () -> String)
        case classic
    }

    enum Result {
        case chord(UInt16)
        case classic(ClassicHotKey)
    }

    var onCapture: ((Result) -> Void)?

    private let mode: Mode
    private var monitor: Any?
    private var isRecording = false
    private var savedTitle = ""

    init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showChord(keyCode: UInt16?) {
        switch (mode, keyCode) {
        case let (.chord(prefix), .some(code)):
            setDisplay(prefix() + KeyCodeMap.displayName(for: CGKeyCode(code)))
        case (.chord, .none):
            setDisplay("未設定")
        default:
            break
        }
    }

    func showClassic(_ hotKey: ClassicHotKey?) {
        guard case .classic = mode else { return }
        setDisplay(hotKey?.displayString ?? "未設定")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording(restoreTitle: true) }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        savedTitle = title
        title = "請按下快捷鍵…"

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = CGKeyCode(event.keyCode)

        if keyCode == CGKeyCode(kVK_Escape), modifiers.isEmpty {
            stopRecording(restoreTitle: true)
            return
        }

        guard !KeyCodeMap.isModifierKey(keyCode) else {
            NSSound.beep()
            return
        }

        switch mode {
        case let .chord(prefix):
            let display = prefix() + KeyCodeMap.displayName(for: keyCode)
            stopRecording(restoreTitle: false)
            setDisplay(display)
            onCapture?(.chord(UInt16(keyCode)))

        case .classic:
            let hasRequiredModifier = modifiers.contains(.command)
                || modifiers.contains(.option)
                || modifiers.contains(.control)
            guard hasRequiredModifier else {
                NSSound.beep()
                return
            }
            let hotKey = ClassicHotKey(
                keyCode: UInt16(keyCode),
                carbonModifiers: KeyCodeMap.carbonModifiers(from: modifiers)
            )
            stopRecording(restoreTitle: false)
            setDisplay(hotKey.displayString)
            onCapture?(.classic(hotKey))
        }
    }

    private func setDisplay(_ display: String) {
        title = display
        savedTitle = display
    }

    private func stopRecording(restoreTitle: Bool) {
        guard isRecording || monitor != nil else { return }
        if restoreTitle { title = savedTitle }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        stopRecording(restoreTitle: false)
    }
}
