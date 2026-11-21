// Рисует значок программы в .iconset для iconutil: два листа с полосами отличий и синяя стрелка слияния.
// См. scripts/bundle.sh. Собирается вместе с Sources/WMerge/Shared/Theme.swift (цвета).
import AppKit

// Плитка по сетке значков macOS: холст 1024, отступ 100, сторона 824, радиус 185,4. Только такую форму
// macOS 26 показывает во весь скруглённый квадрат; иную сажает на серую подложку и уменьшает.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185.4, yRadius: 185.4)

func drawIcon() {
    let r = tileRect
    NSGradient(starting: NSColor(hex: 0xF4F7FB), ending: NSColor(hex: 0xC9D6E6))!.draw(in: NSBezierPath(rect: r), angle: -90)
    // Два листа.
    let sheets = [NSRect(x: r.minX + 80, y: r.minY + 110, width: 300, height: 600), NSRect(x: r.maxX - 380, y: r.minY + 110, width: 300, height: 600)]
    for sheet in sheets {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 24
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: sheet, xRadius: 22, yRadius: 22).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    // Строки: серые — одинаковые, жёлтые и красные — отличия, как в окне сравнения.
    let bands: [(CGFloat, Int, Int)] = [(0, 0, 0), (1, 0, 0), (2, 1, 1), (3, 0, 0), (4, 2, 2), (5, 2, 3), (6, 0, 0), (7, 1, 3), (8, 0, 0)]
    let colors = [NSColor(hex: 0xD5DBE3), NSColor(239, 203, 5), NSColor(239, 119, 116), NSColor(192, 192, 192)]
    for (index, left, right) in bands {
        let y = sheets[0].maxY - 90 - index * 58
        for (sheet, kind) in [(sheets[0], left), (sheets[1], right)] {
            colors[kind].setFill()
            let inset: CGFloat = kind == 0 ? 36 : 0
            NSBezierPath(roundedRect: NSRect(x: sheet.minX + inset, y: y, width: sheet.width - inset * 2 - (kind == 0 ? CGFloat(Int(index) % 3) * 30 : 0), height: 34),
                         xRadius: kind == 0 ? 10 : 0, yRadius: kind == 0 ? 10 : 0).fill()
        }
    }
    // Стрелка слияния между листами.
    let cx = r.midX, cy = r.midY - 30
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: cx - 120, y: cy + 50))
    arrow.line(to: NSPoint(x: cx + 10, y: cy + 50))
    arrow.line(to: NSPoint(x: cx + 10, y: cy + 120))
    arrow.line(to: NSPoint(x: cx + 150, y: cy))
    arrow.line(to: NSPoint(x: cx + 10, y: cy - 120))
    arrow.line(to: NSPoint(x: cx + 10, y: cy - 50))
    arrow.line(to: NSPoint(x: cx - 120, y: cy - 50))
    arrow.close()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowBlurRadius = 16
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(hex: 0x0F5FD0).setFill()
    arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(hex: 0x6CC8FF), ending: NSColor(hex: 0x0F5FD0))!.draw(in: arrow, angle: -90)
    NSColor(hex: 0x0A47A6).setStroke()
    arrow.lineWidth = 12
    arrow.lineJoinStyle = .round
    arrow.stroke()
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scaleTo = NSAffineTransform()
        scaleTo.scale(by: CGFloat(pixels) / 1024)
        scaleTo.concat()
        tile.addClip()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
