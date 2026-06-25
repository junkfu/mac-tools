import AppKit

/// Owns the stash folder on disk and the in-memory list of stashed files.
final class ShelfStore {
    let stashURL: URL
    private(set) var items: [URL] = []

    /// Called on the main thread whenever `items` changes.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let removeKey = "removeAfterDrop"

    /// When true (default), dragging an item out and delivering it successfully
    /// removes it from the stash — i.e. drag-out is a "move". The delete only
    /// happens after the destination has fully received the bytes (see the
    /// NSFilePromiseProvider completion handler), so this is safe.
    var removeAfterDrop: Bool {
        get { defaults.object(forKey: removeKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: removeKey) }
    }

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        stashURL = base.appendingPathComponent("NotchShelf/Stash", isDirectory: true)
        try? FileManager.default.createDirectory(at: stashURL, withIntermediateDirectories: true)
    }

    func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: stashURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        items = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db   // newest first
        }
        onChange?()
    }

    /// Copy the given files into the stash (originals are left in place).
    func add(_ urls: [URL]) {
        let fm = FileManager.default
        for src in urls {
            let dest = uniqueDestination(for: src.lastPathComponent)
            do {
                try fm.copyItem(at: src, to: dest)
            } catch {
                NSLog("NotchShelf: copy failed for \(src.path): \(error.localizedDescription)")
            }
        }
        reload()
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    func clear() {
        for u in items { try? FileManager.default.removeItem(at: u) }
        reload()
    }

    /// Avoid clobbering an existing file: "report.pdf" -> "report 2.pdf" etc.
    private func uniqueDestination(for name: String) -> URL {
        let fm = FileManager.default
        let safeName = name.isEmpty ? "file" : name
        var dest = stashURL.appendingPathComponent(safeName)
        guard fm.fileExists(atPath: dest.path) else { return dest }

        let ext = (safeName as NSString).pathExtension
        let base = (safeName as NSString).deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            dest = stashURL.appendingPathComponent(candidate)
            if !fm.fileExists(atPath: dest.path) { return dest }
            i += 1
        }
    }
}
