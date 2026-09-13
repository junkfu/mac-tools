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

    func reload() {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        groups = HotkeyFileParser.parse(text)
        onReload?()
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
