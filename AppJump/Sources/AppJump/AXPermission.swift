import AppKit
import ApplicationServices

/// 「輔助使用」權限的檢查、請求與等待。
///
/// 為什麼非要不可：右 ⌘ 這種「分左右的修飾鍵」只有 CGEventTap 攔得到，
/// 而能攔截／吞掉按鍵的 tap 一定要這個權限。沒有權限時 App 還是能用——
/// 傳統組合鍵走 Carbon RegisterEventHotKey，那條路不需要任何權限。
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
    /// tap 直接補建起來就會生效，所以這裡拿到 true 就回呼一次然後停掉。
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
        // 選單開著、視窗在拖動時 run loop 會切到 .eventTracking，預設 mode 的 timer 會停擺。
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
