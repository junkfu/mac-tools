import AppKit

/// An NSButton that responds on the first click even when its window is not key.
/// Needed because our panel is a non-activating panel that never becomes key.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One stashed file: icon + name + remove button + selection badge.
///
/// A click toggles selection (Shift-click selects a range); dragging a selected
/// chip drags the whole selection, dragging an unselected one drags just that
/// file. The drag session itself and the file promises are owned by
/// `ShelfDragCoordinator`, not by the chip — chips are rebuilt on every store
/// change and must be free to disappear mid-drag.
final class ShelfItemView: NSView {
    let url: URL
    private weak var shelf: ShelfRootView?

    var isSelected = false {
        didSet { if isSelected != oldValue { updateSelectionAppearance() } }
    }

    /// Selection backdrop. It is a separate subview on purpose: putting a
    /// cornerRadius on *this* view's layer makes AppKit (macOS 14+) flip
    /// `clipsToBounds` on, which clips the × and ✓ badges that deliberately hang
    /// 3pt over the chip's corners into egg shapes.
    private let highlightView = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let removeButton = FirstMouseButton()
    private let checkBadge = NSImageView()
    private var mouseDownLocation: NSPoint?

    /// Where the drag image lifts off from, in this view's coordinates.
    var dragImageFrame: NSRect {
        NSRect(x: (bounds.width - 48) / 2, y: (bounds.height - 48) / 2, width: 48, height: 48)
    }

    init(url: URL, shelf: ShelfRootView) {
        self.url = url
        self.shelf = shelf
        super.init(frame: NSRect(x: 0, y: 0, width: 76, height: 64))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Deliver the first click even though the panel is never key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setup() {
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 10
        highlightView.frame = bounds
        highlightView.autoresizingMask = [.width, .height]
        highlightView.isHidden = true
        addSubview(highlightView)   // first, so it sits behind icon, label and badges

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 40, height: 40)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameLabel.stringValue = url.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 9)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        removeButton.isBordered = false
        removeButton.bezelStyle = .regularSquare
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "移除")
        if removeButton.image == nil { removeButton.title = "✕" }
        removeButton.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        removeButton.imageScaling = .scaleProportionallyDown
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)

        // White check on a blue disc (palette rendering), top-left, selected only.
        let palette = NSImage.SymbolConfiguration(paletteColors: [.white, .systemBlue])
        checkBadge.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已選取")?
            .withSymbolConfiguration(palette)
        checkBadge.imageScaling = .scaleProportionallyUpOrDown
        checkBadge.isHidden = true
        checkBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkBadge)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 76),
            heightAnchor.constraint(equalToConstant: 64),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),

            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: -3),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 3),
            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16),

            checkBadge.topAnchor.constraint(equalTo: topAnchor, constant: -3),
            checkBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -3),
            checkBadge.widthAnchor.constraint(equalToConstant: 16),
            checkBadge.heightAnchor.constraint(equalToConstant: 16),
        ])

        toolTip = "\(url.lastPathComponent)\n點一下選取，拖曳取出"
    }

    private func updateSelectionAppearance() {
        highlightView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        highlightView.isHidden = !isSelected
        checkBadge.isHidden = !isSelected
        nameLabel.textColor = NSColor.white.withAlphaComponent(isSelected ? 1 : 0.85)
    }

    @objc private func removeTapped() {
        shelf?.store.remove(url)
    }

    // MARK: - Mouse: click = select, drag = drag out

    // Not calling super here also keeps the press from reaching the root view,
    // whose mouseDown clears the selection.
    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard (dx * dx + dy * dy) > 16 else { return }   // small threshold so clicks aren't drags
        mouseDownLocation = nil
        shelf?.beginDrag(from: self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownLocation != nil else { return }   // a drag already consumed this press
        mouseDownLocation = nil
        shelf?.chipClicked(self, modifiers: event.modifierFlags)
    }
}
