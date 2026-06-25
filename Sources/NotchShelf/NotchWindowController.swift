import AppKit

/// A non-activating floating panel: clicks/drags work without stealing focus
/// from the frontmost app, and it never becomes key/main.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Positions the panel over the notch and animates between the collapsed
/// "chin" and the expanded shelf.
final class NotchWindowController {
    let panel: NotchPanel
    let rootView: ShelfRootView
    private let store: ShelfStore

    private let collapsedExtraWidth: CGFloat = 56
    private let expandedSize = NSSize(width: 360, height: 172)

    /// Set while an item is being dragged out, so we don't collapse mid-drag.
    var isDraggingOut = false

    init(store: ShelfStore) {
        self.store = store
        rootView = ShelfRootView(store: store)
        panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = rootView

        rootView.controller = self
        rootView.refresh()   // now that controller is wired, rebuild chips with it
    }

    func show() {
        repositionToNotchScreen()
        panel.orderFrontRegardless()
    }

    // MARK: - Geometry

    /// Prefer a screen that actually has a notch; otherwise the main screen.
    var targetScreen: NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func notchHeight(on screen: NSScreen) -> CGFloat {
        max(screen.safeAreaInsets.top, 32)
    }

    func notchWidth(on screen: NSScreen) -> CGFloat {
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let w = screen.frame.width - l.width - r.width
            if w > 40 { return w }
        }
        return 180
    }

    func collapsedFrame(on screen: NSScreen) -> NSRect {
        let w = (notchWidth(on: screen) + collapsedExtraWidth) / 2   // 收合時的小條，約瀏海一半寬
        let h = notchHeight(on: screen)   // 貼齊瀏海下緣，不往下凸出
        let x = screen.frame.midX - w / 2
        let y = screen.frame.maxY - h
        return NSRect(x: x, y: y, width: w, height: h)
    }

    func expandedFrame(on screen: NSScreen) -> NSRect {
        let w = expandedSize.width
        let h = expandedSize.height
        let x = screen.frame.midX - w / 2
        let y = screen.frame.maxY - h
        return NSRect(x: x, y: y, width: w, height: h)
    }

    func repositionToNotchScreen() {
        let screen = targetScreen
        rootView.notchHeight = notchHeight(on: screen)
        let frame = rootView.isExpanded ? expandedFrame(on: screen) : collapsedFrame(on: screen)
        panel.setFrame(frame, display: true)
        rootView.needsLayout = true
        rootView.layoutSubtreeIfNeeded()
    }

    // MARK: - Expand / collapse

    func expand() {
        guard !rootView.isExpanded else { return }
        rootView.isExpanded = true
        let screen = targetScreen
        rootView.notchHeight = notchHeight(on: screen)
        animate(to: expandedFrame(on: screen))
    }

    func collapse() {
        guard rootView.isExpanded else { return }
        rootView.isExpanded = false
        let screen = targetScreen
        animate(to: collapsedFrame(on: screen))
    }

    func toggleExpand() {
        if rootView.isExpanded { collapse() } else { expand() }
    }

    private func animate(to frame: NSRect) {
        rootView.updateVisibility()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            self?.rootView.needsLayout = true
            self?.rootView.layoutSubtreeIfNeeded()
        })
    }
}
