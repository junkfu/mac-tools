import AppKit
import UniformTypeIdentifiers

/// A file promise that also advertises the real file URL.
///
/// Finder, Mail and friends speak file promises, so they keep using the promise
/// path (and its "delete only after the bytes landed" safe move). Terminals such
/// as cmux / Ghostty / iTerm2 / Terminal.app, and many Electron apps, only look
/// for `public.file-url` — without it they refuse the drop outright. The promise
/// types stay first in the type list so the fallback never outranks the promise.
final class StashFilePromiseProvider: NSFilePromiseProvider {
    /// The stashed file this promise stands for. Kept in `userInfo` (not a
    /// stored property) so the superclass' designated initializers stay usable.
    var fileURL: URL? { userInfo as? URL }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.fileURL]
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType,
                                 pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL {
            return fileURL.map { ($0 as NSURL).pasteboardPropertyList(forType: type) as Any }
        }
        return super.pasteboardPropertyList(forType: type)
    }
}

/// Starts drag-out sessions for one or many stashed files and fulfils their
/// file promises.
///
/// This object lives as long as the shelf, deliberately not per chip: chips are
/// rebuilt whenever the store changes, and `NSFilePromiseProvider` holds its
/// delegate weakly — a promise whose delegate has been torn down is silently
/// never written. With several files in flight, the first one to finish (which
/// mutates the store in move mode) would otherwise strand the rest.
final class ShelfDragCoordinator: NSObject, NSDraggingSource, NSFilePromiseProviderDelegate {
    private let store: ShelfStore
    weak var shelf: ShelfRootView?

    /// URLs in the session currently being dragged (empty when idle).
    private var draggedURLs: [URL] = []

    private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    init(store: ShelfStore) {
        self.store = store
        super.init()
    }

    /// Begin dragging `urls` out of the shelf. `frames` are the lift-off rects
    /// in `view`'s coordinates; a URL without one starts centred in `view`.
    func beginDrag(of urls: [URL], from view: NSView, frames: [URL: NSRect], event: NSEvent) {
        guard !urls.isEmpty else { return }
        draggedURLs = urls
        shelf?.controller?.isDraggingOut = true

        let side: CGFloat = 48
        let centred = NSRect(x: (view.bounds.width - side) / 2,
                             y: (view.bounds.height - side) / 2,
                             width: side, height: side)

        let items: [NSDraggingItem] = urls.map { url in
            let provider = StashFilePromiseProvider(fileType: contentType(of: url).identifier, delegate: self)
            provider.userInfo = url
            let item = NSDraggingItem(pasteboardWriter: provider)
            item.setDraggingFrame(frames[url] ?? centred, contents: dragIcon(for: url, side: side))
            return item
        }

        let session = view.beginDraggingSession(with: items, event: event, source: self)
        if items.count > 1 {
            session.draggingFormation = .stack   // gather the icons under the cursor
        }
    }

    private func contentType(of url: URL) -> UTType {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
    }

    private func dragIcon(for url: URL, side: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let copy = (icon.copy() as? NSImage) ?? icon
        copy.size = NSSize(width: side, height: side)
        return copy
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return []                     // never let items drop back onto our own shelf
        case .outsideApplication:
            // Offer "move" only in move mode. A destination that consumes the
            // promise ignores the difference (the stash copy is deleted by the
            // promise handler, after a verified write); one that consumes the
            // plain file URL — Finder does, when it prefers it — moves the real
            // file itself, so it must not be allowed to when the user turned
            // move mode off.
            return store.removeAfterDrop ? [.copy, .move] : [.copy]
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        let urls = draggedURLs
        draggedURLs = []

        shelf?.controller?.isDraggingOut = false
        // Re-evaluate collapse: the pointer is usually outside the panel now and
        // no further mouseExited will fire, so without this the panel stays open.
        shelf?.scheduleCollapseAfterDragOut()

        if operation == .delete {         // dropped on the Trash
            store.remove(urls)
        } else if operation.contains(.move) {
            // A destination that took the plain file URL may have moved the
            // stash file itself. The folder watcher catches that too; reloading
            // here just makes the chip disappear without the debounce delay.
            store.reload()
        }
        // "Move out" deletion for promise-based drops is NOT done here — it
        // happens in the promise completion handler below, only after the bytes
        // are safely delivered.
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? URL)?.lastPathComponent ?? "file"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo destURL: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let srcURL = filePromiseProvider.userInfo as? URL else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        let store = self.store
        let fm = FileManager.default
        do {
            // destURL 是接收端決定的路徑。已存在就回報失敗、保留暫存副本，
            // 絕不替接收端刪掉既有檔案（若那是個資料夾，會整棵不見）。
            if fm.fileExists(atPath: destURL.path) {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destURL.path])
            }
            try fm.copyItem(at: srcURL, to: destURL)
            completionHandler(nil)
            // Bytes delivered. Honor "move out" by removing the stash copy now —
            // safe because the destination already has the full file.
            if store.removeAfterDrop {
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
