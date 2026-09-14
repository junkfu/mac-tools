import AppKit
import Carbon.HIToolbox
import CoreGraphics
import IOKit.hidsystem

/// 攔「按住右 ⌘ + 某個鍵」的 CGEventTap。
///
/// 設計上的三個關鍵決定：
///
/// 1. **跑在自己的執行緒。** tap 的 callback 只要卡超過系統的容忍時間，整個 tap 會被
///    停用（kCGEventTapDisabledByTimeout），使用者的鍵盤就開始「偶爾漏鍵」。主執行緒
///    在開選單、拖視窗、跑動畫時都會忙，不能賭。所以 tap 掛在專屬執行緒的 run loop 上，
///    callback 只做「查表 + 決定吞不吞」，真正的動作全部 async 丟回主執行緒。
///
/// 2. **狀態盡量從事件本身重算。** 「右 ⌘ 現在是不是按著」直接讀事件自己帶的 flags，
///    不完全依賴累積的狀態——鎖定畫面、切換使用者、Mission Control 都可能讓某一次
///    keyUp 沒送到，純靠累積狀態會卡在「以為還按著」，之後每個字母都被吞掉。
///
/// 3. **只吞有綁定的鍵。** 按住右 ⌘ 按沒綁的鍵（⌘C、⌘V…）一律原樣放行，
///    右 ⌘ 才不會變成一顆廢鍵。
final class TriggerTap {

    /// 使用者按下「觸發鍵 + 有綁定的鍵」。回呼在主執行緒。
    var onChord: ((CGKeyCode) -> Void)?
    /// 觸發鍵按住／放開，給提示面板用。回呼在主執行緒。
    var onHoldChanged: ((Bool) -> Void)?

    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?

    // MARK: - 給 tap 執行緒讀的快照（主執行緒寫、tap 執行緒讀，用鎖保護）

    private let lock = NSLock()
    private var modifier: TriggerModifier = .rightCommand
    private var chordKeys: Set<CGKeyCode> = []

    /// 只有這個執行緒會碰的狀態，不需要鎖。
    private var isHolding = false
    private var swallowedKeys: Set<CGKeyCode> = []

    /// IOLLEvent.h 裡所有 device-dependent 位元的聯集，用來判斷「這顆事件到底有沒有帶左右資訊」。
    private static let allDeviceMasks: UInt64 =
        UInt64(NX_DEVICELCTLKEYMASK) | UInt64(NX_DEVICERCTLKEYMASK) |
        UInt64(NX_DEVICELSHIFTKEYMASK) | UInt64(NX_DEVICERSHIFTKEYMASK) |
        UInt64(NX_DEVICELCMDKEYMASK) | UInt64(NX_DEVICERCMDKEYMASK) |
        UInt64(NX_DEVICELALTKEYMASK) | UInt64(NX_DEVICERALTKEYMASK)

    private static let modifierFlagMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    // MARK: - 設定

    /// 換觸發鍵或改綁定後呼叫，tap 不用重建。
    func update(modifier: TriggerModifier, chordKeys: Set<CGKeyCode>) {
        lock.lock()
        self.modifier = modifier
        self.chordKeys = chordKeys
        lock.unlock()
    }

    // MARK: - 啟停

    /// - Returns: 失敗通常就是還沒拿到輔助使用權限。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // .cgSessionEventTap + .defaultTap 才吞得掉事件（listenOnly 只能看不能改）。
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<TriggerTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        isRunning = true
        startThread()
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let threadRunLoop {
            CFRunLoopStop(threadRunLoop)
        }
        thread?.cancel()
        // 等 tap 執行緒真的退出再拆 tap、清狀態：callback 可能正跑到一半，
        // 在主執行緒同時改 swallowedKeys / tap 會是資料競爭。run loop 一輪最多 1 秒。
        let deadline = Date().addingTimeInterval(2)
        while let thread, thread.isExecuting, Date() < deadline {
            usleep(1_000)
        }
        thread = nil
        threadRunLoop = nil

        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        runLoopSource = nil
        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil

        if isHolding {
            isHolding = false
            let callback = onHoldChanged
            DispatchQueue.main.async { callback?(false) }
        }
        swallowedKeys.removeAll()
    }

    private func startThread() {
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource, let tap = self.tap else { return }
            self.threadRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            // 用 run loop 自己的 while 迴圈，stop() 才停得下來。
            while !Thread.current.isCancelled {
                if CFRunLoopRunInMode(.defaultMode, 1.0, false) == .stopped { break }
            }
        }
        thread.name = "com.changfu.AppJump.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
    }

    // MARK: - Tap callback（跑在 tap 執行緒）

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系統把 tap 停掉了（callback 太慢，或使用者的輸入把它擠掉）。重開就好，
        // 不重開的話從這一刻起所有熱鍵就默默失效了——這是這類工具最惡名昭彰的 bug。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            NSLog("[AppJump] 鍵盤事件監聽曾被系統停用，已自動恢復")
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let modifier = self.modifier
        let chordKeys = self.chordKeys
        lock.unlock()

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        switch type {
        case .flagsChanged:
            updateHoldState(holding: isTriggerHeld(flags: flags, modifier: modifier, fallback: false))
            // flagsChanged 一律放行：右 ⌘ 對其他 App 來說還是一顆正常的 ⌘。
            return Unmanaged.passUnretained(event)

        case .keyDown:
            // 這顆鍵這次是原樣放行的，就不能再吞它的 keyUp——順手清掉上一輪殘留的紀錄。
            guard isTriggerHeld(flags: flags, modifier: modifier, fallback: isHolding),
                  // 夾帶了觸發鍵以外的修飾鍵（⌘⇧A 之類）就不是我們的和弦，放行給前景 App。
                  flags.intersection(TriggerTap.modifierFlagMask) == modifier.generalFlag,
                  chordKeys.contains(keyCode) else {
                swallowedKeys.remove(keyCode)
                return Unmanaged.passUnretained(event)
            }

            swallowedKeys.insert(keyCode)

            // 按著不放時系統會狂送重複的 keyDown。照做會變成不斷「顯示/隱藏」閃爍，
            // 所以重複的只吞不做事。
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let callback = onChord
                DispatchQueue.main.async { callback?(keyCode) }
            }
            return nil

        case .keyUp:
            // keyDown 被吞了，keyUp 就一定要跟著吞：只收到 keyUp 的 App 有機會當掉或狀態錯亂。
            if swallowedKeys.remove(keyCode) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// 觸發鍵現在按著嗎？
    ///
    /// 優先信事件自己帶的 device-dependent 位元（能分左右）。如果整包 flags 一個左右位元
    /// 都沒有（例如 Karabiner 之類工具合成出來的事件），才退回用累積的狀態判斷。
    private func isTriggerHeld(flags: CGEventFlags, modifier: TriggerModifier, fallback: Bool) -> Bool {
        guard flags.contains(modifier.generalFlag) else { return false }
        if flags.rawValue & TriggerTap.allDeviceMasks != 0 {
            return flags.rawValue & modifier.deviceMask != 0
        }
        return fallback
    }

    private func updateHoldState(holding: Bool) {
        guard holding != isHolding else { return }
        isHolding = holding
        // 這裡刻意不清 swallowedKeys：使用者常常先放開右 ⌘ 才放開字母，
        // 提早清掉的話那顆字母的 keyUp 會單獨漏給前景 App（有 keyUp 沒 keyDown）。
        let callback = onHoldChanged
        DispatchQueue.main.async { callback?(holding) }
    }

    deinit {
        stop()
    }
}
