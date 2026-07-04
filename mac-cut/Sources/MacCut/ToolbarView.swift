import AppKit

/// 浮動工具列：畫筆／框框、顏色、undo、取消、複製。
final class ToolbarView: NSVisualEffectView {
    var onSelectTool: ((AnnotationView.Tool) -> Void)?
    var onSelectColor: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCancel: (() -> Void)?

    static let height: CGFloat = 44
    private static let horizontalPadding: CGFloat = 24

    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var contentStack: NSStackView!

    /// 工具列所有按鈕排起來實際需要的寬度（含左右留白）。
    /// 視窗寬度不能小於這個值，不然按鈕會被裁到視窗外面看不到。
    var minimumRequiredWidth: CGFloat {
        contentStack.fittingSize.width + Self.horizontalPadding
    }

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let penButton = makeToggleButton(symbol: "pencil.tip", tag: 0, tooltip: "畫筆")
        let rectButton = makeToggleButton(symbol: "rectangle", tag: 1, tooltip: "框框")
        let mosaicButton = makeToggleButton(symbol: "square.grid.3x3.fill", tag: 2, tooltip: "馬賽克")
        toolButtons = [penButton, rectButton, mosaicButton]
        penButton.state = .on

        let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .black]
        colorButtons = colors.map { makeColorButton(color: $0) }
        colorButtons.first?.layer?.borderWidth = 2

        let undoButton = makeActionButton(symbol: "arrow.uturn.backward", tooltip: "復原")
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.keyEquivalent = "z"
        undoButton.keyEquivalentModifierMask = .command

        let cancelButton = makeActionButton(symbol: "xmark.circle.fill", tooltip: "取消 (Esc)")
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\u{1b}"

        let copyButton = makeActionButton(symbol: "checkmark.circle.fill", tooltip: "複製到剪貼簿 (⏎)")
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.keyEquivalent = "\r"
        copyButton.contentTintColor = .systemGreen

        let toolGroup = NSStackView(views: [penButton, rectButton, mosaicButton])
        toolGroup.spacing = 4
        let colorGroup = NSStackView(views: colorButtons)
        colorGroup.spacing = 6
        let actionGroup = NSStackView(views: [undoButton, cancelButton, copyButton])
        actionGroup.spacing = 4

        let stack = NSStackView(views: [toolGroup, separator(), colorGroup, separator(), actionGroup])
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        contentStack = stack
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }

    private func makeToggleButton(symbol: String, tag: Int, tooltip: String) -> NSButton {
        let button = NSButton(image: symbolImage(symbol), target: self, action: #selector(toolTapped(_:)))
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .texturedRounded
        button.tag = tag
        button.toolTip = tooltip
        return button
    }

    private func makeActionButton(symbol: String, tooltip: String) -> NSButton {
        let button = NSButton(image: symbolImage(symbol), target: nil, action: nil)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        return button
    }

    private func makeColorButton(color: NSColor) -> NSButton {
        let button = NSButton(image: circleImage(color: color), target: self, action: #selector(colorTapped(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.6).cgColor
        button.identifier = NSUserInterfaceItemIdentifier(color.mc_hexString)
        return button
    }

    private func symbolImage(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: name) ?? NSImage()
    }

    private func circleImage(color: NSColor, diameter: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2))
        color.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        return image
    }

    @objc private func toolTapped(_ sender: NSButton) {
        toolButtons.forEach { $0.state = ($0 === sender) ? .on : .off }
        let tool: AnnotationView.Tool
        switch sender.tag {
        case 0: tool = .pen
        case 1: tool = .rectangle
        default: tool = .mosaic
        }
        onSelectTool?(tool)
    }

    @objc private func colorTapped(_ sender: NSButton) {
        colorButtons.forEach { $0.layer?.borderWidth = 0 }
        sender.layer?.borderWidth = 2
        if let hex = sender.identifier?.rawValue, let color = NSColor.mc_fromHexString(hex) {
            onSelectColor?(color)
        }
    }

    @objc private func undoTapped() { onUndo?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func copyTapped() { onCopy?() }
}

private extension NSColor {
    var mc_hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255), g = Int(rgb.greenComponent * 255), b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func mc_fromHexString(_ hex: String) -> NSColor? {
        var trimmed = hex
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(deviceRed: r, green: g, blue: b, alpha: 1)
    }
}
