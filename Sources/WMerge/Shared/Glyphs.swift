import AppKit

/// Значки панели инструментов и списка папок. Рисуются кодом в сетке 32×32 (y вниз), образы — как у WinMerge.
enum Glyph: String, CaseIterable {
    case new, open, save, undo, redo, lineDiff
    case nextDiff, prevDiff, nextConflict, prevConflict, firstDiff, currentDiff, lastDiff
    case copyRight, copyLeft, copyRightAdvance, copyLeftAdvance, allRight, allLeft, autoMerge
    case firstFile, prevFile, nextFile, lastFile, options, refresh
    // Список папок (сетка та же, рисунок рассчитан на 16 пунктов).
    case fileSame, fileDiff, fileLeft, fileRight, fileBinarySame, fileBinaryDiff, fileError
    case folderSame, folderDiff, folderLeft, folderRight, folderPlain, filePlain
    case tabFiles, tabFolders, tabOpen

    private static var cache: [String: NSImage] = [:]

    func image(size: CGFloat = 20, enabled: Bool = true) -> NSImage {
        let key = "\(rawValue)-\(size)-\(enabled)"
        if let hit = Glyph.cache[key] { return hit }
        let scale: CGFloat = 2
        let pixels = Int(size * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        // Сетка 32×32 с осью y вниз.
        let t = NSAffineTransform()
        t.translateX(by: 0, yBy: CGFloat(pixels))
        t.scaleX(by: CGFloat(pixels) / 32, yBy: -CGFloat(pixels) / 32)
        t.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        if !enabled, let data = rep.bitmapData {
            // Недоступная кнопка — тот же рисунок в серых тонах, как в Windows.
            for i in stride(from: 0, to: pixels * pixels * 4, by: 4) {
                let a = CGFloat(data[i + 3]) / 255
                guard a > 0 else { continue }
                let lum = (0.3 * CGFloat(data[i]) + 0.59 * CGFloat(data[i + 1]) + 0.11 * CGFloat(data[i + 2])) / a
                let g = 150 + lum * 0.3
                let v = UInt8(min(255, g * a * 0.75))
                data[i] = v; data[i + 1] = v; data[i + 2] = v
                data[i + 3] = UInt8(a * 0.75 * 255)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        rep.size = image.size
        Glyph.cache[key] = image
        return image
    }

    // MARK: Кисти

    private static let green = (NSColor(hex: 0xC6F58A), NSColor(hex: 0x2FBF1E), NSColor(hex: 0x0E6E0E))
    private static let orange = (NSColor(hex: 0xF4B08A), NSColor(hex: 0xE2401C), NSColor(hex: 0x7A2A00))
    private static let blue = (NSColor(hex: 0x6CC8FF), NSColor(hex: 0x0F5FD0), NSColor(hex: 0x0A47A6))
    private static let arrowBlue = (NSColor(hex: 0x4F8FD8), NSColor(hex: 0x12D0F0), NSColor(hex: 0x0A47A6))

    private static func poly(_ pts: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.line(to: NSPoint(x: q.0, y: q.1)) }
        p.close()
        return p
    }

    private static func fill(_ path: NSBezierPath, _ c: (NSColor, NSColor, NSColor), angle: CGFloat = 90, width: CGFloat = 1.6, shadow: Bool = true) {
        if shadow {
            NSGraphicsContext.saveGraphicsState()
            let s = NSAffineTransform()
            s.translateX(by: 1.2, yBy: 1.2)
            let copy = path.copy() as! NSBezierPath
            copy.transform(using: s as AffineTransform)
            NSColor(white: 0, alpha: 0.35).setFill()
            copy.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGradient(starting: c.0, ending: c.1)!.draw(in: path, angle: angle)
        c.2.setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .miter
        path.stroke()
    }

    /// Полоса «отличия»: красные и жёлтые куски с бликом сверху.
    private static func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, red: Bool) {
        let r = NSRect(x: x, y: y, width: w, height: h)
        NSColor(white: 0, alpha: 0.3).setFill()
        r.offsetBy(dx: 1, dy: 1).fill()
        let top = red ? NSColor(hex: 0xE86A6A) : NSColor(hex: 0xF4E46E)
        let bottom = red ? NSColor(hex: 0xE40A0A) : NSColor(hex: 0xF6EA00)
        NSGradient(colors: [top, bottom, bottom], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: r, angle: 90)
        (red ? NSColor(hex: 0xC01818) : NSColor(hex: 0xE0C800)).setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: 0.4, dy: 0.4))
        p.lineWidth = 0.8
        p.stroke()
    }

    private static func page(_ r: NSRect, fold: CGFloat, fill top: NSColor, _ bottom: NSColor, stroke: NSColor, width: CGFloat = 1.4) {
        let p = poly([(r.minX, r.minY), (r.maxX - fold, r.minY), (r.maxX, r.minY + fold), (r.maxX, r.maxY), (r.minX, r.maxY)])
        NSGradient(starting: top, ending: bottom)!.draw(in: p, angle: 90)
        stroke.setStroke()
        p.lineWidth = width
        p.stroke()
        let f = NSBezierPath()
        f.move(to: NSPoint(x: r.maxX - fold, y: r.minY))
        f.line(to: NSPoint(x: r.maxX - fold, y: r.minY + fold))
        f.line(to: NSPoint(x: r.maxX, y: r.minY + fold))
        f.lineWidth = width * 0.8
        f.stroke()
    }

    private static func folder(_ r: NSRect, width: CGFloat = 1.4) {
        let tab = poly([(r.minX, r.minY + 4), (r.minX + 2, r.minY), (r.minX + r.width * 0.42, r.minY),
                        (r.minX + r.width * 0.5, r.minY + 4), (r.maxX, r.minY + 4), (r.maxX, r.maxY), (r.minX, r.maxY)])
        NSGradient(starting: NSColor(hex: 0xF8EE8A), ending: NSColor(hex: 0xD9BC0A))!.draw(in: tab, angle: 90)
        NSColor(hex: 0xA88A00).setStroke()
        tab.lineWidth = width
        tab.stroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: r.minX + 1, y: r.minY + 8))
        line.line(to: NSPoint(x: r.maxX - 1, y: r.minY + 8))
        line.lineWidth = width * 0.7
        NSColor(hex: 0xC8A800).setStroke()
        line.stroke()
    }

    /// Изогнутая стрелка (отмена, обновление): дуга заданной толщины с наконечником.
    private static func curved(center: NSPoint, radius: CGFloat, from: CGFloat, to: CGFloat, clockwise: Bool,
                               thickness: CGFloat, head: CGFloat, _ c: (NSColor, NSColor, NSColor)) {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: clockwise)
        let stroked = arc.cgPath.copy(strokingWithWidth: thickness, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
        let body = NSBezierPath(cgPath: stroked)
        // Наконечник — треугольник в конце дуги, вдоль касательной.
        let a = to * .pi / 180
        let end = NSPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        let dir: CGFloat = clockwise ? -1 : 1
        let tx = -sin(a) * dir, ty = cos(a) * dir
        let nx = cos(a), ny = sin(a)
        let tri = poly([(end.x + nx * head, end.y + ny * head), (end.x - nx * head, end.y - ny * head),
                        (end.x + tx * head * 1.2, end.y + ty * head * 1.2)])
        fill(body, c, width: 1.2)
        fill(tri, c, width: 1.2)
    }

    private static func badge(_ x: CGFloat, _ y: CGFloat, same: Bool) {
        if same {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: y + 8))
            p.line(to: NSPoint(x: x + 5, y: y + 13))
            p.line(to: NSPoint(x: x + 14, y: y + 2))
            p.lineWidth = 7
            NSColor.white.setStroke()
            p.stroke()
            p.lineWidth = 4
            NSColor(hex: 0x1E9E1E).setStroke()
            p.stroke()
        } else {
            let c = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 14, height: 14))
            NSColor(hex: 0xE02020).setFill()
            c.fill()
            NSColor(hex: 0x8A0000).setStroke()
            c.lineWidth = 1
            c.stroke()
            NSColor.white.setFill()
            NSRect(x: x + 5.6, y: y + 2.5, width: 2.8, height: 6).fill()
            NSRect(x: x + 5.6, y: y + 9.6, width: 2.8, height: 2.4).fill()
        }
    }

    private static func textPage(lines: NSColor) {
        page(NSRect(x: 8, y: 2, width: 20, height: 27), fold: 6, fill: .white, NSColor(hex: 0xE4ECFA), stroke: NSColor(hex: 0x3C50C8), width: 2)
        lines.setFill()
        for y in stride(from: 10.0, through: 24.0, by: 4.5) { NSRect(x: 12, y: y, width: 12, height: 2).fill() }
    }

    private static func sideArrow(left: Bool) {
        let p = left
            ? poly([(1, 22), (10, 14), (10, 19), (18, 19), (18, 25), (10, 25), (10, 30)])
            : poly([(31, 22), (22, 14), (22, 19), (14, 19), (14, 25), (22, 25), (22, 30)])
        fill(p, blue, width: 1.2, shadow: false)
    }

    // MARK: Рисунки

    private func draw() {
        typealias G = Glyph
        switch self {
        case .new:
            G.page(NSRect(x: 11, y: 1, width: 17, height: 25), fold: 5, fill: NSColor(hex: 0xF0F5FE), NSColor(hex: 0xC2D6F4), stroke: NSColor(hex: 0x8AA6D8))
            G.page(NSRect(x: 3, y: 5, width: 17, height: 26), fold: 5, fill: NSColor(hex: 0xF0F5FE), NSColor(hex: 0xC2D6F4), stroke: NSColor(hex: 0x8AA6D8))
        case .open:
            G.folder(NSRect(x: 2, y: 8, width: 27, height: 22))
            G.curved(center: NSPoint(x: 22, y: 12), radius: 6, from: 180, to: 290, clockwise: false, thickness: 4.5, head: 4.5, G.green)
        case .save:
            let body = G.poly([(2, 1), (30, 1), (30, 30), (5, 30), (2, 27)])
            G.fill(body, (NSColor(hex: 0x5058C0), NSColor(hex: 0x282E96), NSColor(hex: 0x10106E)))
            NSGradient(starting: .white, ending: NSColor(hex: 0xD8DCF4))!.draw(in: NSRect(x: 7, y: 2, width: 19, height: 13), angle: 90)
            NSGradient(starting: NSColor(hex: 0xF4F4FC), ending: NSColor(hex: 0xC0C4E8))!.draw(in: NSRect(x: 8, y: 20, width: 15, height: 10), angle: 0)
            NSColor(hex: 0x282E96).setFill()
            NSRect(x: 11, y: 22, width: 3, height: 7).fill()
        case .undo, .redo:
            if self == .redo {
                let m = NSAffineTransform()
                m.translateX(by: 32, yBy: 0)
                m.scaleX(by: -1, yBy: 1)
                m.concat()
            }
            // Дуга от правого низа через верх к левому низу, наконечник смотрит вниз-влево.
            let arc = NSBezierPath()
            arc.move(to: NSPoint(x: 27, y: 27))
            arc.curve(to: NSPoint(x: 9, y: 17), controlPoint1: NSPoint(x: 27, y: 12), controlPoint2: NSPoint(x: 14, y: 8))
            let body = NSBezierPath(cgPath: arc.cgPath.copy(strokingWithWidth: 6.5, lineCap: .butt, lineJoin: .round, miterLimit: 4))
            let c = (NSColor(hex: 0x8ED4FF), NSColor(hex: 0x1FB4F0), NSColor(hex: 0x0A5AA8))
            G.fill(body, c, width: 1.2)
            G.fill(G.poly([(1, 8), (16, 12), (3, 24)]), c, width: 1.2)
        case .lineDiff:
            G.bar(0, 5, 30, 9, red: false)
            G.bar(0, 18, 30, 9, red: true)
            NSColor.black.setStroke()
            let frame = NSBezierPath(rect: NSRect(x: 5.5, y: 1.5, width: 20, height: 29))
            frame.lineWidth = 2.4
            frame.stroke()
            for (y, word) in [(6.0, "CBA"), (19.0, "ABC")] {
                NSColor.black.setFill()
                NSRect(x: 8, y: y, width: 15, height: 7.5).fill()
                NSGraphicsContext.saveGraphicsState()
                let flip = NSAffineTransform()
                flip.translateX(by: 0, yBy: y + 7.2)
                flip.scaleX(by: 1, yBy: -1)
                flip.concat()
                (word as NSString).draw(at: NSPoint(x: 8.6, y: -0.4), withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 6.6), .foregroundColor: NSColor.white, .kern: 0.2,
                ])
                NSGraphicsContext.restoreGraphicsState()
            }
        case .nextDiff, .nextConflict:
            if self == .nextConflict { G.bar(0, 22, 10, 8, red: true); G.bar(10, 22, 11, 8, red: false); G.bar(21, 22, 10, 8, red: true) } else {
                G.bar(0, 22, 15, 8, red: true); G.bar(15, 22, 15, 8, red: false)
            }
            G.fill(G.poly([(9, 1), (21, 1), (21, 11), (29, 11), (15, 26), (1, 11), (9, 11)]), self == .nextDiff ? G.green : G.orange)
        case .prevDiff, .prevConflict:
            if self == .prevConflict { G.bar(0, 1, 10, 8, red: true); G.bar(10, 1, 11, 8, red: false); G.bar(21, 1, 10, 8, red: true) } else {
                G.bar(0, 1, 15, 8, red: true); G.bar(15, 1, 15, 8, red: false)
            }
            G.fill(G.poly([(15, 6), (29, 21), (21, 21), (21, 31), (9, 31), (9, 21), (1, 21)]), self == .prevDiff ? G.green : G.orange)
        case .firstDiff:
            G.bar(0, 1, 15, 8, red: true); G.bar(15, 1, 15, 8, red: false)
            G.fill(G.poly([(15, 6), (28, 19), (2, 19)]), G.green)
            G.fill(G.poly([(15, 17), (28, 30), (2, 30)]), G.green)
        case .currentDiff:
            G.bar(0, 11, 15, 9, red: true); G.bar(15, 11, 15, 9, red: false)
            G.fill(G.poly([(2, 1), (28, 1), (15, 15)]), G.green)
            G.fill(G.poly([(15, 16), (28, 30), (2, 30)]), G.green)
        case .lastDiff:
            G.bar(0, 22, 15, 8, red: true); G.bar(15, 22, 15, 8, red: false)
            G.fill(G.poly([(2, 1), (28, 1), (15, 14)]), G.green)
            G.fill(G.poly([(2, 12), (28, 12), (15, 25)]), G.green)
        case .copyRight:
            G.bar(0, 12, 11, 8, red: true); G.bar(20, 12, 10, 8, red: false)
            G.fill(G.poly([(9, 2), (24, 16), (9, 30)]), G.blue, angle: 0)
        case .copyLeft:
            G.bar(0, 12, 10, 8, red: false); G.bar(19, 12, 11, 8, red: true)
            G.fill(G.poly([(21, 2), (6, 16), (21, 30)]), G.blue, angle: 180)
        case .copyRightAdvance:
            G.bar(0, 12, 6, 8, red: true); G.bar(15, 12, 15, 7, red: false)
            G.fill(G.poly([(4, 2), (18, 15), (4, 28)]), G.blue, angle: 0)
            G.fill(G.poly([(20, 19), (27, 19), (27, 24), (31, 24), (23.5, 31), (16, 24), (20, 24)]), G.green, width: 1.2)
        case .copyLeftAdvance:
            G.bar(1, 12, 15, 7, red: false); G.bar(25, 12, 6, 8, red: true)
            G.fill(G.poly([(28, 2), (14, 15), (28, 28)]), G.blue, angle: 180)
            G.fill(G.poly([(5, 19), (12, 19), (12, 24), (16, 24), (8.5, 31), (1, 24), (5, 24)]), G.green, width: 1.2)
        case .allRight:
            G.tall(1, red: true); G.tall(17, red: false)
            G.fill(G.poly([(5, 11), (17, 11), (17, 4), (29, 16), (17, 28), (17, 21), (5, 21)]), G.arrowBlue)
        case .allLeft:
            G.tall(1, red: false); G.tall(17, red: true)
            G.fill(G.poly([(27, 11), (15, 11), (15, 4), (3, 16), (15, 28), (15, 21), (27, 21)]), G.arrowBlue)
        case .autoMerge:
            G.tall(0, red: true, width: 8); G.tall(11, red: false, width: 10); G.tall(24, red: true, width: 8)
            G.fill(G.poly([(2, 13), (9, 13), (9, 10), (15, 16), (9, 22), (9, 19), (2, 19)]), G.arrowBlue, width: 1.2)
            G.fill(G.poly([(30, 13), (23, 13), (23, 10), (17, 16), (23, 22), (23, 19), (30, 19)]), G.arrowBlue, width: 1.2)
        case .firstFile, .prevFile:
            G.tall(2, red: false)
            NSColor.black.setFill()
            NSRect(x: 4, y: 5, width: self == .firstFile ? 2.4 : 1, height: 22).fill()
            G.fill(G.poly([(29, 11), (18, 11), (18, 4), (6, 16), (18, 28), (18, 21), (29, 21)]), G.arrowBlue)
        case .nextFile, .lastFile:
            G.tall(16, red: false)
            NSColor.black.setFill()
            NSRect(x: self == .lastFile ? 25.6 : 27, y: 5, width: self == .lastFile ? 2.4 : 1, height: 22).fill()
            G.fill(G.poly([(3, 11), (14, 11), (14, 4), (26, 16), (14, 28), (14, 21), (3, 21)]), G.arrowBlue)
        case .options:
            let box = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 28, height: 28), xRadius: 3, yRadius: 3)
            NSGradient(colors: [NSColor(hex: 0xD88080), NSColor(hex: 0xD03010), NSColor(hex: 0xF07000), NSColor(hex: 0xF8D000)],
                       atLocations: [0, 0.45, 0.7, 1], colorSpace: .sRGB)!.draw(in: box, angle: 90)
            NSColor(hex: 0xA01818).setStroke()
            box.lineWidth = 1.4
            box.stroke()
            // Гаечный ключ по диагонали.
            let wrench = NSBezierPath()
            wrench.move(to: NSPoint(x: 9, y: 24))
            wrench.line(to: NSPoint(x: 22, y: 10))
            for (w, c) in [(6.5, NSColor(hex: 0x808080)), (4.2, NSColor(hex: 0xF4F4F4))] {
                wrench.lineWidth = w
                wrench.lineCapStyle = .round
                c.setStroke()
                wrench.stroke()
                for (cx, cy, gap) in [(23.0, 9.0, 45.0), (8.0, 25.0, 225.0)] {
                    let jaw = NSBezierPath()
                    jaw.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: 4, startAngle: gap - 80 + 180 - 135, endAngle: gap - 80 + 180 + 135 - 20)
                    jaw.lineWidth = w - 2.2
                    jaw.stroke()
                }
            }
        case .refresh:
            G.curved(center: NSPoint(x: 15, y: 17), radius: 9, from: 80, to: 250, clockwise: false, thickness: 6, head: 5.5,
                     (NSColor(hex: 0x6CB4FF), NSColor(hex: 0x0E5AD0), NSColor(hex: 0x0A3F9A)))
            G.curved(center: NSPoint(x: 17, y: 15), radius: 9, from: 260, to: 70, clockwise: false, thickness: 6, head: 5.5, G.green)
        case .fileSame:
            G.textPage(lines: NSColor(hex: 0x2E8B2E)); G.badge(1, 16, same: true)
        case .fileDiff:
            G.textPage(lines: NSColor(hex: 0xD03030)); G.badge(1, 17, same: false)
        case .fileBinarySame:
            G.textPage(lines: NSColor(hex: 0x808080)); G.badge(1, 16, same: true)
        case .fileBinaryDiff:
            G.textPage(lines: NSColor(hex: 0x808080)); G.badge(1, 17, same: false)
        case .fileLeft:
            G.textPage(lines: NSColor(hex: 0x3C50C8)); G.sideArrow(left: true)
        case .fileRight:
            G.textPage(lines: NSColor(hex: 0x3C50C8)); G.sideArrow(left: false)
        case .fileError:
            G.textPage(lines: NSColor(hex: 0x808080))
            NSColor(hex: 0xE02020).setStroke()
            let x = NSBezierPath()
            x.move(to: NSPoint(x: 2, y: 18)); x.line(to: NSPoint(x: 14, y: 30))
            x.move(to: NSPoint(x: 14, y: 18)); x.line(to: NSPoint(x: 2, y: 30))
            x.lineWidth = 3.5
            x.stroke()
        case .filePlain:
            G.textPage(lines: NSColor(hex: 0x3C50C8))
        case .folderPlain, .folderSame:
            G.folder(NSRect(x: 3, y: 6, width: 27, height: 22), width: 2)
        case .folderDiff:
            G.folder(NSRect(x: 3, y: 6, width: 27, height: 22), width: 2); G.badge(1, 16, same: false)
        case .folderLeft:
            G.folder(NSRect(x: 3, y: 6, width: 27, height: 22), width: 2); G.sideArrow(left: true)
        case .folderRight:
            G.folder(NSRect(x: 3, y: 6, width: 27, height: 22), width: 2); G.sideArrow(left: false)
        case .tabFiles:
            G.page(NSRect(x: 2, y: 3, width: 14, height: 26), fold: 4, fill: .white, NSColor(hex: 0xE4ECFA), stroke: NSColor(hex: 0x3C50C8), width: 2)
            G.page(NSRect(x: 16, y: 3, width: 14, height: 26), fold: 4, fill: .white, NSColor(hex: 0xE4ECFA), stroke: NSColor(hex: 0x3C50C8), width: 2)
            G.bar(4, 13, 10, 4, red: true); G.bar(18, 13, 10, 4, red: false)
            G.bar(4, 21, 10, 4, red: false); G.bar(18, 21, 10, 4, red: true)
        case .tabFolders:
            G.folder(NSRect(x: 1, y: 3, width: 20, height: 16), width: 2)
            G.folder(NSRect(x: 10, y: 13, width: 20, height: 16), width: 2)
        case .tabOpen:
            G.folder(NSRect(x: 2, y: 8, width: 27, height: 22), width: 2)
        }
    }

    private static func tall(_ x: CGFloat, red: Bool, width: CGFloat = 13) {
        let r = NSRect(x: x, y: 1, width: width, height: 29)
        NSColor(white: 0, alpha: 0.3).setFill()
        r.offsetBy(dx: 1, dy: 1).fill()
        let top = red ? NSColor(hex: 0xE07070) : NSColor(hex: 0xF0E060)
        let bottom = red ? NSColor(hex: 0xF02010) : NSColor(hex: 0xFFF020)
        NSGradient(starting: top, ending: bottom)!.draw(in: r, angle: 90)
        (red ? NSColor(hex: 0xC01818) : NSColor(hex: 0xE0C800)).setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: 0.6, dy: 0.6))
        p.lineWidth = 1.2
        p.stroke()
    }
}
