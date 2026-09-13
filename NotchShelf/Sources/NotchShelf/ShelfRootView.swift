import AppKit

/// The panel's content view. Acts as the drag-in target, hosts the item chips,
/// owns the selection, and drives expand/collapse on hover and drag.
final class ShelfRootView: NSView {
    let store: ShelfStore
    weak var controller: NotchWindowController?

    var isExpanded = false
    var notchHeight: CGFloat = 38

    private let bgView = NSView()
    private let titleLabel = NSTextField(labelWithString: "暫存格")
    private let hintLabel = NSTextField(labelWithString: "把檔案拖到此處")
    private let countLabel = NSTextField(labelWithString: "")
    private let selectAllButton = FirstMouseButton()
    private let removeSelectedButton = FirstMouseButton()
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let dragCoordinator: ShelfDragCoordinator

    /// Selection is keyed by URL (not by chip) so it survives chip rebuilds.
    private(set) var selectedURLs: Set<URL> = []
    /// Last plainly-clicked chip; Shift-click selects the range from here.
    private var selectionAnchor: URL?

    // Marquee (rubber-band) selection: press on empty space and sweep across
    // chips. Tracked in the stack's (document) coordinates so autoscrolling the
    // strip mid-sweep keeps the rectangle anchored to the content, not the panel.
    private let marqueeView = NSView()
    private var marqueeStart: NSPoint?
    private var marqueeBaseSelection: Set<URL> = []
    private var marqueeActive = false
    private var isMarqueeTracking: Bool { marqueeStart != nil }

    private var trackingArea: NSTrackingArea?
    private var collapseWork: DispatchWorkItem?
    private var isDragInside = false
    private var isHovering = false
    private var isAnimating = false

    init(store: ShelfStore) {
        self.store = store
        self.dragCoordinator = ShelfDragCoordinator(store: store)
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        dragCoordinator.shelf = self
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
        // Opaque, not 90% black: the expanded panel overlaps the (transparent on
        // macOS 26) menu bar on both sides of the notch, and anything less than
        // opaque lets the wallpaper and status icons bleed through as a tinted
        // band that reads as a rounded bite out of the panel next to the notch.
        // Solid black makes notch + panel one continuous shape.
        bgView.layer?.backgroundColor = NSColor.black.cgColor
        bgView.layer?.cornerRadius = 16
        bgView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // bottom corners
        addSubview(bgView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        hintLabel.alignment = .center
        addSubview(hintLabel)

        countLabel.font = .systemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .white
        countLabel.alignment = .center
        addSubview(countLabel)

        configureHeaderButton(selectAllButton, action: #selector(toggleSelectAll))
        selectAllButton.toolTip = "選取全部項目（也可以在空白處拖曳框選，點空白處取消選取）"
        configureHeaderButton(removeSelectedButton, action: #selector(removeSelected))
        removeSelectedButton.toolTip = "從暫存移除已選取的項目"

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

        marqueeView.wantsLayer = true
        marqueeView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        marqueeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        marqueeView.layer?.borderWidth = 1
        marqueeView.layer?.cornerRadius = 3
        marqueeView.isHidden = true
        addSubview(marqueeView)   // above the scroll view so the rectangle draws over the chips
    }

    /// Passive decoration must not swallow presses: route hits on the labels and
    /// the backdrop to the root so a marquee can start anywhere that isn't a
    /// chip, a button or the scroller. (Presses inside the scroll view's empty
    /// space reach us through the responder chain already.)
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === bgView || hit === titleLabel || hit === hintLabel || hit === countLabel {
            return self
        }
        return hit
    }

    private func configureHeaderButton(_ button: NSButton, action: Selector) {
        button.isBordered = false
        button.target = self
        button.action = action
        addSubview(button)
    }

    private func setHeaderTitle(_ button: NSButton, _ title: String) {
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ])
        button.sizeToFit()
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

        // Header buttons hug the right edge; the title takes what's left.
        var right = bounds.width - inset
        for button in [removeSelectedButton, selectAllButton] where !button.isHidden {
            let w = button.frame.width
            button.frame = NSRect(x: right - w, y: titleY - 2, width: w, height: titleH + 4)
            right -= w + 4
        }
        titleLabel.frame = NSRect(x: inset, y: titleY, width: max(0, right - inset - 4), height: titleH)

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

    private func rebuildItems() {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        selectedURLs.formIntersection(store.items)   // drop selections whose file is gone
        for url in store.items {
            let chip = ShelfItemView(url: url, shelf: self)
            chip.isSelected = selectedURLs.contains(url)
            stack.addArrangedSubview(chip)
        }
        updateVisibility()
    }

    func updateVisibility() {
        let expanded = isExpanded
        let total = store.items.count
        let selected = selectedURLs.count
        let empty = total == 0

        titleLabel.isHidden = !expanded
        scrollView.isHidden = !expanded || empty
        hintLabel.isHidden = !expanded || !empty
        countLabel.isHidden = expanded || empty
        countLabel.stringValue = empty ? "" : "\(total)"

        titleLabel.stringValue = selected > 0 ? "暫存格 (\(total))・已選 \(selected)" : "暫存格 (\(total))"
        setHeaderTitle(selectAllButton, (total > 0 && selected == total) ? "取消選取" : "全選")
        setHeaderTitle(removeSelectedButton, "移除所選")
        selectAllButton.isHidden = !expanded || total < 2
        removeSelectedButton.isHidden = !expanded || selected == 0
        if !expanded { marqueeView.isHidden = true }
        needsLayout = true
    }

    // MARK: - Selection

    /// Called by a chip on a click that didn't turn into a drag.
    func chipClicked(_ chip: ShelfItemView, modifiers: NSEvent.ModifierFlags) {
        var selection = selectedURLs
        if modifiers.contains(.shift),
           let anchor = selectionAnchor,
           let a = store.items.firstIndex(of: anchor),
           let b = store.items.firstIndex(of: chip.url) {
            selection.formUnion(store.items[min(a, b)...max(a, b)])
        } else {
            if selection.contains(chip.url) {
                selection.remove(chip.url)
            } else {
                selection.insert(chip.url)
            }
            selectionAnchor = chip.url
        }
        setSelection(selection)
    }

    private func setSelection(_ urls: Set<URL>) {
        selectedURLs = urls.intersection(store.items)
        for case let chip as ShelfItemView in stack.arrangedSubviews {
            chip.isSelected = selectedURLs.contains(chip.url)
        }
        updateVisibility()
    }

    /// Selected files in shelf order (newest first), the order they're dragged in.
    private var orderedSelection: [URL] {
        store.items.filter { selectedURLs.contains($0) }
    }

    @objc private func toggleSelectAll() {
        let all = Set(store.items)
        setSelection(selectedURLs == all ? [] : all)
    }

    @objc private func removeSelected() {
        store.remove(orderedSelection)
    }

    // MARK: - Marquee selection (press on empty space, sweep across chips)

    // Chips and buttons swallow their own mouseDown, so these only fire for the
    // background, the title row, and the gaps around chips. A press that never
    // moves clears the selection, like clicking empty space in Finder; a press
    // that moves becomes a rubber band (Shift keeps what was already selected).
    override func mouseDown(with event: NSEvent) {
        guard isExpanded else { return }
        marqueeStart = stack.convert(event.locationInWindow, from: nil)
        marqueeBaseSelection = event.modifierFlags.contains(.shift) ? selectedURLs : []
        marqueeActive = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = marqueeStart, !scrollView.isHidden else { return }
        let current = stack.convert(event.locationInWindow, from: nil)
        if !marqueeActive {
            guard hypot(current.x - start.x, current.y - start.y) > 4 else { return }
            marqueeActive = true
        }
        stack.autoscroll(with: event)   // sweeping past the edge scrolls a long strip

        let band = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        var selection = marqueeBaseSelection
        for case let chip as ShelfItemView in stack.arrangedSubviews where chip.frame.intersects(band) {
            selection.insert(chip.url)
        }
        setSelection(selection)

        // Draw the band in panel space, clipped to the strip so it never covers the title.
        marqueeView.frame = convert(band, from: stack).intersection(scrollView.frame)
        marqueeView.isHidden = marqueeView.frame.isEmpty
    }

    override func mouseUp(with event: NSEvent) {
        guard marqueeStart != nil else { return }
        let wasSweep = marqueeActive
        marqueeStart = nil
        marqueeActive = false
        marqueeView.isHidden = true
        if !wasSweep, !event.modifierFlags.contains(.shift), !selectedURLs.isEmpty {
            setSelection([])
        }
        // The pointer may have been released outside the panel; no mouseExited
        // is guaranteed after a drag, so re-check like we do after a drag-out.
        scheduleCollapse()
    }

    // MARK: - Drag OUT

    /// Called by a chip once the press has moved far enough to be a drag.
    func beginDrag(from chip: ShelfItemView, event: NSEvent) {
        let urls = selectedURLs.contains(chip.url) ? orderedSelection : [chip.url]
        let dragged = Set(urls)
        var frames: [URL: NSRect] = [:]
        for case let other as ShelfItemView in stack.arrangedSubviews where dragged.contains(other.url) {
            frames[other.url] = chip.convert(other.dragImageFrame, from: other)
        }
        dragCoordinator.beginDrag(of: urls, from: chip, frames: frames, event: event)
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
        } else if isExpanded, !isDragInside, !isMarqueeTracking, !(controller?.isDraggingOut ?? false) {
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

    /// Our own drag-out now carries a plain file URL too, so it matches the
    /// registered drag-in type. Never treat it as an incoming drop.
    private func isOwnDrag(_ sender: NSDraggingInfo) -> Bool {
        (sender.draggingSource as AnyObject?) === dragCoordinator
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        isDragInside = true
        cancelCollapse()
        controller?.expand()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isOwnDrag(sender) ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragInside = false
        scheduleCollapse()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !isOwnDrag(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard !isOwnDrag(sender),
              let urls = pb.readObjects(forClasses: [NSURL.self],
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

    /// Called by the drag coordinator when a drag-out session ends, so the panel
    /// can collapse even though no mouseExited will fire (pointer is already outside).
    func scheduleCollapseAfterDragOut() {
        scheduleCollapse()
    }

    private func scheduleCollapse(after delay: TimeInterval = 0.12) {
        cancelCollapse()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isDragInside || self.isMarqueeTracking || (self.controller?.isDraggingOut ?? false) { return }
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
