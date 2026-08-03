import AppKit

/// 按住觸發鍵一小段時間後浮出的快捷提示板。
///
/// 面板必須完全不搶焦點——使用者正按著右 ⌘ 等著按下一個字母，
/// 只要面板變成 key window，那顆字母就會跑到面板身上而不是被 tap 攔到。
/// 所以用 nonactivatingPanel + orderFrontRegardless，全程不呼叫 makeKey。
final class ShortcutOverlayController {
    private var panel: NSPanel?
    private var pendingShow: DispatchWorkItem?
    /// 目前面板畫的是哪一份綁定；沒變就不重建 view，直接重用。
    private var renderedSignature: String?

    func handleHold(_ isHolding: Bool, config: AppJumpConfig) {
        pendingShow?.cancel()
        pendingShow = nil

        guard isHolding, config.overlayEnabled else {
            hide()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.show(config: config)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, config.overlayDelay), execute: work)
    }

    func hide() {
        pendingShow?.cancel()
        pendingShow = nil
        // 不做淡出：切過去的 App 應該立刻是畫面主角，面板不該還在上面殘留。
        panel?.orderOut(nil)
    }

    private func show(config: AppJumpConfig) {
        let bindings = config.bindings.filter { $0.isEnabled && $0.chordKeyCode != nil }
        guard !bindings.isEmpty else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let signature = Self.signature(for: bindings, modifier: config.triggerModifier)
        if signature != renderedSignature || panel.contentView == nil {
            let content = makeContent(bindings: bindings, modifier: config.triggerModifier)
            panel.contentView = content
            panel.setContentSize(content.fittingSize)
            renderedSignature = signature
        }

        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + max(64, frame.height * 0.17)
        ))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 選單列層級，全螢幕 App 上面也蓋得住。
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        return panel
    }

    private func makeContent(bindings: [AppBinding], modifier: TriggerModifier) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true

        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let columns = min(6, max(1, bindings.count))
        var row: [NSView] = []
        for binding in bindings {
            row.append(tile(for: binding, modifier: modifier))
            if row.count == columns {
                grid.addRow(with: row)
                row = []
            }
        }
        if !row.isEmpty {
            while row.count < columns { row.append(NSView()) }
            grid.addRow(with: row)
        }

        effect.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -16)
        ])
        return effect
    }

    private func tile(for binding: AppBinding, modifier: TriggerModifier) -> NSView {
        let iconView = NSImageView()
        iconView.image = AppCatalog.icon(forBundleIdentifier: binding.bundleIdentifier, size: 42)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 42),
            iconView.heightAnchor.constraint(equalToConstant: 42)
        ])

        let key = KeyCodeMap.displayName(for: CGKeyCode(binding.chordKeyCode ?? 0))
        let keyLabel = NSTextField(labelWithString: modifier.chordPrefix + key)
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keyLabel.alignment = .center
        keyLabel.wantsLayer = true
        keyLabel.layer?.cornerRadius = 5
        keyLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor

        let name = NSTextField(labelWithString: binding.appName)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .secondaryLabelColor
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1

        let stack = NSStackView(views: [iconView, keyLabel, name])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 88).isActive = true
        return stack
    }

    private static func signature(for bindings: [AppBinding], modifier: TriggerModifier) -> String {
        let parts = bindings.map { "\($0.bundleIdentifier)|\($0.chordKeyCode ?? 0)|\($0.appName)" }
        return modifier.rawValue + "#" + parts.joined(separator: ",")
    }
}
