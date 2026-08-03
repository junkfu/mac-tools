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

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directoryURL = base.appendingPathComponent("AppJump", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("config.json")
        config = BindingStore.read(from: fileURL) ?? AppJumpConfig()
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[AppJump] 設定寫入失敗：\(error.localizedDescription)")
        }
    }

    private static func read(from url: URL) -> AppJumpConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(AppJumpConfig.self, from: data)
        } catch {
            NSLog("[AppJump] 設定檔解析失敗，先用預設值：\(error.localizedDescription)")
            return nil
        }
    }
}
