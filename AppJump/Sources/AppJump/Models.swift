import CoreGraphics
import Foundation
import IOKit.hidsystem

/// 「按住不放」的那顆觸發鍵。
///
/// Carbon 的 RegisterEventHotKey 與 NSEvent.modifierFlags 都只看得到「有沒有按 ⌘」，
/// 分不出左右；要分左右只能讀 CGEvent 的 device-dependent flag（IOLLEvent.h 的 NX_DEVICE*KEYMASK），
/// 這也是整個 App 必須自己架 CGEventTap、而不能沿用 MacCut 那套 Carbon 熱鍵的原因。
enum TriggerModifier: String, Codable, CaseIterable {
    case rightCommand
    case leftCommand
    case rightOption
    case leftOption
    case rightControl
    case leftControl

    /// 這顆鍵按下時，CGEvent flags 裡會亮起來的那個 device-dependent bit。
    var deviceMask: UInt64 {
        switch self {
        case .rightCommand: return UInt64(NX_DEVICERCMDKEYMASK)
        case .leftCommand: return UInt64(NX_DEVICELCMDKEYMASK)
        case .rightOption: return UInt64(NX_DEVICERALTKEYMASK)
        case .leftOption: return UInt64(NX_DEVICELALTKEYMASK)
        case .rightControl: return UInt64(NX_DEVICERCTLKEYMASK)
        case .leftControl: return UInt64(NX_DEVICELCTLKEYMASK)
        }
    }

    /// 對應的「不分左右」旗標，用來過濾「有沒有夾帶其他修飾鍵」。
    var generalFlag: CGEventFlags {
        switch self {
        case .rightCommand, .leftCommand: return .maskCommand
        case .rightOption, .leftOption: return .maskAlternate
        case .rightControl, .leftControl: return .maskControl
        }
    }

    /// 顯示快捷鍵時用的前綴。刻意帶上「左／右」——不然表格裡的 ⌘C 看起來
    /// 就跟系統原生的 ⌘C 一模一樣，而「分左右」正是這個 App 的全部重點。
    var chordPrefix: String {
        switch self {
        case .rightCommand: return "右⌘"
        case .leftCommand: return "左⌘"
        case .rightOption: return "右⌥"
        case .leftOption: return "左⌥"
        case .rightControl: return "右⌃"
        case .leftControl: return "左⌃"
        }
    }

    var displayName: String {
        switch self {
        case .rightCommand: return "右 ⌘"
        case .leftCommand: return "左 ⌘"
        case .rightOption: return "右 ⌥"
        case .leftOption: return "左 ⌥"
        case .rightControl: return "右 ⌃"
        case .leftControl: return "左 ⌃"
        }
    }
}

/// 目標 App 已經在最前面時，再按一次同一個鍵要做什麼。
enum RepeatAction: String, Codable, CaseIterable {
    /// 隱藏該 App（rcmd 的預設行為，等於用同一顆鍵 toggle）。
    case hide
    /// 在該 App 的視窗之間輪替，像 ⌘` 那樣。
    case cycleWindows
    /// 什麼都不做。
    case none

    var displayName: String {
        switch self {
        case .hide: return "隱藏 App"
        case .cycleWindows: return "循環視窗"
        case .none: return "不動作"
        }
    }
}

/// 傳統組合鍵（⌃⌥S 這種），走 Carbon RegisterEventHotKey，不需要輔助使用權限。
struct ClassicHotKey: Codable, Equatable {
    var keyCode: UInt16
    /// Carbon 的 modifier 位元（cmdKey / optionKey / controlKey / shiftKey）。
    var carbonModifiers: UInt32

    var displayString: String {
        KeyCodeMap.modifierSymbols(carbonModifiers) + KeyCodeMap.displayName(for: CGKeyCode(keyCode))
    }
}

/// 一組綁定：一個 App，配上「觸發鍵 + 字母」和／或一組傳統組合鍵。
struct AppBinding: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// 主要識別方式。App 被搬家、改名都還找得到。
    var bundleIdentifier: String
    /// 顯示用的名稱快取（App 沒安裝時仍看得到自己綁過什麼）。
    var appName: String
    /// 後備路徑：bundle id 查不到時用它，也方便使用者手動編輯 JSON 時對照。
    var appPath: String?
    /// 「按住觸發鍵 + 這顆鍵」。nil 表示這組綁定只用傳統組合鍵。
    var chordKeyCode: UInt16?
    /// 傳統全域組合鍵。nil 表示沒設。
    var hotKey: ClassicHotKey?
    /// 這組綁定專屬的重複按行為；nil = 跟隨全域預設。
    var repeatAction: RepeatAction?
    var isEnabled: Bool = true

    /// 手動編輯 JSON 時少寫欄位也不會整份壞掉。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? bundleIdentifier
        appPath = try c.decodeIfPresent(String.self, forKey: .appPath)
        chordKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .chordKeyCode)
        hotKey = try c.decodeIfPresent(ClassicHotKey.self, forKey: .hotKey)
        repeatAction = try c.decodeIfPresent(RepeatAction.self, forKey: .repeatAction)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    init(bundleIdentifier: String,
         appName: String,
         appPath: String?,
         chordKeyCode: UInt16? = nil,
         hotKey: ClassicHotKey? = nil,
         repeatAction: RepeatAction? = nil,
         isEnabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.appPath = appPath
        self.chordKeyCode = chordKeyCode
        self.hotKey = hotKey
        self.repeatAction = repeatAction
        self.isEnabled = isEnabled
    }

    /// 表格裡「觸發方式」那一欄要顯示的字。
    func triggerDisplay(modifier: TriggerModifier) -> String {
        var parts: [String] = []
        if let chordKeyCode {
            parts.append(modifier.chordPrefix + KeyCodeMap.displayName(for: CGKeyCode(chordKeyCode)))
        }
        if let hotKey {
            parts.append(hotKey.displayString)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: "　")
    }
}

/// 整份設定檔。存成 JSON，使用者可以直接手改。
struct AppJumpConfig: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = AppJumpConfig.currentSchemaVersion
    /// 按住哪顆鍵當觸發鍵，預設右 ⌘（rcmd 的做法）。
    var triggerModifier: TriggerModifier = .rightCommand
    /// 沒有另外指定的綁定，重複按時做什麼。
    var defaultRepeatAction: RepeatAction = .hide
    /// 按住觸發鍵不放時，要不要浮出提示面板。
    var overlayEnabled: Bool = true
    /// 按住多久才浮出提示面板（秒）。
    var overlayDelay: Double = 0.4
    /// 目標 App 沒在執行時，要不要幫忙開起來。
    var launchIfNotRunning: Bool = true
    var bindings: [AppBinding] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? AppJumpConfig.currentSchemaVersion
        triggerModifier = try c.decodeIfPresent(TriggerModifier.self, forKey: .triggerModifier) ?? .rightCommand
        defaultRepeatAction = try c.decodeIfPresent(RepeatAction.self, forKey: .defaultRepeatAction) ?? .hide
        overlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? true
        overlayDelay = try c.decodeIfPresent(Double.self, forKey: .overlayDelay) ?? 0.4
        launchIfNotRunning = try c.decodeIfPresent(Bool.self, forKey: .launchIfNotRunning) ?? true
        bindings = try c.decodeIfPresent([AppBinding].self, forKey: .bindings) ?? []
    }

    /// 找出綁在「觸發鍵 + keyCode」上的那組。
    func binding(forChordKey keyCode: CGKeyCode) -> AppBinding? {
        bindings.first { $0.isEnabled && $0.chordKeyCode == UInt16(keyCode) }
    }

    /// 這組綁定實際要用的重複按行為。
    func effectiveRepeatAction(for binding: AppBinding) -> RepeatAction {
        binding.repeatAction ?? defaultRepeatAction
    }
}
