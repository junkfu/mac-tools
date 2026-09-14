import Foundation

/// 把使用者手寫的筆記檔解析成分群資料。
///
/// 格式故意做到「隨手打就對」，沒有嚴謹的文法規則：
/// - `## 分類名稱` 開一個新分類。
/// - `按鍵: 說明`（在第一個冒號斷開）是一條熱鍵筆記。
/// - 開頭不是 `##` 就打的筆記，會歸進隱性的「未分類」。
/// - 空白行、看不懂的行（沒有冒號、或其他層級標題）一律略過，不會噴錯、不會讓整份筆記讀取失敗——
///   筆記本這種東西，打錯一行不該讓其他行也跟著不見。
enum HotkeyFileParser {
    static func parse(_ text: String) -> [HotkeyGroup] {
        var groups: [HotkeyGroup] = []
        var current: HotkeyGroup?

        // 用 isNewline 而不是 "\n"：Swift 把 "\r\n" 當成一個 Character，
        // 用 "\n" 切的話 CRLF 存檔的筆記會整份變成一行、靜默消失。
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("<!--") else { continue }

            if line.hasPrefix("## ") {
                if let current { groups.append(current) }
                let name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                current = HotkeyGroup(name: name.isEmpty ? "未命名分類" : name, entries: [])
                continue
            }
            // 其他層級的標題（單一 # 或 ### 以上）先當成裝飾，不解析成分類。
            guard !line.hasPrefix("#") else { continue }

            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let keys = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let description = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            guard !keys.isEmpty else { continue }

            let entry = HotkeyEntry(keys: keys, description: description)
            if current != nil {
                current!.entries.append(entry)
            } else {
                current = HotkeyGroup(name: "未分類", entries: [entry])
            }
        }
        if let current { groups.append(current) }

        return groups.filter { !$0.entries.isEmpty }
    }
}
