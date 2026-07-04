import AppKit

/// 呼叫系統內建的 /usr/sbin/screencapture 做互動式框選。
/// 選取 UI 完全交給 macOS 原生實作（GPU 合成、零額外負擔），
/// 我們只負責在選完之後從剪貼簿讀圖、接手做標註。
enum CaptureController {
    private static var isCapturing = false

    static func capture(completion: @escaping (NSImage?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true

        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i 互動框選, -s 限制只用滑鼠框選(不進入視窗擷取模式), -x 不播放快門音, -c 輸出到剪貼簿
        process.arguments = ["-i", "-s", "-x", "-c"]

        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                isCapturing = false
                // 使用者按 Esc 取消時，screencapture 正常結束但剪貼簿不會變動
                guard pasteboard.changeCount != changeCountBefore,
                      let image = readImage(from: pasteboard) else {
                    completion(nil)
                    return
                }
                completion(image)
            }
        }

        do {
            try process.run()
        } catch {
            isCapturing = false
            completion(nil)
        }
    }

    private static func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) else {
            return nil
        }
        return NSImage(data: data)
    }
}
