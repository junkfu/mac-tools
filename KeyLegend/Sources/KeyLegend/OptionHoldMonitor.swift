import AppKit

/// 偵測「單獨長按 Option、沒有夾雜其他鍵」的狀態機。
///
/// 只用 NSEvent 的全域監控（`addGlobalMonitorForEvents`），不架 CGEventTap——
/// 這裡從頭到尾只是「看」，從不「吞」按鍵，全域監控本來就攔不下事件，
/// 用它可以省掉 AppJump 那套 CGEventTap 執行緒／run loop／逾時重啟的機器。
/// 代價跟 tap 一樣：現行 macOS 上兩者都需要「輔助使用」權限才收得到事件
/// （這也是為什麼跟 MacCut 那套不需權限的 Carbon 熱鍵是完全不同的路）。
final class OptionHoldMonitor {
    /// 長按判定成立／取消時呼叫，回呼都在主執行緒（NSEvent 全域監控本來就在主執行緒送事件）。
    var onHoldChanged: ((Bool) -> Void)?

    /// 按著不放要多久才算「長按」，而不是路過 Option 修飾一個真正的快捷鍵（⌥Tab、⌥點按…）。
    private static let holdDelay: TimeInterval = 0.35

    private(set) var isRunning = false
    private var isHolding = false
    private var armTimer: Timer?
    private var globalMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?

    /// - Returns: 失敗通常就是還沒拿到輔助使用權限。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        // 兩個資源（monitor、observer）要嘛一起註冊、要嘛一起清掉——先把 isRunning 標成
        // true，才能保證不管下面 globalMonitor 拿不拿得到，stop() 都一定會真的執行清理，
        // 不會因為「isRunning 還是 false」就把 appSwitchObserver 漏掉沒解除註冊。
        isRunning = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
        // 切換到別的 App 時面板該立刻收起——使用者這時候的注意力已經不在原本那個畫面了。
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cancel()
        }

        return globalMonitor != nil
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        cancel()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if pressed == .option {
                arm()
            } else {
                // 放開了 Option，或是有其他修飾鍵一起按著（⌘⌥、⇧⌥…）——後者代表這是一個
                // 正在進行中的真實快捷鍵，不該被我們的長按判定攔下來。
                cancel()
            }
        case .keyDown:
            // 按著 Option 的同時又按了別的鍵，就是真的快捷鍵（⌥Tab、⌥⌫…），不是單純長按。
            cancel()
        default:
            break
        }
    }

    /// 剛好只按著 Option、沒有其他鍵：起一個計時器，過了門檻還維持這個狀態才真的算長按。
    private func arm() {
        guard armTimer == nil, !isHolding else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
            self?.armTimer = nil
            self?.setHolding(true)
        }
        // 選單開著、視窗在拖動時 run loop 會切到 .eventTracking，預設 mode 的 timer 會停擺。
        RunLoop.main.add(timer, forMode: .common)
        armTimer = timer
    }

    /// 放開 Option、按了別的鍵、或切換了 App——不管長按判定成立了沒，一律回到沒按的狀態。
    private func cancel() {
        armTimer?.invalidate()
        armTimer = nil
        setHolding(false)
    }

    private func setHolding(_ holding: Bool) {
        guard holding != isHolding else { return }
        isHolding = holding
        onHoldChanged?(holding)
    }

    deinit {
        stop()
    }
}
