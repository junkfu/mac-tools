import AppKit
import UniformTypeIdentifiers

/// An NSButton that responds on the first click even when its window is not key.
/// Needed because our panel is a non-activating panel that never becomes key.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One stashed file: icon + name + remove button. Draggable out to Finder/apps.
///
/// Drag-out uses NSFilePromiseProvider so that, in "move out" mode, the stash
/// copy is only deleted *after* the destination has fully received the bytes —
/// this avoids the data-loss race that a plain file-URL drag would have.
final class ShelfItemView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    private let url: URL
    private weak var store: ShelfStore?
    private weak var controller: NotchWindowController?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let removeButton = FirstMouseButton()
    private var mouseDownLocation: NSPoint?

    private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    init(url: URL, store: ShelfStore?, controller: NotchWindowController?) {
        self.url = url
        self.store = store
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 76, height: 64))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Deliver the first click even though the panel is never key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setup() {
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
        ])

        toolTip = url.lastPathComponent
    }

    @objc private func removeTapped() {
        store?.remove(url)
    }

    // MARK: - Drag OUT

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard (dx * dx + dy * dy) > 16 else { return }   // small threshold so clicks aren't drags
        mouseDownLocation = nil
        beginDrag(with: event)
    }

    private func beginDrag(with event: NSEvent) {
        controller?.isDraggingOut = true

        let typeID = (UTType(filenameExtension: url.pathExtension) ?? .data).identifier
        let provider = NSFilePromiseProvider(fileType: typeID, delegate: self)

        let item = NSDraggingItem(pasteboardWriter: provider)
        let dragImage = NSWorkspace.shared.icon(forFile: url.path)
        dragImage.size = NSSize(width: 48, height: 48)
        let frame = NSRect(x: (bounds.width - 48) / 2, y: (bounds.height - 48) / 2, width: 48, height: 48)
        item.setDraggingFrame(frame, contents: dragImage)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return []                     // don't let an item drop back onto our own shelf
        case .outsideApplication:
            // Allow move so the cursor reflects "move"; the actual source
            // deletion (when in move mode) happens only after a verified write.
            return [.copy, .move]
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        controller?.isDraggingOut = false
        // Re-evaluate collapse: the pointer is usually outside the panel now and
        // no further mouseExited will fire, so without this the panel stays open.
        controller?.rootView.scheduleCollapseAfterDragOut()

        if operation == .delete {         // dropped on Trash
            store?.remove(url)
        }
        // "Move out" deletion is NOT done here — it happens in the promise
        // completion handler below, only after the bytes are safely delivered.
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        url.lastPathComponent
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo destURL: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        let srcURL = url
        let store = self.store
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: srcURL, to: destURL)
            completionHandler(nil)
            // Bytes delivered. Honor "move out" by removing the stash copy now —
            // safe because the destination already has the full file.
            if let store = store, store.removeAfterDrop {
                DispatchQueue.main.async { store.remove(srcURL) }
            }
        } catch {
            completionHandler(error)      // failed write: keep the stash copy
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }
}
