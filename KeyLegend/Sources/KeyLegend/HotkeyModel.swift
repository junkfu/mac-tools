import Foundation

/// 一條熱鍵筆記：按鍵組合 + 說明文字，都是使用者自己手打的自由格式字串。
struct HotkeyEntry {
    let keys: String
    let description: String
}

/// 一個分群（例如「VSCode」「全域」「Claude Code」），群名跟順序都由使用者在筆記檔裡自己決定。
struct HotkeyGroup {
    let name: String
    var entries: [HotkeyEntry]
}
