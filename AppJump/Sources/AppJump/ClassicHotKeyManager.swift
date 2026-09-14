import AppKit
import Carbon.HIToolbox

/// 傳統全域組合鍵（⌃⌥S 這種）的註冊。
///
/// 走 Carbon RegisterEventHotKey，**不需要輔助使用權限**——這是刻意的：
/// 使用者還沒授權、或不想授權時，這條路仍然能用，App 不會整個變成廢物。
/// 代價是分不出左右修飾鍵，所以右 ⌘ 那套只能靠 TriggerTap。
///
/// 和 MacCut 的 HotKeyManager 差別在這裡要同時掛很多組，所以多一層 id → 綁定的對照表。
final class ClassicHotKeyManager {

    /// 某組熱鍵被按下，帶回對應綁定的 id。
    var onHotKey: ((UUID) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, bindingID: UUID)] = [:]
    private var nextID: UInt32 = 1

    private let signature = OSType(0x414A4D50) // 'AJMP'

    init() {
        installEventHandler()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let manager = Unmanaged<ClassicHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var receivedID = EventHotKeyID()
            GetEventParameter(eventRef,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &receivedID)
            manager.fire(id: receivedID.id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func fire(id: UInt32) {
        guard let entry = registered[id] else { return }
        onHotKey?(entry.bindingID)
    }

    /// 依目前設定重掛全部熱鍵。
    /// - Returns: 註冊失敗的綁定（多半是這組鍵已經被系統或別的 App 佔走了）。
    @discardableResult
    func reload(bindings: [AppBinding]) -> [AppBinding] {
        unregisterAll()

        var failed: [AppBinding] = []
        for binding in bindings {
            guard binding.isEnabled, let hotKey = binding.hotKey else { continue }

            let id = nextID
            nextID += 1
            let hotKeyID = EventHotKeyID(signature: signature, id: id)

            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotKey.keyCode),
                                             hotKey.carbonModifiers,
                                             hotKeyID,
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                registered[id] = (ref, binding.id)
            } else {
                failed.append(binding)
                NSLog("%@", "[AppJump] 註冊組合鍵 \(hotKey.displayString) 失敗（\(status)），可能已被其他 App 佔用")
            }
        }
        return failed
    }

    private func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
