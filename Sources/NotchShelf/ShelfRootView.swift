import AppKit

/// The panel's content view. Acts as the drag-in target, hosts the item chips,
/// and drives expand/collapse on hover and drag.
final class ShelfRootView: NSView {
    private let store: ShelfStore
    weak var controller: NotchWindowController?

    var isExpanded = false
    var notchHeight: CGFloat = 38

    private let bgView = NSView()
    private let titleLabel = NSTextField(labelWithString: "暫存區")
    private let hintLabel = NSTextField(labelWithString: "把檔案拖到此處")
    private let countLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let stack = NSStackView()

    private var trackingArea: NSTrackingArea?
    private var collapseWork: DispatchWorkItem?
    private var isDragInside = false
    private var isHovering = false
    private var isAnimating = false

    init(store: ShelfStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        wantsLayer = true
        autoresizesSubviews = false
        setupViews()
        registerForDraggedTypes([.fileURL])
        store.onChange = { [weak self] in self?.rebuildItems() }
        rebuildItems()
        updateVisibility()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Respond to the first click even though the panel never becomes key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setupViews() {
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        bgView.layer?.cornerRadius = 16
        bgView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // bottom corners
        addSubview(bgView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        addSubview(titleLabel)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        hintLabel.alignment = .center
        addSubview(hintLabel)

        countLabel.font = .systemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .white
        countLabel.alignment = .center
        addSubview(countLabel)

        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .top
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = true

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay   // don't reserve layout space for the scroller
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = stack
        addSubview(scrollView)
    }

    // Non-flipped (origin bottom-left). We measure offsets from the top using
    // bounds.height so the rounded "chin" hangs below the notch.

    override func layout() {
        super.layout()
        bgView.frame = bounds
        countLabel.frame = NSRect(x: 0, y: 2, width: bounds.width, height: 14)

        guard isExpanded else { return }

        let inset: CGFloat = 12
        let titleH: CGFloat = 16
        let topPad = notchHeight + 6
        let titleY = bounds.height - topPad - titleH
        titleLabel.frame = NSRect(x: inset, y: titleY, width: bounds.width - inset * 2, height: titleH)

        let contentTop = titleY - 6
        let contentH = max(0, contentTop - inset)
        scrollView.frame = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: contentH)
        hintLabel.frame = NSRect(x: inset, y: inset + contentH / 2 - 8, width: bounds.width - inset * 2, height: 16)

        layoutStackSize(visibleHeight: contentH)
    }

    private func layoutStackSize(visibleHeight: CGFloat) {
        let n = stack.arrangedSubviews.count
        let chipW: CGFloat = 76
        let width = CGFloat(n) * chipW
            + CGFloat(max(0, n - 1)) * stack.spacing
            + stack.edgeInsets.left + stack.edgeInsets.right
        // Size the document view to its natural content width only. Stretching it
        // to the clip width would make .fill balloon the last chip.
        stack.frame = NSRect(x: 0, y: 0, width: width, height: visibleHeight)
    }

    // MARK: - Items

    func refresh() { rebuildItems() }

    private func rebuildItems() {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        for url in store.items {
            let chip = ShelfItemView(url: url, store: store, controller: controller)
            stack.addArrangedSubview(chip)
        }
        titleLabel.stringValue = "暫存格 (\(store.items.count))"
        updateVisibility()
        needsLayout = true
    }

    func updateVisibility() {
        let expanded = isExpanded
        let empty = store.items.isEmpty
        titleLabel.isHidden = !expanded
        scrollView.isHidden = !expanded || empty
        hintLabel.isHidden = !expanded || !empty
        countLabel.isHidden = expanded || empty
        countLabel.stringValue = empty ? "" : "\(store.items.count)"
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Build once. With .inVisibleRect the area auto-syncs to the view's
        // bounds, so we must NOT remove/re-add it on every bounds change —
        // doing so during the expand/collapse animation fires a storm of
        // spurious enter/exit events (the flicker).
        guard trackingArea == nil else { return }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    /// Called by the controller around the expand/collapse animation. While
    /// animating we ignore enter/exit (the moving boundary sweeps the cursor);
    /// when it finishes we reconcile against the cursor's real position.
    func setAnimating(_ animating: Bool) {
        isAnimating = animating
        if !animating { reconcileHoverState() }
    }

    private func reconcileHoverState() {
        if cursorIsInsidePanel() {
            if !isExpanded { controller?.expand() }
        } else if isExpanded, !isDragInside, !(controller?.isDraggingOut ?? false) {
            controller?.collapse()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        guard !isAnimating else { return }
        cancelCollapse()
        controller?.expand()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        guard !isAnimating else { return }
        // 極短防抖後收合；收合前會再確認游標真的離開（避免最頂端邊界誤收）
        scheduleCollapse()
    }

    // MARK: - Drag IN (files dropped onto the notch)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragInside = true
        cancelCollapse()
        controller?.expand()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragInside = false
        scheduleCollapse()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            isDragInside = false
            scheduleCollapse()
            return false
        }
        store.add(urls)
        isDragInside = false
        scheduleCollapse()
        return true
    }

    // MARK: - Collapse scheduling

    /// Called by an item view when a drag-out session ends, so the panel can
    /// collapse even though no mouseExited will fire (pointer is already outside).
    func scheduleCollapseAfterDragOut() {
        scheduleCollapse()
    }

    private func scheduleCollapse(after delay: TimeInterval = 0.12) {
        cancelCollapse()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isDragInside || (self.controller?.isDraggingOut ?? false) { return }
            // Re-check the cursor's real position: a spurious exit at the very
            // top screen edge (window top == screen top) must not collapse.
            if self.cursorIsInsidePanel() { return }
            self.controller?.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    /// Whether the cursor is over the panel, with a few px of tolerance so the
    /// top screen edge and boundary jitter count as "inside".
    private func cursorIsInsidePanel() -> Bool {
        guard let window = window else { return false }
        let f = window.frame.insetBy(dx: -3, dy: -3)
        return NSMouseInRect(NSEvent.mouseLocation, f, false)
    }
}
