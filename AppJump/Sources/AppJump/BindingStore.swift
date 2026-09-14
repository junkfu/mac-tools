import Foundation

/// 設定的唯一真相來源：一份 `~/Library/Application Support/AppJump/config.json`。
///
/// 刻意不用 UserDefaults：這份東西使用者會想手改、想備份、想 diff。
/// 檔案格式的每個欄位在 Models.swift 都有 decodeIfPresent 的預設值，
/// 手改改壞一個欄位不會整份設定消失。
final class BindingStore {
    static let shared = BindingStore()

    private(set) var config: AppJumpConfig

    /// 設定變動後通知外面（AppDelegate 會重掛熱鍵、重畫選單）。
    var onChange: ((AppJumpConfig) -> Void)?

    let fileURL: URL
    private let directoryURL: URL

    /// 啟動時設定檔存在但解析失敗的錯誤訊息。非 nil 時，下一次 save() 會先把原檔改名備份，
    /// 使用者手改壞一個欄位不會因為「點了在 Finder 顯示」或勾了一個選項就整份不見。
    private(set) var loadError: String?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directoryURL = base.appendingPathComponent("AppJump", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("config.json")
        switch BindingStore.read(from: fileURL) {
        case .success(let loaded): config = loaded
        case .failure(let error):
            config = AppJumpConfig()
            if !(error is ReadError) { loadError = error.localizedDescription }
        }
    }

    /// 改設定的唯一入口：改完立刻寫檔並通知。
    func update(_ body: (inout AppJumpConfig) -> Void) {
        body(&config)
        save()
        onChange?(config)
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if loadError != nil {
                try backUpUnreadableFile()
                loadError = nil
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("%@", "[AppJump] 設定寫入失敗：\(error.localizedDescription)")
        }
    }

    /// 把解析不了的設定檔改名成 `config.json.broken-<時間>`，原內容留給使用者自己救。
    private func backUpUnreadableFile() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL.appendingPathExtension("broken-\(stamp)")
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        NSLog("%@", "[AppJump] 原設定檔解析失敗，已備份到 \(backupURL.path)")
    }

    private enum ReadError: LocalizedError {
        case missing
        var errorDescription: String? { "設定檔不存在" }
    }

    /// 檔案不存在也算 failure，但呼叫端只在意「存在卻讀不懂」的情況（見 loadError 的判斷）。
    private static func read(from url: URL) -> Result<AppJumpConfig, Error> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(ReadError.missing) }
        do {
            let data = try Data(contentsOf: url)
            return .success(try JSONDecoder().decode(AppJumpConfig.self, from: data))
        } catch {
            NSLog("%@", "[AppJump] 設定檔解析失敗，先用預設值：\(error.localizedDescription)")
            return .failure(error)
        }
    }
}
