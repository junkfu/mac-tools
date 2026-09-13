import AppKit
import ApplicationServices

/// 「輔助使用」權限的檢查、請求與等待。
///
/// 為什麼非要不可：長按判定要用 `NSEvent.addGlobalMonitorForEvents` 全程盯著
/// 別的 App 是前景時的按鍵事件，現行 macOS 上這類全域鍵盤事件監控（不管是
/// CGEventTap 還是 NSEvent 的全域監控）都會被輔助使用的權限守門，沒有例外。
enum AXPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 跳出系統的授權對話框（只有第一次、或使用者還沒決定時會出現）。
    @discardableResult
    static func requestWithPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 直接開到「系統設定 → 隱私權與安全性 → 輔助使用」。
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 等使用者去系統設定按下開關。
    ///
    /// 沒有「權限變更」的通知可以訂閱，只能輪詢；授權當下不需要重開 App，
    /// 監控直接補建起來就會生效，所以這裡拿到 true 就回呼一次然後停掉。
    static func waitForGrant(interval: TimeInterval = 1.0, onGrant: @escaping () -> Void) -> Timer? {
        guard !isTrusted else {
            onGrant()
            return nil
        }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            guard isTrusted else { return }
            timer.invalidate()
            onGrant()
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
