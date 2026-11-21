import AppKit

/// Одна сторона сравнения: рисует видимые строки и передаёт мышь и клавиши хозяину.
final class TextPane: NSView, NSTextInputClient {
    unowned let host: FileCompareView
    let side: Int

    init(host: FileCompareView, side: Int) {
        self.host = host
        self.side = side
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        host.activate(side: side)
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    /// Ширина поля слева: отступ, поле выделения, номера строк.
    var gutter: CGFloat {
        var g: CGFloat = 0
        if ViewFlag.margin.isOn { g += 14 }
        if ViewFlag.lineNumbers.isOn {
            let digits = max(3, String(host.doc.sides[side].lines.count).count)
            g += CGFloat(digits) * host.metrics.charW + 8
        }
        return g
    }

    var textOrigin: CGFloat { gutter + 3 }
    var textWidth: CGFloat { max(10, bounds.width - textOrigin) }

    override func draw(_ dirtyRect: NSRect) {
        let m = host.metrics
        Theme.textBackground.setFill()
        bounds.fill()
        let g = gutter
        let rows = host.doc.diff.rows
        let first = host.topRow
        let count = Int(ceil(bounds.height / m.lineH))
        let textClip = NSRect(x: g, y: 0, width: bounds.width - g, height: bounds.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textClip).addClip()
        for i in 0..<count {
            let row = first + i
            guard row < rows.count else { break }
            host.drawRow(row, side: side, y: CGFloat(i) * m.lineH, textX: textOrigin - host.hOffset, clip: textClip, selection: true)
        }
        // Курсор.
        if host.active == side, host.caretOn, window?.firstResponder === self, window?.isKeyWindow == true || Snapshot.active {
            let row = host.row(of: host.caret.line, side: side)
            if row >= first && row < first + count {
                let x = textOrigin - host.hOffset + host.x(side: side, pos: host.caret)
                NSColor.black.setFill()
                NSRect(x: floor(x), y: CGFloat(row - first) * m.lineH, width: 1.5, height: m.lineH).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        if g > 0 {
            Theme.margin.setFill()
            NSRect(x: 0, y: 0, width: g, height: bounds.height).fill()
            if ViewFlag.lineNumbers.isOn {
                let attrs: [NSAttributedString.Key: Any] = [.font: m.font, .foregroundColor: Theme.marginText]
                for i in 0..<count {
                    let row = first + i
                    guard row < rows.count else { break }
                    guard let line = side == 0 ? rows[row].left : rows[row].right else { continue }
                    let s = String(line + 1) as NSString
                    let w = s.size(withAttributes: attrs).width
                    s.draw(at: NSPoint(x: g - 4 - w, y: CGFloat(i) * m.lineH + 1), withAttributes: attrs)
                }
            }
        }
    }

    // MARK: Мышь

    private func place(_ event: NSEvent) -> (row: Int, x: CGFloat, inGutter: Bool) {
        let p = convert(event.locationInWindow, from: nil)
        let row = host.topRow + Int(floor(p.y / host.metrics.lineH))
        return (row, p.x - textOrigin + host.hOffset, p.x < gutter)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = place(event)
        host.mouseDown(side: side, row: p.row, x: p.x, clicks: event.clickCount,
                       shift: event.modifierFlags.contains(.shift), gutter: p.inGutter)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = place(event)
        host.mouseDragged(side: side, row: p.row, x: p.x)
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) { host.mouseUp() }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = place(event)
        if !host.hasSelection { host.mouseDown(side: side, row: p.row, x: p.x, clicks: 1, shift: false, gutter: false); host.mouseUp() }
        NSMenu.popUpContextMenu(host.contextMenu(), with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) { host.handleWheel(event) }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: gutter, y: 0, width: bounds.width - gutter, height: bounds.height), cursor: .iBeam)
    }

    // MARK: Клавиши

    override func keyDown(with event: NSEvent) {
        if !host.keyDown(event) { interpretKeyEvents([event]) }
    }

    override func doCommand(by selector: Selector) {}

    func insertText(_ string: Any, replacementRange: NSRange) {
        let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        host.type(s)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let row = host.row(of: host.caret.line, side: side) - host.topRow
        let local = NSRect(x: textOrigin - host.hOffset + host.x(side: side, pos: host.caret), y: CGFloat(row) * host.metrics.lineH,
                           width: 1, height: host.metrics.lineH)
        return window?.convertToScreen(convert(local, to: nil)) ?? .zero
    }
}
