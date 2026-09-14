import Foundation

/// 筆記檔的存放、首次啟動的預設內容、讀取後的目前資料。
///
/// 檔案本身就是唯一真相來源——這裡不做任何「編輯」動作，使用者用自己的編輯器改檔案，
/// `HotkeyFileWatcher` 偵測到變動後呼叫 `reload()`，App 再讀一次就好。
final class HotkeyStore {
    static let shared = HotkeyStore()

    private(set) var groups: [HotkeyGroup] = []

    let fileURL: URL

    /// 有回呼就代表資料重新讀過一次（不管內容有沒有真的變），給需要重繪畫面的地方訂閱。
    var onReload: (() -> Void)?

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyLegend", isDirectory: true)
        fileURL = supportDir.appendingPathComponent("hotkeys.md")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        seedDefaultFileIfMissing()
        reload()
    }

    /// 筆記檔再大也不該超過這個數；超過就當成放錯檔，不要在拿到選單列圖示前把整份讀進記憶體。
    private static let maxFileSize = 1 << 20   // 1 MB

    func reload() {
        groups = HotkeyFileParser.parse(readNotes())
        onReload?()
    }

    private func readNotes() -> String {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > Self.maxFileSize {
            NSLog("%@", "[KeyLegend] 筆記檔超過 \(Self.maxFileSize) bytes，略過不讀：\(fileURL.path)")
            return ""
        }
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        // 有損解碼：夾一個壞 byte 只會變成 U+FFFD，不會讓整份筆記靜默變空。
        return String(decoding: data, as: UTF8.self)
    }

    private func seedDefaultFileIfMissing() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? Self.defaultTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static let defaultTemplate = """
    <!-- KeyLegend 熱鍵筆記：## 開一個分類，「按鍵: 說明」記一條熱鍵。改完存檔，長按 Option 就看得到最新內容。 -->

    ## 全域
    ⌥（長按）: 顯示這份熱鍵筆記
    ⌘⇧4: 螢幕截圖選取範圍

    ## VSCode
    ⌘P: 快速開檔
    ⌘⇧P: 命令面板
    ⌘⇧F: 全域搜尋

    ## Claude Code
    ⌘⇧X: MacCut 截圖標註（範例，改成你自己的）
    """
}
