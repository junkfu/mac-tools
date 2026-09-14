import AppKit

/// Owns the stash folder on disk and the in-memory list of stashed files.
final class ShelfStore {
    let stashURL: URL
    private(set) var items: [URL] = []

    /// Called on the main thread whenever `items` changes.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let removeKey = "removeAfterDrop"

    private var watcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?
    /// Serial so two drops never race on `uniqueDestination` names.
    private let copyQueue = DispatchQueue(label: "NotchShelf.copy", qos: .userInitiated)

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
        // Recreate the folder if something removed it, so drops keep working.
        try? fm.createDirectory(at: stashURL, withIntermediateDirectories: true)
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
    ///
    /// The copy runs off the main thread: a dropped folder can be arbitrarily
    /// large (any app can put `file:///` on the pasteboard), and copying it
    /// synchronously would freeze the panel. Sources that contain the stash
    /// itself are skipped — copying them would recurse into the copy in progress.
    func add(_ urls: [URL]) {
        let stashPath = stashURL.standardizedFileURL.path
        let sources = urls.filter { src in
            let path = src.standardizedFileURL.path
            let containsStash = path == "/" || stashPath == path || stashPath.hasPrefix(path + "/")
            if containsStash { NSLog("%@", "NotchShelf: refusing to stash \(path): it contains the stash folder") }
            return !containsStash
        }
        guard !sources.isEmpty else { return }
        var reserved = Set<String>()
        let destinations: [URL] = sources.map { src in
            let dest = uniqueDestination(for: src.lastPathComponent, avoiding: reserved)
            reserved.insert(dest.lastPathComponent)
            return dest
        }
        copyQueue.async { [weak self] in
            let fm = FileManager.default
            for (src, dest) in zip(sources, destinations) {
                do {
                    try fm.copyItem(at: src, to: dest)
                } catch {
                    NSLog("%@", "NotchShelf: copy failed for \(src.path): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func remove(_ url: URL) {
        remove([url])
    }

    func remove(_ urls: [URL]) {
        for u in urls { try? FileManager.default.removeItem(at: u) }
        reload()
    }

    /// Empties the folder, including dotfiles that `items` (which skips hidden
    /// files) never shows — otherwise they would accumulate invisibly forever.
    func clear() {
        let fm = FileManager.default
        let everything = (try? fm.contentsOfDirectory(at: stashURL, includingPropertiesForKeys: nil, options: [])) ?? []
        for u in everything { try? fm.removeItem(at: u) }
        reload()
    }

    // MARK: - Folder watching

    /// Reload when the stash folder changes behind our back: the user tidying it
    /// in Finder (the menu opens it), or a drop destination that consumed the
    /// plain file URL and moved the file out itself. Events are debounced since
    /// a single copy produces several.
    func startWatching() {
        guard watcher == nil else { return }
        let fd = open(stashURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.watcher?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // The folder itself went away; the fd now points at a dead inode.
                self.stopWatching()
                try? FileManager.default.createDirectory(at: self.stashURL, withIntermediateDirectories: true)
                self.startWatching()
            }
            self.scheduleReload()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Avoid clobbering an existing file: "report.pdf" -> "report 2.pdf" etc.
    private func uniqueDestination(for name: String, avoiding reserved: Set<String> = []) -> URL {
        let fm = FileManager.default
        let safeName = name.isEmpty ? "file" : name
        var dest = stashURL.appendingPathComponent(safeName)
        let taken = { (url: URL) in fm.fileExists(atPath: url.path) || reserved.contains(url.lastPathComponent) }
        guard taken(dest) else { return dest }

        let ext = (safeName as NSString).pathExtension
        let base = (safeName as NSString).deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            dest = stashURL.appendingPathComponent(candidate)
            if !taken(dest) { return dest }
            i += 1
        }
    }
}
