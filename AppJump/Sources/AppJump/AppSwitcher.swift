import AppKit
import ApplicationServices

/// 真正「跳過去」的那一層：把一組綁定變成「啟動／切換／隱藏／循環視窗」。
enum AppSwitcher {

    /// 執行一組綁定。
    /// - Parameters:
    ///   - binding: 要跳的目標。
    ///   - repeatAction: 目標已經在最前面時的行為。
    ///   - launchIfNotRunning: 沒在跑的話要不要順手開起來。
    static func perform(binding: AppBinding, repeatAction: RepeatAction, launchIfNotRunning: Bool) {
        guard let app = runningApplication(for: binding) else {
            if launchIfNotRunning { launch(binding: binding) }
            return
        }

        if isFrontmost(app) {
            switch repeatAction {
            case .hide:
                app.hide()
            case .cycleWindows:
                cycleWindows(of: app)
            case .none:
                break
            }
            return
        }

        activate(app)
    }

    // MARK: - 找 App

    /// 同一個 bundle id 可能有多個 process（例如開了第二份實例），挑還活著的第一個。
    private static func runningApplication(for binding: AppBinding) -> NSRunningApplication? {
        let byIdentifier = NSRunningApplication.runningApplications(withBundleIdentifier: binding.bundleIdentifier)
            .first { !$0.isTerminated }
        if let byIdentifier { return byIdentifier }

        // bundle id 對不上時（使用者手改設定、或 App 改過 id），退回用路徑比對。
        guard let path = binding.appPath else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated && $0.bundleURL?.standardizedFileURL == url
        }
    }

    /// 解析出 App 在磁碟上的位置：優先問 LaunchServices（App 搬家、改名都還找得到），找不到才用存下來的路徑。
    private static func applicationURL(for binding: AppBinding) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleIdentifier) {
            return url
        }
        guard let path = binding.appPath else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        // 比 pid 而不是比 bundle id：同一個 App 開兩份實例時才不會認錯。
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    // MARK: - 啟動與切換

    private static func launch(binding: AppBinding) {
        guard let url = applicationURL(for: binding) else {
            NSLog("[AppJump] 找不到 App：\(binding.bundleIdentifier)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("[AppJump] 啟動 \(binding.appName) 失敗：\(error.localizedDescription)")
            }
        }
    }

    private static func activate(_ app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }

        // macOS 14 起 .activateIgnoringOtherApps 明確失效（標頭上寫 "will have no effect"），
        // 只有舊系統需要帶；新系統帶了不會壞，但編譯器會警告，所以分開寫。
        if #available(macOS 14.0, *) {
            app.activate(options: [.activateAllWindows])
        } else {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        // 視窗全被縮到 Dock 時，activate 只會把選單列換過去、畫面上什麼都不會出現。
        // 有輔助使用權限的話順手還原一個視窗，這是最常被抱怨的「按了沒反應」。
        if AXPermission.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                restoreWindowIfAllMinimized(of: app)
            }
        }
    }

    // MARK: - 視窗操作（需要輔助使用權限）

    /// 在該 App 的視窗之間輪替，效果接近 ⌘`。
    ///
    /// AX 回傳的 kAXWindows 大致是由前到後的疊放順序，所以「把最後一個抬到最前面」
    /// 才會真的輪替（[A,B,C] → [C,A,B] → [B,C,A]）；抬第二個只會在兩個視窗間來回跳。
    private static func cycleWindows(of app: NSRunningApplication) {
        guard AXPermission.isTrusted else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = standardWindows(of: axApp)
        guard windows.count > 1, let last = windows.last else { return }
        raise(window: last, in: axApp)
    }

    private static func restoreWindowIfAllMinimized(of app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = standardWindows(of: axApp)
        guard !windows.isEmpty else { return }
        let hasVisible = windows.contains { !boolValue(of: $0, attribute: kAXMinimizedAttribute) }
        guard !hasVisible, let first = windows.first else { return }
        AXUIElementSetAttributeValue(first, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        raise(window: first, in: axApp)
    }

    private static func raise(window: AXUIElement, in axApp: AXUIElement) {
        if boolValue(of: window, attribute: kAXMinimizedAttribute) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// 只要一般視窗：面板、浮動工具列、通知不算，不然「循環視窗」會跳到奇怪的東西上。
    private static func standardWindows(of axApp: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return []
        }
        return windows.filter { window in
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                  let subrole = subroleValue as? String else {
                // 問不到 subrole 的就當一般視窗，寧可多留不要漏。
                return true
            }
            return subrole == (kAXStandardWindowSubrole as String)
        }
    }

    private static func boolValue(of element: AXUIElement, attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}
