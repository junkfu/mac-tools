import Carbon.HIToolbox
import AppKit

/// 包一層 Carbon 的全域快捷鍵 API（RegisterEventHotKey）。
/// 不需要 Accessibility 權限，系統層級攔截，優先權高於前景 App 的同組快捷鍵。
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D435554) /* 'MCUT' */, id: 1)

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        installEventHandler()
        updateHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var receivedID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID)
            if receivedID.id == manager.hotKeyID.id {
                manager.handler()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// 換一組快捷鍵：只需要重新 Register，事件處理器（installEventHandler）不用重裝。
    func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

enum HotKeyDefaults {
    /// 出廠預設 ⌘⇧X（呼應「cut」）。使用者可以在「偏好設定」裡改，改完存在 HotKeyStore。
    static let keyCode: UInt32 = UInt32(kVK_ANSI_X)
    static let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static var displayString: String { HotKeyStore.modifierSymbols(modifiers) + "X" }
}
