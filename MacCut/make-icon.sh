#!/bin/bash
# 產生 Resources/AppIcon.icns。
#
# 圖示是程式畫出來的，不是美術檔：要改設計就改這支腳本裡的參數再重跑一次，
# 不需要任何繪圖軟體，也不會有「原始檔不見了只剩 png」的問題。
set -euo pipefail
cd "$(dirname "$0")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/IconGenerator.swift" <<'SWIFT'
import AppKit

// ── 設計參數 ────────────────────────────────────────────────
let bodyTop: UInt32 = 0x565C69      // 石墨漸層（左上）
let bodyBottom: UInt32 = 0x191C23   // 石墨漸層（右下）
let accent: UInt32 = 0xFF6A5C       // 標註筆觸，對應介紹頁的 MacCut 強調色
// ────────────────────────────────────────────────────────────

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

/// Big Sur 之後的 App 圖示是「超橢圓」圓角，不是一般圓角矩形；用一般圓角一眼就看得出格格不入。
func superellipse(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = rect.midY + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// 四個角的裁切標記。比整圈虛線耐縮：縮到 16pt 時虛線會糊成一條灰邊，角標還留得住形狀。
func cornerBrackets(_ ctx: CGContext, rect: CGRect, arm: CGFloat, width: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: rect.minX, y: rect.maxY - arm), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX + arm, y: rect.maxY)),
        (CGPoint(x: rect.maxX - arm, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY - arm)),
        (CGPoint(x: rect.maxX, y: rect.minY + arm), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX - arm, y: rect.minY)),
        (CGPoint(x: rect.minX + arm, y: rect.minY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.minY + arm))
    ]
    for c in corners {
        ctx.move(to: c.0)
        ctx.addLine(to: c.1)
        ctx.addLine(to: c.2)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawIcon(size: CGFloat) {
    let s = size / 1024
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // 1024 的格線上，圖示本體是置中的 824×824，四周各留 100 的透明邊。
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = superellipse(in: body)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 26 * s, color: rgb(0x000000, 0.30))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(bodyBottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [rgb(bodyTop), rgb(bodyBottom)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY),
                           options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(superellipse(in: body.insetBy(dx: 1.5 * s, dy: 1.5 * s)))
    ctx.setStrokeColor(rgb(0xffffff, 0.20))
    ctx.setLineWidth(3 * s)
    ctx.strokePath()
    ctx.restoreGState()

    // 框選（角標）＋ 標註（筆觸）：這個 App 做的兩件事。
    // 線寬給下限，不然 16pt 時整組會淡到看不見。
    cornerBrackets(ctx,
                   rect: CGRect(x: 276 * s, y: 300 * s, width: 472 * s, height: 424 * s),
                   arm: max(3, 128 * s),
                   width: max(1.6, 48 * s),
                   color: rgb(0xffffff, 0.95))

    ctx.saveGState()
    ctx.setStrokeColor(rgb(accent))
    ctx.setLineWidth(max(2, 52 * s))
    ctx.setLineCap(.round)
    let stroke = CGMutablePath()
    stroke.move(to: CGPoint(x: 380 * s, y: 452 * s))
    stroke.addCurve(to: CGPoint(x: 646 * s, y: 560 * s),
                    control1: CGPoint(x: 470 * s, y: 620 * s),
                    control2: CGPoint(x: 556 * s, y: 392 * s))
    ctx.addPath(stroke)
    ctx.strokePath()
    ctx.restoreGState()
}

/// 直接畫進指定像素數的 bitmap。
///
/// 不要用 NSImage.lockFocus()：它會套用主螢幕的 backing scale，在 Retina 機器上
/// 每張圖都會變成兩倍大，iconutil 接著按實際像素重新歸位，最後 icns 裡就會少掉
/// 16 與 128 這兩階（而且完全不會報錯）。
func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size) // 1 point = 1 pixel
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// iconutil 要的固定檔名組合。
let slots: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
var cache: [Int: Data] = [:]
for (name, size) in slots {
    let data = cache[size] ?? png(size: size)
    cache[size] = data
    try! data.write(to: outDir.appendingPathComponent("\(name).png"))
}
SWIFT

echo "▶︎ 編譯圖示產生器…"
swiftc -O "$TMP_DIR/IconGenerator.swift" -o "$TMP_DIR/icongen"

echo "▶︎ 繪製各尺寸…"
"$TMP_DIR/icongen" "$TMP_DIR/MacCut.iconset"

echo "▶︎ 打包成 .icns…"
mkdir -p Resources
iconutil -c icns "$TMP_DIR/MacCut.iconset" -o Resources/AppIcon.icns

echo ""
echo "✅ 完成： $(pwd)/Resources/AppIcon.icns（$(du -h Resources/AppIcon.icns | cut -f1)）"
echo "   接著跑 ./build.sh 就會打包進 MacCut.app。"
