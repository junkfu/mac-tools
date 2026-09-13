import AppKit

/// 長按 Option 時浮出的熱鍵筆記面板。
///
/// 面板完全不搶焦點、也不吃滑鼠事件——它只是「湊過來看一眼」的參考卡，不該影響使用者
/// 正在操作的前景 App。所以用 nonactivatingPanel + orderFrontRegardless，全程不呼叫
/// makeKey，還開了 ignoresMouseEvents。內容每次顯示都重新讀 HotkeyStore 現況並重建，
/// 這樣編輯筆記檔存檔後、下一次長按看到的就是最新內容，不用額外處理「資料有沒有變」。
final class OverlayWindowController {
    private var panel: NSPanel?

    func show() {
        let groups = HotkeyStore.shared.groups
        guard !groups.isEmpty else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let content = OverlayColumnsView(groups: groups)
        panel.contentView = content
        position(panel, contentSize: content.fittingSize)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func position(_ panel: NSPanel, contentSize: NSSize) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let width = min(contentSize.width, frame.width * 0.7, 900)
        let height = min(contentSize.height, frame.height * 0.6, 600)
        panel.setFrame(
            NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height),
            display: false
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // isFloatingPanel = true 要設的話務必在 level 之前——它會把 level 重設回
        // .floating（3），蓋掉這裡要的 .statusBar（25）。這個面板不需要它：
        // level + hidesOnDeactivate 已經足夠讓它一直浮在最上層、不會被切走。
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        return panel
    }
}
