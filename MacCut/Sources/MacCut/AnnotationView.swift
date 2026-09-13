import AppKit

/// 標註畫布：畫筆（自由手繪）、框框（矩形外框）、馬賽克（區塊像素化）。
/// 設計重點（解決效能卡頓的關鍵）：
/// - layer-backed，drawRect 每次只疊「目前已完成的合成圖」+「正在畫的那一筆」，GPU 合成，不做全畫面重繪以外的事。
/// - 放開滑鼠才把這一筆「烘焙」進合成圖（baseImage），同時把烘焙前的版本推進 undo stack，
///   所以 baseImage 隨時就是「目前結果」，複製到剪貼簿時直接拿它用，不用額外拼合。
final class AnnotationView: NSView {
    enum Tool {
        case pen
        case rectangle
        case mosaic
        case numberMarker
    }

    var tool: Tool = .pen
    var strokeColor: NSColor = .systemRed {
        didSet { needsDisplay = true }
    }

    private(set) var baseImage: NSImage
    /// 連同 undo 快照一起存編號計數，undo 才不會把「已烘焙的圖」跟「下一個該編幾號」搞不同步。
    private var undoStack: [(image: NSImage, markerCount: Int)] = []
    private var markerCount: Int = 0
    private let baseLineWidth: CGFloat = 4.0
    private let mosaicBlockSize: CGFloat = 14.0
    private let markerDiameter: CGFloat = 28.0
    private let maxUndoDepth = 30

    private var currentPoints: [NSPoint] = []
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?

    var canUndo: Bool { !undoStack.isEmpty }

    // 沒有這個 override，NSWindow.isMovableByWindowBackground 會讓畫布上的每次
    // mouseDown/drag 都順便拖動整個視窗，導致邊畫邊移動。
    override var mouseDownCanMoveWindow: Bool { false }

    /// baseImage 的原生尺寸 / 目前顯示尺寸，通常是 1（截圖比螢幕小時不需縮放）。
    private var imageSpaceScale: CGFloat {
        guard bounds.width > 0 else { return 1 }
        return baseImage.size.width / bounds.width
    }

    init(image: NSImage, displaySize: NSSize) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: displaySize))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

        let scale = imageSpaceScale

        switch tool {
        case .pen:
            guard currentPoints.count > 1 else { return }
            let path = NSBezierPath()
            path.lineWidth = baseLineWidth / scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: currentPoints[0])
            for point in currentPoints.dropFirst() {
                path.line(to: point)
            }
            strokeColor.setStroke()
            path.stroke()
        case .rectangle:
            guard let start = dragStart, let current = dragCurrent else { return }
            let rect = viewLocalRect(start: start, current: current)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = baseLineWidth / scale
            strokeColor.setStroke()
            path.stroke()
        case .mosaic:
            guard let start = dragStart, let current = dragCurrent else { return }
            let viewRect = viewLocalRect(start: start, current: current)
            guard viewRect.width > 1, viewRect.height > 1 else { return }
            let imageRect = NSRect(
                x: viewRect.minX * scale, y: viewRect.minY * scale,
                width: viewRect.width * scale, height: viewRect.height * scale
            )
            let patch = mosaicPatch(from: baseImage, rect: imageRect)
            patch.draw(in: viewRect, from: .zero, operation: .copy, fraction: 1.0)
            let border = NSBezierPath(rect: viewRect)
            border.lineWidth = 1
            NSColor.white.withAlphaComponent(0.9).setStroke()
            border.stroke()
        case .numberMarker:
            break // 點一下就直接烘焙，沒有拖曳中的預覽狀態要畫。
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch tool {
        case .pen:
            currentPoints = [point]
        case .rectangle, .mosaic:
            dragStart = point
            dragCurrent = point
        case .numberMarker:
            placeNumberMarker(at: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch tool {
        case .pen:
            currentPoints.append(point)
        case .rectangle, .mosaic:
            dragCurrent = point
        case .numberMarker:
            break // 單點工具：mouseDown 當下就放好了，拖曳不做事。
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        bakeCurrentShape()
    }

    private func viewLocalRect(start: NSPoint, current: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    private func bakeCurrentShape() {
        let scale = imageSpaceScale

        switch tool {
        case .pen, .rectangle:
            guard let path = strokePath(scale: scale) else {
                clearPendingInput()
                return
            }
            pushUndoSnapshot()
            let composite = NSImage(size: baseImage.size)
            composite.lockFocus()
            baseImage.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
            strokeColor.setStroke()
            path.lineWidth = baseLineWidth
            path.stroke()
            composite.unlockFocus()
            baseImage = composite

        case .mosaic:
            guard let rect = dragRectInImageSpace(scale: scale) else {
                clearPendingInput()
                return
            }
            pushUndoSnapshot()
            let patch = mosaicPatch(from: baseImage, rect: rect)
            let composite = NSImage(size: baseImage.size)
            composite.lockFocus()
            baseImage.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
            patch.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            composite.unlockFocus()
            baseImage = composite

        case .numberMarker:
            break // 已經在 mouseDown 裡烘焙完成。
        }

        clearPendingInput()
        needsDisplay = true
    }

    /// 點一下就放一個帶編號的圓形標記，編號從 1 開始遞增，畫布重開才會重置。
    private func placeNumberMarker(at point: NSPoint) {
        let scale = imageSpaceScale
        pushUndoSnapshot()
        markerCount += 1

        let center = NSPoint(x: point.x * scale, y: point.y * scale)
        let diameter = markerDiameter * scale
        let composite = NSImage(size: baseImage.size)
        composite.lockFocus()
        baseImage.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
        drawNumberMarker(markerCount, center: center, diameter: diameter)
        composite.unlockFocus()
        baseImage = composite
    }

    private func drawNumberMarker(_ number: Int, center: NSPoint, diameter: CGFloat) {
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let circle = NSBezierPath(ovalIn: rect)
        strokeColor.setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        circle.lineWidth = max(1, diameter * 0.05)
        circle.stroke()

        let text = "\(number)"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: diameter * 0.5),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2,
            width: textSize.width, height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func clearPendingInput() {
        currentPoints = []
        dragStart = nil
        dragCurrent = nil
    }

    private func strokePath(scale: CGFloat) -> NSBezierPath? {
        switch tool {
        case .pen:
            guard currentPoints.count > 1 else { return nil }
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: currentPoints[0].x * scale, y: currentPoints[0].y * scale))
            for point in currentPoints.dropFirst() {
                path.line(to: NSPoint(x: point.x * scale, y: point.y * scale))
            }
            return path
        case .rectangle:
            guard let rect = dragRectInImageSpace(scale: scale) else { return nil }
            return NSBezierPath(rect: rect)
        case .mosaic, .numberMarker:
            return nil
        }
    }

    private func dragRectInImageSpace(scale: CGFloat) -> NSRect? {
        guard let start = dragStart, let current = dragCurrent,
              abs(current.x - start.x) > 1 || abs(current.y - start.y) > 1 else { return nil }
        return NSRect(
            x: min(start.x, current.x) * scale, y: min(start.y, current.y) * scale,
            width: abs(current.x - start.x) * scale, height: abs(current.y - start.y) * scale
        )
    }

    /// 把 source 裡 rect 這塊區域變成馬賽克：裁切 → 縮小 → 用最近鄰放大回去（沒有內插，才會有色塊感）。
    /// 全程用 AppKit 既有的座標系統（左下角原點），跟畫布其他地方一致，不會有翻轉問題。
    private func mosaicPatch(from source: NSImage, rect: NSRect) -> NSImage {
        let width = max(rect.width, 1)
        let height = max(rect.height, 1)
        let smallWidth = max(1, Int(width / mosaicBlockSize))
        let smallHeight = max(1, Int(height / mosaicBlockSize))

        let cropped = NSImage(size: NSSize(width: width, height: height))
        cropped.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: rect, operation: .copy, fraction: 1.0)
        cropped.unlockFocus()

        let small = NSImage(size: NSSize(width: smallWidth, height: smallHeight))
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        cropped.draw(
            in: NSRect(x: 0, y: 0, width: CGFloat(smallWidth), height: CGFloat(smallHeight)),
            from: .zero, operation: .copy, fraction: 1.0
        )
        small.unlockFocus()

        let blocky = NSImage(size: NSSize(width: width, height: height))
        blocky.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1.0)
        blocky.unlockFocus()

        return blocky
    }

    private func pushUndoSnapshot() {
        undoStack.append((baseImage, markerCount))
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        baseImage = previous.image
        markerCount = previous.markerCount
        needsDisplay = true
    }
}
