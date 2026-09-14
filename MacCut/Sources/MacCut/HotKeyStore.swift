import Carbon.HIToolbox
import AppKit

/// 使用者自訂快捷鍵的存取（存在 UserDefaults，等同 App 的 preferences）。
enum HotKeyStore {
    private static let keyCodeKey = "MacCut.hotKeyCode"
    private static let modifiersKey = "MacCut.hotKeyModifiers"
    private static let displayKey = "MacCut.hotKeyDisplay"

    static var keyCode: UInt32 { stored?.keyCode ?? HotKeyDefaults.keyCode }
    static var modifiers: UInt32 { stored?.modifiers ?? HotKeyDefaults.modifiers }

    static var displayString: String {
        guard stored != nil else { return HotKeyDefaults.displayString }
        return UserDefaults.standard.string(forKey: displayKey) ?? HotKeyDefaults.displayString
    }

    /// 三個值一起驗證、一起採用。UserDefaults 是任何同使用者程序（或打錯的 `defaults write`）
    /// 都能改的：負數或超出範圍的 keyCode 若直接 `UInt32(_:)` 會在啟動時 trap，變成每次開都 crash；
    /// 修飾鍵為 0 則會讓一顆普通按鍵被全域攔走。任何一項不合理就整組退回預設值。
    private static var stored: (keyCode: UInt32, modifiers: UInt32)? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeKey) != nil, defaults.object(forKey: modifiersKey) != nil,
              let code = UInt32(exactly: defaults.integer(forKey: keyCodeKey)), code <= 0xFFFF,
              let mods = UInt32(exactly: defaults.integer(forKey: modifiersKey)),
              mods & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0
        else { return nil }
        return (code, mods)
    }

    static func save(keyCode: UInt32, modifiers: UInt32, display: String) {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: keyCodeKey)
        defaults.set(Int(modifiers), forKey: modifiersKey)
        defaults.set(display, forKey: displayKey)
    }

    static func resetToDefault() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keyCodeKey)
        defaults.removeObject(forKey: modifiersKey)
        defaults.removeObject(forKey: displayKey)
    }

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
}
