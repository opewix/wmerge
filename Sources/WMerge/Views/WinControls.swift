import AppKit

/// Кнопка в духе Windows: плоская серая с рамкой; у кнопки по умолчанию рамка синяя. Может иметь стрелку-список справа.
final class WinButton: NSView {
    var title: String
    var isDefault = false
    var enabled = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    /// Если задано — справа отделяется стрелка, по щелчку на ней вызывается это.
    var onArrow: ((WinButton) -> Void)?
    private var hover = false, down = false
    private var tracking: NSTrackingArea?

    init(_ title: String, isDefault: Bool = false, onClick: (() -> Void)? = nil) {
        self.title = title
        self.isDefault = isDefault
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(tracking!)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let active = enabled && (hover || down)
        (down && enabled ? NSColor(204, 228, 247) : active ? NSColor(229, 241, 251) : NSColor(225, 225, 225)).setFill()
        r.fill()
        let border = !enabled ? NSColor(191, 191, 191) : (active || isDefault) ? NSColor(0, 120, 215) : NSColor(173, 173, 173)
        border.setStroke()
        let path = NSBezierPath(rect: isDefault && enabled ? r.insetBy(dx: 0.5, dy: 0.5) : r)
        path.lineWidth = isDefault && enabled ? 2 : 1
        path.stroke()
        let color = enabled ? NSColor.black : NSColor(131, 131, 131)
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: color]
        let arrowW: CGFloat = onArrow != nil ? 14 : 0
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - arrowW - size.width) / 2, y: (bounds.height - size.height) / 2 - 0.5), withAttributes: attrs)
        if onArrow != nil {
            let x = bounds.width - arrowW
            color.setFill()
            NSRect(x: x, y: 3, width: 0.7, height: bounds.height - 6).fill()
            let t = NSBezierPath()
            t.move(to: NSPoint(x: x + 3.5, y: bounds.height / 2 - 1.5))
            t.line(to: NSPoint(x: x + 10.5, y: bounds.height / 2 - 1.5))
            t.line(to: NSPoint(x: x + 7, y: bounds.height / 2 + 2.5))
            t.close()
            t.fill()
        }
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { down = true; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        down = false
        needsDisplay = true
        guard enabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        if let onArrow, p.x > bounds.width - 14 { onArrow(self) } else { onClick?() }
    }
}

/// Флажок в духе Windows: квадрат с галочкой и подпись.
final class WinCheck: NSView {
    var title: String
    var on: Bool { didSet { needsDisplay = true } }
    var onChange: ((Bool) -> Void)?

    init(_ title: String, on: Bool = false) {
        self.title = title
        self.on = on
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0.5, y: (bounds.height - 12) / 2, width: 12, height: 12)
        NSColor.white.setFill()
        box.fill()
        NSColor(51, 51, 51).setStroke()
        let p = NSBezierPath(rect: box)
        p.lineWidth = 1
        p.stroke()
        if on {
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 2.5, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + 5, y: box.maxY - 3))
            tick.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 3))
            tick.lineWidth = 1.2
            tick.stroke()
        }
        (title as NSString).draw(at: NSPoint(x: 18, y: (bounds.height - 15) / 2 - 0.5),
                                 withAttributes: [.font: Theme.uiFont, .foregroundColor: NSColor.black])
    }

    override func mouseDown(with event: NSEvent) {
        on.toggle()
        onChange?(on)
    }
}

/// Поле со списком в духе Windows: белое с рамкой, справа «галочка», по ней — список прежних значений.
final class WinCombo: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    var items: [String] = []
    var enabled = true { didSet { field.isEnabled = enabled; needsDisplay = true } }
    var onChange: (() -> Void)?
    /// Значок слева от текста (папка или файл), если есть.
    var glyph: Glyph? { didSet { needsLayout = true; needsDisplay = true } }

    var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue; onChange?() }
    }

    init() {
        super.init(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.uiFont
        field.textColor = .black
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let left: CGFloat = glyph != nil ? 24 : 4
        field.frame = NSRect(x: left, y: (bounds.height - 16) / 2, width: bounds.width - left - 18, height: 16)
    }

    private var focused: Bool {
        guard let editor = window?.firstResponder as? NSText else { return false }
        return editor.delegate === field
    }

    override func draw(_ dirtyRect: NSRect) {
        (enabled ? NSColor.white : NSColor(240, 240, 240)).setFill()
        bounds.fill()
        (focused ? NSColor(0, 120, 215) : enabled ? NSColor(122, 122, 122) : NSColor(204, 204, 204)).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.stroke()
        if let glyph {
            glyph.image(size: 14).draw(in: NSRect(x: 5, y: (bounds.height - 14) / 2, width: 14, height: 14), from: .zero,
                                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let c = NSBezierPath()
        let cx = bounds.width - 9, cy = bounds.height / 2
        c.move(to: NSPoint(x: cx - 3.5, y: cy - 1.5))
        c.line(to: NSPoint(x: cx, y: cy + 2))
        c.line(to: NSPoint(x: cx + 3.5, y: cy - 1.5))
        c.lineWidth = 1
        (enabled ? NSColor(64, 64, 64) : NSColor(160, 160, 160)).setStroke()
        c.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard p.x > bounds.width - 18 else { window?.makeFirstResponder(field); return }
        let menu = NSMenu()
        for item in items {
            let i = NSMenuItem(title: item, action: #selector(pick(_:)), keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        if items.isEmpty { return }
        menu.minimumWidth = bounds.width
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) { text = sender.title }

    func controlTextDidChange(_ obj: Notification) { onChange?() }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
}

/// Рамка группы с подписью на верхней линии.
final class WinGroup: NSView {
    var title: String
    var enabled = true

    init(_ title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(220, 220, 220).setStroke()
        let p = NSBezierPath(rect: NSRect(x: 0.5, y: 7.5, width: bounds.width - 1, height: bounds.height - 8))
        p.lineWidth = 1
        p.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: enabled ? NSColor.black : NSColor(131, 131, 131)]
        let size = (title as NSString).size(withAttributes: attrs)
        Theme.chrome.setFill()
        NSRect(x: 6, y: 0, width: size.width + 4, height: 15).fill()
        (title as NSString).draw(at: NSPoint(x: 8, y: -0.5), withAttributes: attrs)
    }
}
