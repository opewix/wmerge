import AppKit

/// Размеры редактора при текущем шрифте.
final class EditorMetrics {
    let font: NSFont
    let bold: NSFont
    let lineH: CGFloat
    let charW: CGFloat
    let ascent: CGFloat
    let paragraph: NSParagraphStyle

    init() {
        font = Theme.editorFont
        bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        charW = ("0" as NSString).size(withAttributes: [.font: font]).width
        lineH = ceil(font.ascender - font.descender + font.leading) + 2
        ascent = font.ascender + 1
        let p = NSMutableParagraphStyle()
        p.tabStops = []
        p.defaultTabInterval = charW * CGFloat(Theme.tabSize)
        p.lineBreakMode = .byClipping
        paragraph = p
    }
}

/// Полоса прокрутки в духе Windows 11: серый бегунок на светлой дорожке.
final class WinScroller: NSView {
    let vertical: Bool
    var proportion: CGFloat = 1 { didSet { needsDisplay = true } }
    var value: CGFloat = 0 { didSet { needsDisplay = true } }
    var onChange: ((CGFloat) -> Void)?
    var onPage: ((Int) -> Void)?
    private var grab: CGFloat?

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var track: CGFloat { vertical ? bounds.height : bounds.width }
    private var thumbLength: CGFloat { max(18, track * min(1, proportion)) }

    private var thumbRect: NSRect? {
        guard proportion < 1, track > 24 else { return nil }
        let pos = (track - thumbLength) * min(max(value, 0), 1)
        return vertical
            ? NSRect(x: 2.5, y: pos, width: bounds.width - 5, height: thumbLength)
            : NSRect(x: pos, y: 3.5, width: thumbLength, height: bounds.height - 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        guard let r = thumbRect else { return }
        Theme.scrollThumb.setFill()
        r.fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let c = vertical ? p.y : p.x
        guard let r = thumbRect else { return }
        let start = vertical ? r.minY : r.minX
        if c >= start && c <= start + thumbLength {
            grab = c - start
        } else {
            onPage?(c < start ? -1 : 1)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab else { return }
        let p = convert(event.locationInWindow, from: nil)
        let c = (vertical ? p.y : p.x) - grab
        let span = track - thumbLength
        guard span > 0 else { return }
        onChange?(min(max(c / span, 0), 1))
    }

    override func mouseUp(with event: NSEvent) { grab = nil }
}

/// Заголовок панели: путь по центру полужирным на скруглённой плашке, справа «≡».
final class PaneHeader: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var active = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        let r = bounds.insetBy(dx: 1, dy: 0)
        (active ? Theme.headerActive : Theme.headerInactive).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingHead
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black, .paragraphStyle: p]
        (text as NSString).draw(in: NSRect(x: 8, y: (bounds.height - 15) / 2 - 0.5, width: bounds.width - 34, height: 16), withAttributes: attrs)
        ("≡" as NSString).draw(at: NSPoint(x: bounds.width - 20, y: (bounds.height - 16) / 2 - 1),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.2, alpha: 1)])
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x > bounds.width - 26 { onMenu?(event) } else { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
}

/// Строка состояния панели: место курсора, кодировка, концы строк, признак «только чтение».
final class PaneStatus: NSView {
    var position = "" { didSet { needsDisplay = true } }
    var encoding = "" { didSet { needsDisplay = true } }
    var eol = "" { didSet { needsDisplay = true } }
    var readOnly = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: NSColor.black]
        let y = (bounds.height - 15) / 2 - 0.5
        let w = bounds.width
        (position as NSString).draw(at: NSPoint(x: 3, y: y), withAttributes: attrs)
        (encoding as NSString).draw(at: NSPoint(x: max(w * 0.58, 190), y: y), withAttributes: attrs)
        (eol as NSString).draw(at: NSPoint(x: max(w * 0.86, 290), y: y), withAttributes: attrs)
        if readOnly { ("RO" as NSString).draw(at: NSPoint(x: w - 22, y: y), withAttributes: attrs) }
    }
}

/// Панель расположения: файл целиком в двух полосках, отличия — цветными полосами.
final class LocationPane: NSView {
    unowned let host: FileCompareView
    static let width: CGFloat = 80
    private let captionH: CGFloat = 16

    init(host: FileCompareView) {
        self.host = host
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var barArea: NSRect { NSRect(x: 0, y: captionH + 2, width: bounds.width, height: bounds.height - captionH - 4) }

    /// Высота одной строки экрана в полоске: файл сжимается до высоты панели, короткий не растягивается.
    private var rowScale: CGFloat {
        let rows = max(1, host.doc.diff.rows.count)
        return min(host.metrics.lineH / 3, (barArea.height - 4) / CGFloat(rows))
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        // Заголовок с крестиком.
        let caption = NSRect(x: 0, y: 0, width: bounds.width - 14, height: captionH)
        NSColor(225, 232, 244).setFill()
        caption.fill()
        ("Location Pane" as NSString).draw(at: NSPoint(x: 2, y: 1.5), withAttributes: [.font: NSFont.systemFont(ofSize: 9.5), .foregroundColor: NSColor.black])
        ("✕" as NSString).draw(at: NSPoint(x: bounds.width - 11, y: 2), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.black])

        let area = barArea
        Theme.locationBackground.setFill()
        area.fill()
        let barW = floor(area.width * 0.24)
        let xs = [floor(area.width * 0.16), floor(area.width * 0.60)]
        let top = area.minY + 2
        let scale = rowScale
        let diff = host.doc.diff
        let total = CGFloat(diff.rows.count)
        for side in 0..<2 {
            let bar = NSRect(x: xs[side], y: top, width: barW, height: area.height - 4)
            NSColor.white.setFill()
            bar.fill()
            NSColor(200, 200, 220).setStroke()
            NSBezierPath.defaultLineWidth = 1
            NSBezierPath.stroke(bar.insetBy(dx: -0.5, dy: -0.5))
            for (index, block) in diff.blocks.enumerated() {
                let selected = index == host.doc.currentBlock
                let present = side == 0 ? block.aCount > 0 : block.bCount > 0
                let color: NSColor
                if block.trivial { color = present ? Theme.trivial : Theme.trivialDeleted } else if selected {
                    color = present ? Theme.selDiff : Theme.selDiffDeleted
                } else { color = present ? Theme.diff : Theme.diffDeleted }
                color.setFill()
                let y = top + CGFloat(block.rowStart) * scale
                NSRect(x: bar.minX, y: floor(y), width: barW, height: max(1, ceil(CGFloat(block.rowCount) * scale))).fill()
            }
        }
        // Видимая часть: полупрозрачная плашка поперёк обеих полосок с треугольниками по краям.
        let visY = top + CGFloat(host.topRow) * scale
        let visH = max(4, min(total, CGFloat(host.visibleRows)) * scale)
        let vis = NSRect(x: 3, y: visY, width: area.width - 6, height: visH)
        NSColor(150, 160, 210).withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: vis, xRadius: 3, yRadius: 3).fill()
        if host.doc.currentBlock >= 0 {
            let block = diff.blocks[host.doc.currentBlock]
            let cy = top + (CGFloat(block.rowStart) + CGFloat(block.rowCount) / 2) * scale
            NSColor(110, 140, 200).setFill()
            for (x, dir) in [(xs[0] - 8, CGFloat(1)), (xs[1] + barW + 8, CGFloat(-1))] {
                let t = NSBezierPath()
                t.move(to: NSPoint(x: x, y: cy - 3.5))
                t.line(to: NSPoint(x: x + 5 * dir, y: cy))
                t.line(to: NSPoint(x: x, y: cy + 3.5))
                t.close()
                t.fill()
            }
        }
    }

    private func scroll(to event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = Int((p.y - barArea.minY - 2) / rowScale)
        host.scrollTo(top: row - host.visibleRows / 2)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y < captionH {
            if p.x > bounds.width - 14 { MainWindowController.shared.run(.locationPane) }
            return
        }
        scroll(to: event)
    }

    override func mouseDragged(with event: NSEvent) { scroll(to: event) }
}

/// Панель отличия (внизу): строки выбранного отличия — сверху левые, снизу правые.
final class DiffDetailPane: NSView {
    unowned let host: FileCompareView
    static let height: CGFloat = 112
    private let captionH: CGFloat = 16

    init(host: FileCompareView) {
        self.host = host
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        NSColor(225, 232, 244).setFill()
        NSRect(x: 0, y: 0, width: 62, height: captionH).fill()
        ("Diff Pane" as NSString).draw(at: NSPoint(x: 3, y: 0.5), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
        ("✕" as NSString).draw(at: NSPoint(x: 66, y: 1), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
        let half = floor((bounds.height - captionH - 3) / 2)
        for side in 0..<2 {
            let r = NSRect(x: 0, y: captionH + CGFloat(side) * (half + 3), width: bounds.width, height: half)
            NSColor.white.setFill()
            r.fill()
            guard host.doc.currentBlock >= 0 else { continue }
            let block = host.doc.diff.blocks[host.doc.currentBlock]
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r).addClip()
            var y = r.minY
            for row in block.rowStart..<(block.rowStart + block.rowCount) where y < r.maxY {
                host.drawRow(row, side: side, y: y, textX: 3, clip: r, selection: false)
                y += host.metrics.lineH
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y < captionH && p.x > 60 && p.x < 82 { MainWindowController.shared.run(.diffPane) }
    }
}
