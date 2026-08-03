import AppKit
import Carbon.HIToolbox

/// keyCode ↔ 顯示文字的轉換。
///
/// 字母鍵不寫死對照表，改用 UCKeyTranslate 問系統目前的鍵盤佈局——
/// Dvorak／AZERTY 使用者看到的才會是他鍵帽上的字，而不是 QWERTY 的字。
enum KeyCodeMap {
    /// 沒有可見字元的鍵，只能自己列。
    private static let specialNames: [CGKeyCode: String] = [
        CGKeyCode(kVK_Return): "⏎",
        CGKeyCode(kVK_Tab): "⇥",
        CGKeyCode(kVK_Space): "空白鍵",
        CGKeyCode(kVK_Delete): "⌫",
        CGKeyCode(kVK_ForwardDelete): "⌦",
        CGKeyCode(kVK_Escape): "⎋",
        CGKeyCode(kVK_Home): "↖",
        CGKeyCode(kVK_End): "↘",
        CGKeyCode(kVK_PageUp): "⇞",
        CGKeyCode(kVK_PageDown): "⇟",
        CGKeyCode(kVK_LeftArrow): "←",
        CGKeyCode(kVK_RightArrow): "→",
        CGKeyCode(kVK_UpArrow): "↑",
        CGKeyCode(kVK_DownArrow): "↓",
        CGKeyCode(kVK_ANSI_KeypadEnter): "⌤",
        CGKeyCode(kVK_ANSI_KeypadClear): "⌧",
        CGKeyCode(kVK_F1): "F1", CGKeyCode(kVK_F2): "F2", CGKeyCode(kVK_F3): "F3",
        CGKeyCode(kVK_F4): "F4", CGKeyCode(kVK_F5): "F5", CGKeyCode(kVK_F6): "F6",
        CGKeyCode(kVK_F7): "F7", CGKeyCode(kVK_F8): "F8", CGKeyCode(kVK_F9): "F9",
        CGKeyCode(kVK_F10): "F10", CGKeyCode(kVK_F11): "F11", CGKeyCode(kVK_F12): "F12",
        CGKeyCode(kVK_F13): "F13", CGKeyCode(kVK_F14): "F14", CGKeyCode(kVK_F15): "F15",
        CGKeyCode(kVK_F16): "F16", CGKeyCode(kVK_F17): "F17", CGKeyCode(kVK_F18): "F18",
        CGKeyCode(kVK_F19): "F19", CGKeyCode(kVK_F20): "F20"
    ]

    /// 純修飾鍵不能拿來當「被觸發的那顆鍵」。
    private static let modifierKeyCodes: Set<CGKeyCode> = [
        CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand),
        CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption),
        CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl),
        CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift),
        CGKeyCode(kVK_CapsLock), CGKeyCode(kVK_Function)
    ]

    private static var cache: [CGKeyCode: String] = [:]
    private static var observerInstalled = false

    static func isModifierKey(_ keyCode: CGKeyCode) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    /// 這顆鍵在 UI 上顯示成什麼。
    static func displayName(for keyCode: CGKeyCode) -> String {
        if let special = specialNames[keyCode] { return special }
        installInputSourceObserverIfNeeded()
        if let cached = cache[keyCode] { return cached }
        let name = translate(keyCode: keyCode) ?? "鍵\(keyCode)"
        cache[keyCode] = name
        return name
    }

    /// 反查：使用者打「S」要對到哪個 keyCode（自動指派字母時用）。
    /// 掃過整個鍵盤問系統，所以一樣是跟著目前佈局走。
    static func keyCode(for character: Character) -> CGKeyCode? {
        let target = String(character).uppercased()
        for code in CGKeyCode(0)...CGKeyCode(127) where !isModifierKey(code) {
            if specialNames[code] != nil { continue }
            if translate(keyCode: code) == target { return code }
        }
        return nil
    }

    /// 適合拿來當觸發鍵的鍵：英數字母、數字、以及功能鍵。
    static var assignableLetterKeyCodes: [CGKeyCode] {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return letters.compactMap { keyCode(for: $0) }
    }

    // MARK: - Carbon 修飾鍵

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    static func modifierSymbols(_ carbonMods: UInt32) -> String {
        var symbols = ""
        if carbonMods & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonMods & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonMods & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonMods & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    // MARK: - UCKeyTranslate

    private static func translate(keyCode: CGKeyCode) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(paramErr) }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0, // 不帶修飾鍵，要的是鍵帽上的字
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        guard !text.isEmpty, text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return text.uppercased()
    }

    /// 使用者換輸入法／鍵盤佈局時把快取丟掉。
    private static func installInputSourceObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            cache.removeAll()
        }
    }
}
