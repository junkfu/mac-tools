import AppKit

/// 呼叫系統內建的 /usr/sbin/screencapture 做互動式框選。
/// 選取 UI 完全交給 macOS 原生實作（GPU 合成、零額外負擔），
/// 我們只負責在選完之後把圖讀進來、接手做標註。
///
/// 輸出走 $TMPDIR 下的隨機檔名，而不是 `-c` 直接進系統剪貼簿：剪貼簿是全系統共享的，
/// 原圖在打碼之前就會被剪貼簿歷史工具存到磁碟、被 Universal Clipboard 同步到別台裝置，
/// 按 Esc 取消也會留在那裡。$TMPDIR 是每個使用者私有（0700）的目錄，讀完立刻刪。
/// 只有使用者按 ⏎ 確認時，標註後的成品才會寫進剪貼簿。
enum CaptureController {
    private static var isCapturing = false

    static func capture(completion: @escaping (NSImage?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCut-\(UUID().uuidString).png", isDirectory: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i 互動框選, -s 限制只用滑鼠框選(不進入視窗擷取模式), -x 不播放快門音, -t png 輸出格式
        process.arguments = ["-i", "-s", "-x", "-t", "png", fileURL.path]

        process.terminationHandler = { _ in
            // 使用者按 Esc 取消時 screencapture 正常結束但不會建檔 → Data 讀不到 → nil。
            // 先整份讀進記憶體再刪檔，不讓 NSImage 留著檔案參照懶載入。
            let image = (try? Data(contentsOf: fileURL)).flatMap { NSImage(data: $0) }
            try? FileManager.default.removeItem(at: fileURL)
            DispatchQueue.main.async {
                isCapturing = false
                completion(image)
            }
        }

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            isCapturing = false
            completion(nil)
        }
    }
}
