import AppKit

/// 截圖後的標註視窗：無邊框樣式的浮動面板，上方工具列 + 下方畫布。
final class AnnotationWindowController: NSWindowController {
    private var annotationView: AnnotationView!
    private var toolbar: ToolbarView!

    /// 視窗關閉（複製或取消）後呼叫，讓 AppDelegate 釋放這個 controller。
    var onFinish: (() -> Void)?

    convenience init(image: NSImage) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        let maxWidth = visibleFrame.width * 0.9
        let maxHeight = (visibleFrame.height - ToolbarView.height) * 0.9
        let scale = min(1.0, min(maxWidth / image.size.width, maxHeight / image.size.height))
        let displaySize = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        // 工具列需要的寬度先算出來，避免截圖太小時視窗比工具列窄，按鈕被裁到看不見。
        let toolbarView = ToolbarView()
        let windowWidth = min(max(displaySize.width, toolbarView.minimumRequiredWidth), visibleFrame.width * 0.95)
        let windowSize = NSSize(width: windowWidth, height: displaySize.height + ToolbarView.height)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        ))

        self.init(window: window)

        let canvas = AnnotationView(image: image, displaySize: displaySize)
        let canvasX = (windowWidth - displaySize.width) / 2
        canvas.frame = NSRect(x: canvasX, y: 0, width: displaySize.width, height: displaySize.height)
        canvas.autoresizingMask = [.minXMargin, .maxXMargin]

        toolbarView.frame = NSRect(x: 0, y: displaySize.height, width: windowWidth, height: ToolbarView.height)
        toolbarView.autoresizingMask = [.width, .minYMargin]

        let contentView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        contentView.addSubview(canvas)
        contentView.addSubview(toolbarView)
        window.contentView = contentView

        annotationView = canvas
        toolbar = toolbarView

        toolbarView.onSelectTool = { [weak canvas] tool in canvas?.tool = tool }
        toolbarView.onSelectColor = { [weak canvas] color in canvas?.strokeColor = color }
        toolbarView.onUndo = { [weak canvas] in canvas?.undo() }
        toolbarView.onCancel = { [weak self] in self?.finish(copyToClipboard: false) }
        toolbarView.onCopy = { [weak self] in self?.finish(copyToClipboard: true) }
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(copyToClipboard: Bool) {
        if copyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([annotationView.baseImage])
        }
        window?.close()
        onFinish?()
    }
}
