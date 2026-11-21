import AppKit

/// Вкладка сравнения двух файлов: панель расположения, две панели текста, панель отличия, строки состояния.
final class FileCompareView: NSView, DocumentTab {
    private(set) var doc: CompareDocument
    private(set) var metrics = EditorMetrics()

    // Прокрутка: первая видимая строка экрана и сдвиг по горизонтали, общие для обеих панелей.
    private(set) var topRow = 0
    private(set) var hOffset: CGFloat = 0
    private var wheelRemainder: CGFloat = 0
    private var maxLineWidth: CGFloat = 0

    // Курсор и выделение — в активной панели.
    private(set) var active = 0
    private(set) var caret = TextPos(line: 0, col: 0)
    private var anchor: TextPos?
    private var desiredX: CGFloat?
    private(set) var caretOn = true
    private var blink: Timer?
    private var dragging = false

    private var location: LocationPane!
    private var detail: DiffDetailPane!
    private var headers: [PaneHeader] = []
    private var panes: [TextPane] = []
    private var hScrollers: [WinScroller] = []
    private var vScroller = WinScroller(vertical: true)
    private var statuses: [PaneStatus] = []

    // Кэши, сбрасываются при любом изменении текста.
    private var lineCache: [[Int: CTLine]] = [[:], [:]]
    private var inlineCache: [Int: (a: [NSRange], b: [NSRange])] = [:]
    private var languages: [Language?] = [nil, nil]
    private var syntaxStates: [[Bool]?] = [nil, nil]

    init(left: TextFile, right: TextFile) {
        doc = CompareDocument(left: left, right: right)
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        location = LocationPane(host: self)
        detail = DiffDetailPane(host: self)
        addSubview(location)
        addSubview(detail)
        for side in 0..<2 {
            let header = PaneHeader()
            header.onClick = { [unowned self] in self.focus(side: side) }
            header.onMenu = { [unowned self] event in self.headerMenu(side: side, event: event) }
            headers.append(header)
            addSubview(header)
            let pane = TextPane(host: self, side: side)
            panes.append(pane)
            addSubview(pane)
            let h = WinScroller(vertical: false)
            h.onChange = { [unowned self] v in self.setHOffset(v * self.maxHOffset) }
            h.onPage = { [unowned self] dir in self.setHOffset(self.hOffset + CGFloat(dir) * self.panes[0].textWidth * 0.9) }
            hScrollers.append(h)
            addSubview(h)
            let status = PaneStatus()
            statuses.append(status)
            addSubview(status)
        }
        vScroller.onChange = { [unowned self] v in self.scrollTo(top: Int((v * CGFloat(self.maxTop)).rounded())) }
        vScroller.onPage = { [unowned self] dir in self.scrollTo(top: self.topRow + dir * max(1, self.visibleRows - 1)) }
        addSubview(vScroller)
        languages = doc.sides.map { Language.forPath($0.path) }
        if languages[0] == nil { languages[0] = languages[1] }
        if languages[1] == nil { languages[1] = languages[0] }
        didChange(keepCaretVisible: false)
        if !Snapshot.active {
            blink = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
                guard let self, self.window != nil else { return }
                self.caretOn.toggle()
                self.panes[self.active].needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { blink?.invalidate() }
    override var isFlipped: Bool { true }

    // MARK: Вкладка

    private func name(_ side: Int) -> String {
        if let path = doc.sides[side].path { return (path as NSString).lastPathComponent }
        return side == 0 ? "Untitled Left" : "Untitled Right"
    }

    var tabTitle: String {
        let a = name(0), b = name(1)
        return a == b ? "\(a) x 2" : "\(a) - \(b)"
    }

    var tabGlyph: Glyph { .tabFiles }

    var statusRight: String {
        let n = doc.significantCount
        if n == 0 { return "Identical" }
        if let ordinal = doc.currentOrdinal { return "Difference \(ordinal + 1) of \(n)" }
        return n == 1 ? "1 Difference Found" : "\(n) Differences Found"
    }

    func activated() {
        window?.makeFirstResponder(panes[active])
    }

    func settingsChanged() {
        metrics = EditorMetrics()
        doc.rescan()
        didChange(keepCaretVisible: false)
        needsLayout = true
    }

    // MARK: Раскладка

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let statusH: CGFloat = 17, headerH: CGFloat = 19, scrollH: CGFloat = 12, vW: CGFloat = 12, gap: CGFloat = 4
        let locW: CGFloat = ViewFlag.locationPane.isOn ? LocationPane.width + 4 : 0
        let detailH: CGFloat = ViewFlag.diffPane.isOn ? DiffDetailPane.height + 3 : 0
        location.isHidden = locW == 0
        detail.isHidden = detailH == 0
        location.frame = NSRect(x: 4, y: 2, width: LocationPane.width, height: h - statusH - 4)
        let x0 = locW + 4
        let paneW = floor((w - x0 - vW - gap) / 2)
        let textTop = headerH + 3
        let textH = h - statusH - detailH - textTop - scrollH
        for side in 0..<2 {
            let x = x0 + CGFloat(side) * (paneW + gap)
            headers[side].frame = NSRect(x: x, y: 2, width: paneW, height: headerH)
            panes[side].frame = NSRect(x: x, y: textTop, width: paneW, height: textH)
            hScrollers[side].frame = NSRect(x: x, y: textTop + textH, width: paneW, height: scrollH)
            statuses[side].frame = NSRect(x: x, y: h - statusH, width: paneW, height: statusH)
        }
        vScroller.frame = NSRect(x: w - vW, y: textTop, width: vW, height: textH)
        detail.frame = NSRect(x: x0, y: textTop + textH + scrollH + 3, width: w - x0, height: DiffDetailPane.height)
        clampScroll()
        updateScrollers()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
    }

    var visibleRows: Int { max(1, Int(floor(panes[0].bounds.height / metrics.lineH))) }
    private var maxTop: Int { max(0, doc.diff.rows.count - visibleRows + 1) }
    private var maxHOffset: CGFloat { max(0, maxLineWidth + metrics.charW * 8 - panes[0].textWidth) }

    private func clampScroll() {
        topRow = min(max(0, topRow), maxTop)
        hOffset = min(max(0, hOffset), maxHOffset)
    }

    private func updateScrollers() {
        let rows = CGFloat(max(1, doc.diff.rows.count))
        vScroller.proportion = CGFloat(visibleRows) / (rows + 1)
        vScroller.value = maxTop > 0 ? CGFloat(topRow) / CGFloat(maxTop) : 0
        for h in hScrollers {
            h.proportion = panes[0].textWidth / max(1, maxLineWidth + metrics.charW * 8)
            h.value = maxHOffset > 0 ? hOffset / maxHOffset : 0
        }
    }

    private func redraw() {
        panes.forEach { $0.needsDisplay = true }
        location.needsDisplay = true
        detail.needsDisplay = true
        updateScrollers()
    }

    func scrollTo(top: Int) {
        topRow = top
        clampScroll()
        redraw()
    }

    private func setHOffset(_ v: CGFloat) {
        hOffset = v
        clampScroll()
        redraw()
    }

    func handleWheel(_ event: NSEvent) {
        var dy = event.scrollingDeltaY, dx = event.scrollingDeltaX
        if !event.hasPreciseScrollingDeltas { dy *= metrics.lineH * 3; dx *= metrics.charW * 6 }
        if event.modifierFlags.contains(.shift) && dx == 0 { dx = dy; dy = 0 }
        wheelRemainder -= dy
        let rows = Int(wheelRemainder / metrics.lineH)
        if rows != 0 {
            wheelRemainder -= CGFloat(rows) * metrics.lineH
            topRow += rows
        }
        hOffset -= dx
        clampScroll()
        redraw()
    }

    // MARK: Текст и рисование строк

    private func invalidateCaches() {
        lineCache = [[:], [:]]
        inlineCache = [:]
        syntaxStates = [nil, nil]
    }

    func row(of line: Int, side: Int) -> Int {
        let map = side == 0 ? doc.diff.leftRow : doc.diff.rightRow
        return line < map.count ? map[line] : max(0, doc.diff.rows.count - 1)
    }

    private func line(atRow row: Int, side: Int) -> Int? {
        guard row >= 0, row < doc.diff.rows.count else { return nil }
        return side == 0 ? doc.diff.rows[row].left : doc.diff.rows[row].right
    }

    /// Ближайшая настоящая строка к строке экрана: сама, выше, затем ниже.
    private func nearestLine(row: Int, side: Int, preferDown: Bool = false) -> Int {
        let n = doc.diff.rows.count
        let r = min(max(row, 0), n - 1)
        let up = stride(from: r, through: 0, by: -1).lazy.compactMap { self.line(atRow: $0, side: side) }.first
        let down = (r..<n).lazy.compactMap { self.line(atRow: $0, side: side) }.first
        return (preferDown ? (down ?? up) : (up ?? down)) ?? 0
    }

    private func ctLine(side: Int, line: Int) -> CTLine {
        if let hit = lineCache[side][line] { return hit }
        let text = doc.sides[side].lines[line].text
        let s = NSMutableAttributedString(string: text, attributes: [
            .font: metrics.font, .foregroundColor: Theme.text, .paragraphStyle: metrics.paragraph,
        ])
        if let language = languages[side], (text as NSString).length < 3000 {
            if syntaxStates[side] == nil { syntaxStates[side] = language.lineStates(doc.sides[side].lines) }
            var state = syntaxStates[side]![line]
            for (range, kind) in language.highlight(text as NSString, state: &state) {
                s.addAttribute(.foregroundColor, value: kind.color, range: range)
                if kind == .keyword { s.addAttribute(.font, value: metrics.bold, range: range) }
            }
        }
        let ct = CTLineCreateWithAttributedString(s)
        lineCache[side][line] = ct
        return ct
    }

    func x(side: Int, pos: TextPos) -> CGFloat {
        CTLineGetOffsetForStringIndex(ctLine(side: side, line: pos.line), pos.col, nil)
    }

    private func col(side: Int, line: Int, x: CGFloat) -> Int {
        let length = (doc.sides[side].lines[line].text as NSString).length
        if x <= 0 { return 0 }
        let index = CTLineGetStringIndexForPosition(ctLine(side: side, line: line), CGPoint(x: x, y: 0))
        return index == kCFNotFound ? length : min(max(index, 0), length)
    }

    private func inlineRanges(row: Int) -> (a: [NSRange], b: [NSRange]) {
        if let hit = inlineCache[row] { return hit }
        let r = doc.diff.rows[row]
        var value: (a: [NSRange], b: [NSRange]) = ([], [])
        if let l = r.left, let rr = r.right {
            value = InlineDiff.compute(doc.sides[0].lines[l].text, doc.sides[1].lines[rr].text,
                                       options: doc.options, wordLevel: ViewFlag.wordLevel.isOn)
        }
        inlineCache[row] = value
        return value
    }

    var hasSelection: Bool { anchor != nil && anchor != caret }

    private var selection: (from: TextPos, to: TextPos)? {
        guard let anchor, anchor != caret else { return nil }
        return anchor < caret ? (anchor, caret) : (caret, anchor)
    }

    /// Рисует строку экрана `rowIndex` стороны `side`; текст начинается в `textX`.
    func drawRow(_ rowIndex: Int, side: Int, y: CGFloat, textX: CGFloat, clip: NSRect, selection showSelection: Bool) {
        let row = doc.diff.rows[rowIndex]
        let line = side == 0 ? row.left : row.right
        let rect = NSRect(x: clip.minX, y: y, width: clip.width, height: metrics.lineH)
        var selected = false, trivial = false
        if row.block >= 0 {
            trivial = doc.diff.blocks[row.block].trivial
            selected = row.block == doc.currentBlock
            let color: NSColor
            if trivial { color = line != nil ? Theme.trivial : Theme.trivialDeleted } else if selected {
                color = line != nil ? Theme.selDiff : Theme.selDiffDeleted
            } else { color = line != nil ? Theme.diff : Theme.diffDeleted }
            color.setFill()
            rect.fill()
        }
        guard let line else { return }
        let ct = ctLine(side: side, line: line)
        let length = (doc.sides[side].lines[line].text as NSString).length
        func offset(_ index: Int) -> CGFloat { CTLineGetOffsetForStringIndex(ct, min(index, length), nil) }

        if row.block >= 0, !trivial, ViewFlag.lineDiff.isOn, row.left != nil, row.right != nil {
            let ranges = side == 0 ? inlineRanges(row: rowIndex).a : inlineRanges(row: rowIndex).b
            (selected ? Theme.selDiffWord : Theme.diffWord).setFill()
            for r in ranges where r.length > 0 {
                let x0 = offset(r.location), x1 = offset(NSMaxRange(r))
                NSRect(x: textX + x0, y: y, width: x1 - x0, height: metrics.lineH).fill()
            }
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        func drawText(white: Bool) {
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: textX, y: y + metrics.ascent)
            if white {
                let s = NSAttributedString(string: doc.sides[side].lines[line].text, attributes: [
                    .font: metrics.font, .foregroundColor: NSColor.white, .paragraphStyle: metrics.paragraph,
                ])
                CTLineDraw(CTLineCreateWithAttributedString(s), context)
            } else {
                CTLineDraw(ct, context)
            }
        }
        drawText(white: false)

        if ViewFlag.whitespace.isOn, length < 2000 {
            let s = doc.sides[side].lines[line].text as NSString
            Theme.whitespace.setFill()
            Theme.whitespace.setStroke()
            for i in 0..<length {
                let c = s.character(at: i)
                if c == 32 {
                    let cx = textX + offset(i) + metrics.charW / 2
                    NSRect(x: cx - 0.75, y: y + metrics.lineH / 2 - 0.75, width: 1.5, height: 1.5).fill()
                } else if c == 9 {
                    let x0 = textX + offset(i) + 1, x1 = textX + offset(i + 1) - 2, cy = y + metrics.lineH / 2
                    let p = NSBezierPath()
                    p.move(to: NSPoint(x: x0, y: cy)); p.line(to: NSPoint(x: x1, y: cy))
                    p.move(to: NSPoint(x: x1 - 3, y: cy - 2.5)); p.line(to: NSPoint(x: x1, y: cy)); p.line(to: NSPoint(x: x1 - 3, y: cy + 2.5))
                    p.lineWidth = 0.8
                    p.stroke()
                }
            }
        }

        if showSelection, side == active, let sel = selection, line >= sel.from.line, line <= sel.to.line {
            let from = line == sel.from.line ? sel.from.col : 0
            let x0 = offset(from)
            var x1 = line == sel.to.line ? offset(sel.to.col) : offset(length) + metrics.charW
            if x1 <= x0 && line != sel.to.line { x1 = x0 + metrics.charW }
            guard x1 > x0 else { return }
            let r = NSRect(x: textX + x0, y: y, width: x1 - x0, height: metrics.lineH)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r).addClip()
            Theme.selection.setFill()
            r.fill()
            drawText(white: true)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: Изменение и обновление вида

    /// После любой правки или пересравнения: кэши, прокрутка, заголовки, строки состояния.
    private func didChange(keepCaretVisible: Bool = true) {
        invalidateCaches()
        var longest = 0
        for file in doc.sides {
            for line in file.lines {
                let n = line.text.utf16.count
                if n > longest { longest = n }
            }
        }
        maxLineWidth = CGFloat(longest) * metrics.charW * 1.15
        caret = doc.clamp(caret, side: active)
        if let a = anchor { anchor = doc.clamp(a, side: active) }
        clampScroll()
        if keepCaretVisible { revealCaret() }
        updateChrome()
        redraw()
    }

    private func updateChrome() {
        for side in 0..<2 {
            let file = doc.sides[side]
            let title = file.title ?? file.path.map { $0 } ?? (side == 0 ? "Untitled Left" : "Untitled Right")
            headers[side].text = (file.modified ? "* " : "") + title
            headers[side].active = side == active
            statuses[side].encoding = file.encodingName
            statuses[side].eol = file.eolName
            statuses[side].readOnly = file.readOnly
            statuses[side].position = side == active ? positionText() : statuses[side].position
            if statuses[side].position.isEmpty { statuses[side].position = "Ln: 1  Col: 1/1  Ch: 1/1" }
        }
        MainWindowController.shared.refreshChrome()
    }

    private func positionText() -> String {
        let text = doc.sides[active].lines[caret.line].text as NSString
        let tab = Theme.tabSize
        func column(_ upTo: Int) -> Int {
            var c = 0
            for i in 0..<min(upTo, text.length) { c += text.character(at: i) == 9 ? tab - c % tab : 1 }
            return c
        }
        var s = "Ln: \(caret.line + 1)  Col: \(column(caret.col) + 1)/\(column(text.length) + 1)  Ch: \(caret.col + 1)/\(text.length + 1)"
        if let sel = selection {
            s += "  Sel: \(sel.to.line - sel.from.line + 1) | \((doc.text(side: active, from: sel.from, to: sel.to) as NSString).length)"
        }
        return s
    }

    private func revealCaret() {
        let row = row(of: caret.line, side: active)
        let visible = visibleRows
        if row < topRow { topRow = row } else if row >= topRow + visible - 1 { topRow = row - visible + 2 }
        let cx = x(side: active, pos: caret)
        let width = panes[active].textWidth
        if cx < hOffset { hOffset = max(0, cx - metrics.charW * 8) } else if cx > hOffset + width - metrics.charW * 2 {
            hOffset = cx - width + metrics.charW * 8
        }
        clampScroll()
    }

    private func caretMoved() {
        caretOn = true
        revealCaret()
        updateChrome()
        redraw()
    }

    func activate(side: Int) {
        guard side != active else { headers[side].active = true; return }
        let row = row(of: caret.line, side: active)
        active = side
        anchor = nil
        caret = doc.clamp(TextPos(line: nearestLine(row: row, side: side), col: caret.col), side: side)
        updateChrome()
        redraw()
    }

    private func focus(side: Int) {
        window?.makeFirstResponder(panes[side])
    }

    // MARK: Мышь

    func mouseDown(side: Int, row: Int, x: CGFloat, clicks: Int, shift: Bool, gutter: Bool) {
        if side != active { activate(side: side) }
        let line = nearestLine(row: row, side: side)
        let pos = TextPos(line: line, col: gutter ? 0 : col(side: side, line: line, x: x))
        desiredX = nil
        if gutter || clicks >= 3 {
            anchor = TextPos(line: line, col: 0)
            caret = line + 1 < doc.sides[side].lines.count ? TextPos(line: line + 1, col: 0)
                : TextPos(line: line, col: (doc.sides[side].lines[line].text as NSString).length)
        } else if clicks == 2 {
            // Двойной щелчок внутри отличия выбирает его; вне отличий — слово.
            if let block = doc.block(atRow: min(max(row, 0), doc.diff.rows.count - 1)) {
                caret = pos
                anchor = nil
                doc.currentBlock = block
            } else {
                let range = wordRange(side: side, pos: pos)
                anchor = TextPos(line: line, col: range.location)
                caret = TextPos(line: line, col: NSMaxRange(range))
            }
        } else {
            if shift { if anchor == nil { anchor = caret } } else { anchor = pos }
            caret = pos
            dragging = true
        }
        caretMoved()
    }

    func mouseDragged(side: Int, row: Int, x: CGFloat) {
        guard dragging, side == active else { return }
        let line = nearestLine(row: min(max(row, 0), doc.diff.rows.count - 1), side: side)
        caret = TextPos(line: line, col: col(side: side, line: line, x: x))
        caretMoved()
    }

    func mouseUp() {
        dragging = false
        if anchor == caret { anchor = nil }
    }

    private func wordRange(side: Int, pos: TextPos) -> NSRange {
        let s = doc.sides[side].lines[pos.line].text as NSString
        guard s.length > 0 else { return NSRange(location: 0, length: 0) }
        func isWord(_ c: unichar) -> Bool {
            guard let u = Unicode.Scalar(c) else { return true }
            return CharacterSet.alphanumerics.contains(u) || c == 95
        }
        let i = min(pos.col, s.length - 1)
        guard isWord(s.character(at: i)) else { return NSRange(location: i, length: 1) }
        var a = i, b = i + 1
        while a > 0, isWord(s.character(at: a - 1)) { a -= 1 }
        while b < s.length, isWord(s.character(at: b)) { b += 1 }
        return NSRange(location: a, length: b - a)
    }

    // MARK: Клавиатура

    private enum Move { case left, right, up, down, wordLeft, wordRight, lineStart, lineEnd, docStart, docEnd, pageUp, pageDown }

    private func move(_ m: Move, select: Bool) {
        if select { if anchor == nil { anchor = caret } } else if let sel = selection, m == .left || m == .right {
            // Без Shift стрелка снимает выделение и ставит курсор на его край.
            caret = m == .left ? sel.from : sel.to
            anchor = nil
            desiredX = nil
            caretMoved()
            return
        } else { anchor = nil }
        let lines = doc.sides[active].lines
        let text = lines[caret.line].text as NSString
        var vertical = false
        switch m {
        case .left:
            if caret.col > 0 { caret.col = text.rangeOfComposedCharacterSequence(at: caret.col - 1).location } else if caret.line > 0 {
                caret = TextPos(line: caret.line - 1, col: (lines[caret.line - 1].text as NSString).length)
            }
        case .right:
            if caret.col < text.length { caret.col = NSMaxRange(text.rangeOfComposedCharacterSequence(at: caret.col)) } else if caret.line + 1 < lines.count {
                caret = TextPos(line: caret.line + 1, col: 0)
            }
        case .wordLeft:
            if caret.col == 0 { if caret.line > 0 { caret = TextPos(line: caret.line - 1, col: (lines[caret.line - 1].text as NSString).length) } } else {
                var i = caret.col
                while i > 0, text.character(at: i - 1) == 32 || text.character(at: i - 1) == 9 { i -= 1 }
                if i > 0 { i = wordRange(side: active, pos: TextPos(line: caret.line, col: i - 1)).location }
                caret.col = i
            }
        case .wordRight:
            if caret.col >= text.length { if caret.line + 1 < lines.count { caret = TextPos(line: caret.line + 1, col: 0) } } else {
                var i = NSMaxRange(wordRange(side: active, pos: caret))
                while i < text.length, text.character(at: i) == 32 || text.character(at: i) == 9 { i += 1 }
                caret.col = i
            }
        case .lineStart:
            var indent = 0
            while indent < text.length, text.character(at: indent) == 32 || text.character(at: indent) == 9 { indent += 1 }
            caret.col = caret.col == indent ? 0 : indent
        case .lineEnd: caret.col = text.length
        case .docStart: caret = TextPos(line: 0, col: 0)
        case .docEnd: caret = TextPos(line: lines.count - 1, col: (lines[lines.count - 1].text as NSString).length)
        case .up, .down, .pageUp, .pageDown:
            vertical = true
            let step = m == .up ? -1 : m == .down ? 1 : (m == .pageUp ? -1 : 1) * max(1, visibleRows - 1)
            let from = row(of: caret.line, side: active)
            let x = desiredX ?? self.x(side: active, pos: caret)
            desiredX = x
            var target = min(max(from + step, 0), doc.diff.rows.count - 1)
            // Через «призрачные» строки курсор перешагивает.
            while line(atRow: target, side: active) == nil, target + step.signum() >= 0, target + step.signum() < doc.diff.rows.count { target += step.signum() }
            if let l = line(atRow: target, side: active) { caret = TextPos(line: l, col: col(side: active, line: l, x: x)) }
            if m == .pageUp || m == .pageDown { topRow += step }
        }
        if !vertical { desiredX = nil }
        if anchor == caret && !select { anchor = nil }
        caretMoved()
    }

    /// Возвращает true, если клавиша обработана; иначе это набор текста.
    func keyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let shift = flags.contains(.shift), cmd = flags.contains(.command), ctrl = flags.contains(.control)
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return true }
        switch Int(scalar.value) {
        case NSLeftArrowFunctionKey: move(cmd ? .lineStart : ctrl ? .wordLeft : .left, select: shift)
        case NSRightArrowFunctionKey: move(cmd ? .lineEnd : ctrl ? .wordRight : .right, select: shift)
        case NSUpArrowFunctionKey: move(cmd ? .docStart : .up, select: shift)
        case NSDownArrowFunctionKey: move(cmd ? .docEnd : .down, select: shift)
        case NSHomeFunctionKey: move(ctrl || cmd ? .docStart : .lineStart, select: shift)
        case NSEndFunctionKey: move(ctrl || cmd ? .docEnd : .lineEnd, select: shift)
        case NSPageUpFunctionKey: move(.pageUp, select: shift)
        case NSPageDownFunctionKey: move(.pageDown, select: shift)
        case 127, 8: deleteBackward()
        case NSDeleteFunctionKey: deleteForward()
        case 13, 3: newline()
        case 9: if !shift { type("\t") }
        case 27: MainWindowController.shared.run(.close)
        default:
            if cmd || ctrl { return true }
            return false
        }
        return true
    }

    private var editable: Bool {
        if doc.sides[active].readOnly { NSSound.beep(); return false }
        return true
    }

    private func replaceSelection(with string: String, typing: Bool = false) {
        guard editable else { return }
        doc.beginChange(side: active, caret: caret, typing: typing)
        let range = selection ?? (caret, caret)
        caret = doc.replace(side: active, from: range.from, to: range.to, with: string)
        anchor = nil
        desiredX = nil
        doc.currentBlock = -1
        didChange()
    }

    func type(_ string: String) {
        replaceSelection(with: string, typing: true)
    }

    private func newline() {
        // Новая строка наследует отступ текущей.
        let text = doc.sides[active].lines[caret.line].text as NSString
        var indent = 0
        while indent < min(text.length, caret.col), text.character(at: indent) == 32 || text.character(at: indent) == 9 { indent += 1 }
        replaceSelection(with: "\n" + text.substring(to: indent))
    }

    private func deleteBackward() {
        if selection == nil {
            guard caret != TextPos(line: 0, col: 0) else { return }
            let end = caret
            move(.left, select: false)
            anchor = end
        }
        replaceSelection(with: "", typing: true)
    }

    private func deleteForward() {
        if selection == nil {
            let start = caret
            move(.right, select: false)
            guard caret != start else { return }
            anchor = start
        }
        replaceSelection(with: "")
    }

    private func copySelection() {
        guard let sel = selection else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(doc.text(side: active, from: sel.from, to: sel.to), forType: .string)
    }

    // MARK: Отличия

    private var caretRow: Int { row(of: caret.line, side: active) }

    private func select(block index: Int) {
        doc.currentBlock = index
        let block = doc.diff.blocks[index]
        anchor = nil
        desiredX = nil
        caret = TextPos(line: nearestLine(row: block.rowStart, side: active, preferDown: true), col: 0)
        // Отличие ставится с запасом строк над ним, как в WinMerge.
        let visible = visibleRows
        if block.rowStart < topRow + 1 || block.rowStart + block.rowCount > topRow + visible - 1 {
            topRow = block.rowStart - min(5, visible / 3)
        }
        hOffset = 0
        clampScroll()
        caretOn = true
        updateChrome()
        redraw()
    }

    private var nextTarget: Int? {
        let here = caretRow
        if let b = doc.block(atRow: here), b != doc.currentBlock { return b }
        let from = doc.block(atRow: here).map { doc.diff.blocks[$0].rowStart + doc.diff.blocks[$0].rowCount - 1 } ?? here
        return doc.nextBlock(afterRow: from)
    }

    private var previousTarget: Int? {
        let here = caretRow
        let from = doc.block(atRow: here).map { doc.diff.blocks[$0].rowStart } ?? here
        return doc.previousBlock(beforeRow: from)
    }

    /// Отличие, к которому относятся команды копирования: выбранное или то, в котором стоит курсор.
    private var mergeTarget: Int? {
        if doc.currentBlock >= 0 { return doc.currentBlock }
        return doc.block(atRow: caretRow)
    }

    private func copy(from: Int, advance: Bool) {
        guard let index = mergeTarget else { return }
        if doc.sides[1 - from].readOnly { NSSound.beep(); return }
        let rowStart = doc.diff.blocks[index].rowStart
        doc.copyBlock(index, from: from, caret: caret)
        anchor = nil
        didChange(keepCaretVisible: false)
        if advance, let next = doc.diff.significant.first(where: { doc.diff.blocks[$0].rowStart >= rowStart }) {
            select(block: next)
        } else {
            caret = doc.clamp(caret, side: active)
            updateChrome()
        }
    }

    private func selectLineDifference() {
        let rowIndex = caretRow
        guard doc.diff.rows[rowIndex].block >= 0 else { return }
        let ranges = active == 0 ? inlineRanges(row: rowIndex).a : inlineRanges(row: rowIndex).b
        guard !ranges.isEmpty else { return }
        let current = selection?.from.col ?? -1
        let next = ranges.first { $0.location > current } ?? ranges[0]
        anchor = TextPos(line: caret.line, col: next.location)
        caret = TextPos(line: caret.line, col: NSMaxRange(next))
        caretMoved()
    }

    // MARK: Файлы

    private func save(side: Int, ask: Bool = false) -> Bool {
        let file = doc.sides[side]
        var target = file.path
        if ask || target == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.path.map { ($0 as NSString).lastPathComponent } ?? "Untitled.txt"
            if let path = file.path { panel.directoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent) }
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url.path
        }
        do {
            try file.save(to: target!)
        } catch {
            UI.alert("Saving file failed.", info: error.localizedDescription, style: .warning)
            return false
        }
        languages[side] = Language.forPath(file.path) ?? languages[side]
        didChange(keepCaretVisible: false)
        return true
    }

    func canClose() -> Bool {
        let modified = (0..<2).filter { doc.sides[$0].modified }
        guard !modified.isEmpty, !Snapshot.active else { return true }
        // Как в WinMerge: по каждой изменённой стороне — сохранить или отбросить.
        let alert = NSAlert()
        alert.messageText = "Save modified files?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard All")
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 4
        var radios: [Int: NSButton] = [:]
        for side in modified {
            box.addArrangedSubview(UI.label(side == 0 ? "Left side file" : "Right side file", bold: true))
            box.addArrangedSubview(UI.label(UI.short(doc.sides[side].path ?? name(side)), size: 11))
            let group = SaveChoice()
            box.addArrangedSubview(group)
            radios[side] = group.save
        }
        box.frame = NSRect(origin: .zero, size: box.fittingSize)
        alert.accessoryView = box
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for side in modified where radios[side]?.state == .on {
                if !save(side: side) { return false }
            }
            return true
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func reload() {
        if doc.sides.contains(where: { $0.modified }),
           UI.alert("Changes will be lost. Reload the files?", buttons: ["Yes", "No"], style: .warning) != 0 { return }
        var files: [TextFile] = []
        for side in 0..<2 {
            guard let path = doc.sides[side].path, let file = try? TextFile.load(path) else { files.append(doc.sides[side]); continue }
            file.readOnly = doc.sides[side].readOnly
            files.append(file)
        }
        doc = CompareDocument(left: files[0], right: files[1])
        anchor = nil
        didChange(keepCaretVisible: false)
    }

    private func swap() {
        doc = CompareDocument(left: doc.sides[1], right: doc.sides[0])
        languages.swapAt(0, 1)
        anchor = nil
        didChange(keepCaretVisible: false)
    }

    private func convertEOL(_ eol: String) {
        guard editable else { return }
        doc.beginChange(side: active, caret: caret)
        let file = doc.sides[active]
        for i in 0..<(file.lines.count - 1) { file.lines[i].eol = eol }
        file.modified = true
        doc.rescan()
        didChange()
    }

    private func generatePatch() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "changes.patch"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try doc.unifiedPatch().write(to: url, atomically: true, encoding: .utf8) } catch {
            UI.alert("Could not write to file.", info: error.localizedDescription, style: .warning)
        }
    }

    // MARK: Поиск и переход

    /// Ищет от курсора; `replace` — заменить найденное выделение перед поиском следующего.
    @discardableResult
    func find(_ query: FindQuery, backward: Bool = false) -> Bool {
        guard let regex = query.regex else { NSSound.beep(); return false }
        let lines = doc.sides[active].lines
        let n = lines.count
        let start = backward ? (selection?.from ?? caret) : (selection?.to ?? caret)
        for step in 0...n {
            let index = backward ? (start.line - step + n * 2) % n : (start.line + step) % n
            if step > 0, !query.wrap, backward ? index > start.line : index < start.line { break }
            let s = lines[index].text as NSString
            let matches = regex.matches(in: lines[index].text, range: NSRange(location: 0, length: s.length)).filter { $0.range.length > 0 }
            let hit: NSTextCheckingResult?
            if step == 0 {
                hit = backward ? matches.last { NSMaxRange($0.range) <= start.col } : matches.first { $0.range.location >= start.col }
            } else if step == n {
                hit = backward ? matches.last { $0.range.location >= start.col } : matches.first { $0.range.location < start.col }
            } else {
                hit = backward ? matches.last : matches.first
            }
            if let hit {
                anchor = TextPos(line: index, col: hit.range.location)
                caret = TextPos(line: index, col: NSMaxRange(hit.range))
                desiredX = nil
                caretMoved()
                return true
            }
        }
        NSSound.beep()
        return false
    }

    func replaceCurrent(_ query: FindQuery) {
        guard let sel = selection, sel.from.line == sel.to.line, let regex = query.regex else { find(query); return }
        let text = doc.text(side: active, from: sel.from, to: sel.to)
        let whole = NSRange(location: 0, length: (text as NSString).length)
        if let m = regex.firstMatch(in: text, range: whole), m.range == whole {
            replaceSelection(with: regex.stringByReplacingMatches(in: text, range: whole, withTemplate: query.template))
        }
        find(query)
    }

    func replaceAll(_ query: FindQuery) -> Int {
        guard editable, let regex = query.regex else { return 0 }
        let file = doc.sides[active]
        var count = 0
        var began = false
        for i in 0..<file.lines.count {
            let text = file.lines[i].text
            let range = NSRange(location: 0, length: (text as NSString).length)
            let hits = regex.numberOfMatches(in: text, range: range)
            guard hits > 0 else { continue }
            if !began { doc.beginChange(side: active, caret: caret); began = true }
            file.lines[i].text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: query.template)
            count += hits
        }
        if began {
            file.modified = true
            doc.rescan()
            anchor = nil
            didChange()
        }
        return count
    }

    func goTo(line: Int, side: Int) {
        if side != active { focus(side: side); activate(side: side) }
        anchor = nil
        caret = doc.clamp(TextPos(line: line - 1, col: 0), side: active)
        topRow = row(of: caret.line, side: active) - visibleRows / 3
        caretMoved()
    }

    func goTo(difference: Int) {
        guard difference >= 1, difference <= doc.significantCount else { NSSound.beep(); return }
        select(block: doc.diff.significant[difference - 1])
    }

    var activeSide: Int { active }
    var caretLine: Int { caret.line + 1 }
    func lineCount(side: Int) -> Int { doc.sides[side].lines.count }

    // MARK: Меню

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ cmd: Cmd) {
            let item = NSMenuItem(title: title, action: #selector(MainWindowController.menuCommand(_:)), keyEquivalent: "")
            item.target = MainWindowController.shared
            item.tag = cmd.rawValue
            menu.addItem(item)
        }
        add("Copy to Right", .copyRight)
        add("Copy to Left", .copyLeft)
        menu.addItem(.separator())
        add("Select Line Difference", .selectLineDiff)
        menu.addItem(.separator())
        add("Undo", .undo)
        add("Redo", .redo)
        menu.addItem(.separator())
        add("Cut", .cut)
        add("Copy", .copy)
        add("Paste", .paste)
        menu.addItem(.separator())
        add("Go to...", .goTo)
        return menu
    }

    private func headerMenu(side: Int, event: NSEvent) {
        focus(side: side)
        let menu = NSMenu()
        let path = doc.sides[side].path
        let copy = NSMenuItem(title: "Copy Full Path", action: #selector(copyPath(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = path
        copy.isEnabled = path != nil
        let nameItem = NSMenuItem(title: "Copy Filename", action: #selector(copyPath(_:)), keyEquivalent: "")
        nameItem.target = self
        nameItem.representedObject = path.map { ($0 as NSString).lastPathComponent }
        menu.addItem(copy)
        menu.addItem(nameItem)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open...", action: #selector(MainWindowController.menuCommand(_:)), keyEquivalent: "")
        open.target = MainWindowController.shared
        open.tag = Cmd.open.rawValue
        menu.addItem(open)
        let save = NSMenuItem(title: "Save", action: #selector(MainWindowController.menuCommand(_:)), keyEquivalent: "")
        save.target = MainWindowController.shared
        save.tag = (side == 0 ? Cmd.saveLeft : Cmd.saveRight).rawValue
        menu.addItem(save)
        NSMenu.popUpContextMenu(menu, with: event, for: headers[side])
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func isEnabled(_ cmd: Cmd) -> Bool {
        switch cmd {
        case .save: return doc.sides.contains { $0.modified }
        case .saveLeft: return doc.sides[0].modified
        case .saveRight: return doc.sides[1].modified
        case .undo: return doc.canUndo
        case .redo: return doc.canRedo
        case .cut: return hasSelection && !doc.sides[active].readOnly
        case .copy: return hasSelection
        case .paste, .eolWin, .eolUnix, .eolMac: return !doc.sides[active].readOnly
        case .selectLineDiff: return doc.diff.rows.isEmpty ? false : doc.diff.rows[caretRow].block >= 0
        case .nextDiff: return nextTarget != nil
        case .prevDiff: return previousTarget != nil
        case .firstDiff: return doc.significantCount > 0 && doc.currentBlock != doc.diff.significant.first
        case .lastDiff: return doc.significantCount > 0 && doc.currentBlock != doc.diff.significant.last
        case .currentDiff: return mergeTarget != nil
        case .copyRight, .copyRightAdvance: return mergeTarget != nil && !doc.sides[1].readOnly
        case .copyLeft, .copyLeftAdvance: return mergeTarget != nil && !doc.sides[0].readOnly
        case .allRight: return doc.significantCount > 0 && !doc.sides[1].readOnly
        case .allLeft: return doc.significantCount > 0 && !doc.sides[0].readOnly
        case .reload: return doc.sides.contains { $0.path != nil }
        case .saveLeftAs, .saveRightAs, .leftReadOnly, .rightReadOnly, .selectAll, .find, .findNext, .findPrev, .replace, .goTo,
             .refresh, .swapPanes, .generatePatch, .changePane, .zoomIn, .zoomOut, .zoomNormal,
             .viewWhitespace, .viewLineDiff, .viewLineNumbers, .viewMargins, .diffPane, .locationPane:
            return true
        default: return false
        }
    }

    func isChecked(_ cmd: Cmd) -> Bool {
        switch cmd {
        case .leftReadOnly: return doc.sides[0].readOnly
        case .rightReadOnly: return doc.sides[1].readOnly
        default: return false
        }
    }

    func perform(_ cmd: Cmd) {
        switch cmd {
        case .save:
            for side in 0..<2 where doc.sides[side].modified { if !save(side: side) { break } }
        case .saveLeft: _ = save(side: 0)
        case .saveRight: _ = save(side: 1)
        case .saveLeftAs: _ = save(side: 0, ask: true)
        case .saveRightAs: _ = save(side: 1, ask: true)
        case .leftReadOnly: doc.sides[0].readOnly.toggle(); updateChrome()
        case .rightReadOnly: doc.sides[1].readOnly.toggle(); updateChrome()
        case .eolWin: convertEOL("\r\n")
        case .eolUnix: convertEOL("\n")
        case .eolMac: convertEOL("\r")
        case .reload: reload()
        case .undo:
            if let r = doc.undo(side: active, caret: caret) { restoreCaret(r) }
        case .redo:
            if let r = doc.redo(side: active, caret: caret) { restoreCaret(r) }
        case .cut: copySelection(); replaceSelection(with: "")
        case .copy: copySelection()
        case .paste:
            if let s = NSPasteboard.general.string(forType: .string) { replaceSelection(with: s) }
        case .selectAll:
            anchor = TextPos(line: 0, col: 0)
            let last = doc.sides[active].lines.count - 1
            caret = TextPos(line: last, col: (doc.sides[active].lines[last].text as NSString).length)
            updateChrome(); redraw()
        case .selectLineDiff: selectLineDifference()
        case .find: FindDialog.show(for: self, replace: false)
        case .replace: FindDialog.show(for: self, replace: true)
        case .findNext:
            if FindQuery.last.pattern.isEmpty { FindDialog.show(for: self, replace: false) } else { find(FindQuery.last) }
        case .findPrev:
            if FindQuery.last.pattern.isEmpty { FindDialog.show(for: self, replace: false) } else { find(FindQuery.last, backward: true) }
        case .goTo: GoToDialog.show(for: self)
        case .refresh: doc.rescan(); didChange(keepCaretVisible: false)
        case .swapPanes: swap()
        case .generatePatch: generatePatch()
        case .changePane: focus(side: 1 - active)
        case .nextDiff: if let b = nextTarget { select(block: b) }
        case .prevDiff: if let b = previousTarget { select(block: b) }
        case .firstDiff: if let b = doc.diff.significant.first { select(block: b) }
        case .lastDiff: if let b = doc.diff.significant.last { select(block: b) }
        case .currentDiff: if let b = mergeTarget { select(block: b) }
        case .copyRight: copy(from: 0, advance: false)
        case .copyLeft: copy(from: 1, advance: false)
        case .copyRightAdvance: copy(from: 0, advance: true)
        case .copyLeftAdvance: copy(from: 1, advance: true)
        case .allRight: doc.copyAll(from: 0, caret: caret); anchor = nil; didChange(keepCaretVisible: false)
        case .allLeft: doc.copyAll(from: 1, caret: caret); anchor = nil; didChange(keepCaretVisible: false)
        default: break
        }
    }

    private func restoreCaret(_ r: (side: Int, caret: TextPos)) {
        if r.side != active { focus(side: r.side); active = r.side }
        anchor = nil
        caret = doc.clamp(r.caret, side: active)
        didChange()
    }
}

/// Пара переключателей «сохранить / отбросить» в запросе при закрытии.
private final class SaveChoice: NSView {
    let save = NSButton(radioButtonWithTitle: "Save changes", target: nil, action: nil)
    let discard = NSButton(radioButtonWithTitle: "Discard changes", target: nil, action: nil)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        save.state = .on
        for (i, b) in [save, discard].enumerated() {
            b.target = self
            b.action = #selector(pick(_:))
            b.frame = NSRect(x: 12 + i * 130, y: 2, width: 130, height: 18)
            addSubview(b)
        }
        widthAnchor.constraint(equalToConstant: 300).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func pick(_ sender: NSButton) {
        save.state = sender === save ? .on : .off
        discard.state = sender === discard ? .on : .off
    }
}
