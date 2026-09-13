import Foundation

/// 監看筆記檔案的變動，存檔後自動重新讀取，不用重開 App。
///
/// 用 rename-safe 的方式重建監看：多數編輯器存檔其實是「寫一個暫存檔、再原地換掉舊檔」，
/// 原本那個檔案描述符盯著的是舊的、已經被取代的 inode，之後再也收不到寫入事件，
/// 只會先看到一次「檔案被刪除／改名」。所以每次收到 .delete / .rename 都要整組重建：
/// 關掉舊的檔案描述符、重新 open 目前這個路徑、重新建 dispatch source。
final class HotkeyFileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        startWatching()
    }

    deinit {
        stopWatching()
    }

    private func startWatching() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // 檔案這一刻不在（例如被外部工具整個砍掉、還沒建回來）：等一下再試，
            // 不要就此永久放棄——不然使用者之後把檔案救回來，筆記本也不會再自動更新了。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startWatching()
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let flags = source.data
            self.scheduleReload()
            if flags.contains(.delete) || flags.contains(.rename) {
                self.stopWatching()
                // 存檔的「刪舊檔→建新檔」幾乎是一瞬間的事，稍微等一下再重建監看，
                // 不然常常會撲空——這時候新檔案可能都還沒落地。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.startWatching()
                }
            }
        }
        // 直接捕捉這次的 fd 數值，不透過 self：cancel handler 是非同步排程執行的，
        // 如果 HotkeyFileWatcher 這時候已經被釋放（例如剛好碰到 deinit），weak self
        // 會拿到 nil，經由 self 才關得到的 fd 就永遠漏關了。
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
