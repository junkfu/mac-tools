import Carbon.HIToolbox
import AppKit

/// 使用者自訂快捷鍵的存取（存在 UserDefaults，等同 App 的 preferences）。
enum HotKeyStore {
    private static let keyCodeKey = "MacCut.hotKeyCode"
    private static let modifiersKey = "MacCut.hotKeyModifiers"
    private static let displayKey = "MacCut.hotKeyDisplay"

    static var keyCode: UInt32 {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeKey) != nil else { return HotKeyDefaults.keyCode }
        return UInt32(defaults.integer(forKey: keyCodeKey))
    }

    static var modifiers: UInt32 {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: modifiersKey) != nil else { return HotKeyDefaults.modifiers }
        return UInt32(defaults.integer(forKey: modifiersKey))
    }

    static var displayString: String {
        UserDefaults.standard.string(forKey: displayKey) ?? HotKeyDefaults.displayString
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
