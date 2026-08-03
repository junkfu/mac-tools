import AppKit
import UniformTypeIdentifiers

/// 一個可以被綁定的 App。
struct InstalledApp: Equatable {
    let name: String
    let bundleIdentifier: String
    let url: URL

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

/// 查 App 的名稱與圖示。只在主執行緒使用。
enum AppCatalog {

    /// bundle id → App 資訊／圖示的快取。
    ///
    /// 選單、提示板、設定表格都會為每一組綁定要一次圖示，而 `NSWorkspace.icon(forFile:)`
    /// 每次都會真的去讀檔。按住觸發鍵後要在 0.4 秒內畫出十幾個 App 的提示板，
    /// 不快取就會看得出卡頓。
    private static var infoCache: [String: InstalledApp] = [:]
    private static var iconCache: [String: NSImage] = [:]

    /// 目前正在執行、而且看得到（有 Dock 圖示）的 App，通常是使用者最想綁的那些。
    static func runningApps() -> [InstalledApp] {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> InstalledApp? in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { return nil }
            return InstalledApp(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                bundleIdentifier: bundleID,
                                url: url)
        }

        var seen = Set<String>()
        return apps
            .filter { seen.insert($0.bundleIdentifier).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 從 bundle id 反查資訊（設定檔裡只存 id，UI 要顯示名字和圖示時用）。
    static func info(forBundleIdentifier bundleID: String) -> InstalledApp? {
        if let cached = infoCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let app = InstalledApp(name: displayName(of: url), bundleIdentifier: bundleID, url: url)
        infoCache[bundleID] = app
        return app
    }

    /// 給定一個 .app 路徑，讀出它的資訊。
    static func info(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        return InstalledApp(name: displayName(of: url), bundleIdentifier: bundleID, url: url)
    }

    /// 指定尺寸的 App 圖示，找不到 App 時給系統的通用圖示。
    static func icon(forBundleIdentifier bundleID: String, size: CGFloat) -> NSImage {
        let key = "\(bundleID)@\(size)"
        if let cached = iconCache[key] { return cached }

        let source = info(forBundleIdentifier: bundleID)?.icon ?? NSWorkspace.shared.icon(for: .application)
        let icon = (source.copy() as? NSImage) ?? source
        icon.size = NSSize(width: size, height: size)
        iconCache[key] = icon
        return icon
    }

    private static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// 幫新綁定挑一個還沒被佔用的鍵：先試 App 名稱的首字母，再試名稱裡的其他字母，
    /// 最後才隨便找一個沒人用的。挑不到就回 nil（讓使用者自己指定）。
    static func suggestKeyCode(for appName: String, taken: Set<CGKeyCode>) -> CGKeyCode? {
        let letters = appName.uppercased().filter { $0.isLetter && $0.isASCII }
        for letter in letters {
            if let code = KeyCodeMap.keyCode(for: letter), !taken.contains(code) {
                return code
            }
        }
        return KeyCodeMap.assignableLetterKeyCodes.first { !taken.contains($0) }
    }
}
