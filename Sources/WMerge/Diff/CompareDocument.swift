import Foundation

/// Место в тексте: номер строки и смещение в ней в единицах UTF-16.
struct TextPos: Equatable, Comparable {
    var line: Int
    var col: Int
    static func < (a: TextPos, b: TextPos) -> Bool { a.line != b.line ? a.line < b.line : a.col < b.col }
}

/// Пара сравниваемых текстов: отличия, слияние, правка и отмена.
final class CompareDocument {
    let sides: [TextFile]
    var options = CompareOptions.current
    private(set) var diff = DiffResult()
    /// Выбранное отличие (номер в `diff.blocks`) или -1.
    var currentBlock = -1

    struct Snapshot {
        var lines: [[TextLine]]
        var modified: [Bool]
        var side: Int
        var caret: TextPos
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// Набор текста подряд сливается в один шаг отмены.
    private var lastTyping: (side: Int, time: Date)?

    init(left: TextFile, right: TextFile) {
        sides = [left, right]
        rescan()
    }

    func rescan() {
        options = CompareOptions.current
        diff = DiffResult.compute(sides[0].lines, sides[1].lines, options: options)
        if currentBlock >= diff.blocks.count { currentBlock = -1 }
    }

    // MARK: Навигация

    var significantCount: Int { diff.significant.count }

    /// Порядковый номер выбранного отличия среди значимых (с нуля) или nil.
    var currentOrdinal: Int? { diff.significant.firstIndex(of: currentBlock) }

    func block(atRow row: Int) -> Int? {
        guard row >= 0, row < diff.rows.count else { return nil }
        let b = diff.rows[row].block
        return b >= 0 && !diff.blocks[b].trivial ? b : nil
    }

    /// Следующее значимое отличие после строки экрана `row` (или перед ней).
    func nextBlock(afterRow row: Int) -> Int? {
        diff.significant.first { diff.blocks[$0].rowStart > row }
    }

    func previousBlock(beforeRow row: Int) -> Int? {
        diff.significant.last { diff.blocks[$0].rowStart + diff.blocks[$0].rowCount - 1 < row }
    }

    // MARK: Отмена

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot(side: Int, caret: TextPos) -> Snapshot {
        Snapshot(lines: sides.map { $0.lines }, modified: sides.map { $0.modified }, side: side, caret: caret)
    }

    func beginChange(side: Int, caret: TextPos, typing: Bool = false) {
        if typing, let last = lastTyping, last.side == side, Date().timeIntervalSince(last.time) < 1.2, !undoStack.isEmpty {
            lastTyping = (side, Date())
            return
        }
        lastTyping = typing ? (side, Date()) : nil
        undoStack.append(snapshot(side: side, caret: caret))
        if undoStack.count > 400 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ s: Snapshot) {
        for i in 0..<sides.count {
            sides[i].lines = s.lines[i]
            sides[i].modified = s.modified[i]
        }
        currentBlock = -1
        rescan()
    }

    /// Возвращает, куда поставить курсор, или nil, если отменять нечего.
    func undo(side: Int, caret: TextPos) -> (side: Int, caret: TextPos)? {
        guard let s = undoStack.popLast() else { return nil }
        lastTyping = nil
        redoStack.append(snapshot(side: side, caret: caret))
        restore(s)
        return (s.side, s.caret)
    }

    func redo(side: Int, caret: TextPos) -> (side: Int, caret: TextPos)? {
        guard let s = redoStack.popLast() else { return nil }
        undoStack.append(snapshot(side: side, caret: caret))
        restore(s)
        return (s.side, s.caret)
    }

    // MARK: Правка

    func clamp(_ p: TextPos, side: Int) -> TextPos {
        let lines = sides[side].lines
        let line = min(max(p.line, 0), lines.count - 1)
        let col = min(max(p.col, 0), (lines[line].text as NSString).length)
        return TextPos(line: line, col: col)
    }

    func text(side: Int, from a: TextPos, to b: TextPos) -> String {
        let lines = sides[side].lines
        if a.line == b.line {
            return (lines[a.line].text as NSString).substring(with: NSRange(location: a.col, length: b.col - a.col))
        }
        var out = (lines[a.line].text as NSString).substring(from: a.col) + lines[a.line].eol
        for i in (a.line + 1)..<b.line { out += lines[i].text + lines[i].eol }
        out += (lines[b.line].text as NSString).substring(to: b.col)
        return out
    }

    /// Заменяет текст между `a` и `b` на `string`; возвращает место сразу после вставленного.
    /// Отмену (`beginChange`) вызывающий заводит сам.
    @discardableResult
    func replace(side: Int, from a: TextPos, to b: TextPos, with string: String) -> TextPos {
        let file = sides[side]
        let eol = file.dominantEOL
        let head = (file.lines[a.line].text as NSString).substring(to: a.col)
        let tail = (file.lines[b.line].text as NSString).substring(from: b.col)
        let tailEOL = file.lines[b.line].eol
        var inserted = TextFile.split(string)
        for i in 0..<(inserted.count - 1) { inserted[i].eol = eol }
        let endLine = a.line + inserted.count - 1
        let endCol = (inserted.count == 1 ? (head as NSString).length : 0) + (inserted[inserted.count - 1].text as NSString).length
        inserted[0].text = head + inserted[0].text
        inserted[inserted.count - 1].text += tail
        inserted[inserted.count - 1].eol = tailEOL
        file.lines.replaceSubrange(a.line...b.line, with: inserted)
        file.modified = true
        rescan()
        return TextPos(line: endLine, col: endCol)
    }

    // MARK: Слияние

    /// Копирует отличие `index` со стороны `from` на другую. Отмену заводит вызывающий.
    private func copyBlockRaw(_ index: Int, from: Int) {
        let block = diff.blocks[index]
        let to = 1 - from
        var src = from == 0 ? block.aStart..<(block.aStart + block.aCount) : block.bStart..<(block.bStart + block.bCount)
        var dst = to == 0 ? block.aStart..<(block.aStart + block.aCount) : block.bStart..<(block.bStart + block.bCount)
        let source = sides[from], target = sides[to]
        func bodyEnd(_ f: TextFile) -> Int {
            if let last = f.lines.last, last.text.isEmpty, last.eol.isEmpty { return f.lines.count - 1 }
            return f.lines.count
        }
        // Отличие в самом конце обеих сторон — переносим и хвост, иначе не сойдётся завершающий перевод строки.
        if src.upperBound == bodyEnd(source) && dst.upperBound == bodyEnd(target) {
            src = src.lowerBound..<source.lines.count
            dst = dst.lowerBound..<target.lines.count
        }
        target.lines.replaceSubrange(dst, with: source.lines[src])
        // Порядок: у всех строк, кроме последней, есть конец; последняя — без него.
        let eol = target.dominantEOL
        if target.lines.isEmpty { target.lines = [TextLine(text: "", eol: "")] }
        for i in 0..<(target.lines.count - 1) where target.lines[i].eol.isEmpty { target.lines[i].eol = eol }
        if !target.lines[target.lines.count - 1].eol.isEmpty { target.lines.append(TextLine(text: "", eol: "")) }
        target.modified = true
    }

    func copyBlock(_ index: Int, from: Int, caret: TextPos) {
        guard index >= 0, index < diff.blocks.count, !sides[1 - from].readOnly else { return }
        beginChange(side: 1 - from, caret: caret)
        copyBlockRaw(index, from: from)
        currentBlock = -1
        rescan()
    }

    /// «Все вправо» / «Все влево»: с конца к началу, чтобы номера строк не съезжали.
    func copyAll(from: Int, caret: TextPos) {
        guard !diff.significant.isEmpty, !sides[1 - from].readOnly else { return }
        beginChange(side: 1 - from, caret: caret)
        for index in diff.significant.reversed() { copyBlockRaw(index, from: from) }
        currentBlock = -1
        rescan()
    }

    // MARK: Патч

    /// Отличия в едином формате (unified diff), как Tools → Generate Patch.
    func unifiedPatch(context: Int = 3) -> String {
        let a = sides[0].lines, b = sides[1].lines
        var out = "--- \(sides[0].path ?? "left")\n+++ \(sides[1].path ?? "right")\n"
        let rows = diff.rows
        var i = 0
        while i < rows.count {
            guard rows[i].block >= 0 else { i += 1; continue }
            // Кусок: от первого отличия, пока до следующего меньше двух контекстов.
            var end = i
            var j = i
            while j < rows.count {
                if rows[j].block >= 0 { end = j; j += 1 } else if j - end <= context * 2 { j += 1 } else { break }
            }
            let from = max(0, i - context), to = min(rows.count - 1, end + context)
            var body = "", countA = 0, countB = 0
            var startA = 0, startB = 0, seenA = false, seenB = false
            var minus = "", plus = ""
            func flush() { body += minus + plus; minus = ""; plus = "" }
            for r in from...to {
                let row = rows[r]
                if let l = row.left, !seenA { startA = l; seenA = true }
                if let rr = row.right, !seenB { startB = rr; seenB = true }
                if row.block < 0 {
                    flush()
                    guard let l = row.left, !(a[l].text.isEmpty && a[l].eol.isEmpty) else { continue }
                    body += " " + a[l].text + "\n"; countA += 1; countB += 1
                } else {
                    if let l = row.left { minus += "-" + a[l].text + "\n"; countA += 1 }
                    if let rr = row.right { plus += "+" + b[rr].text + "\n"; countB += 1 }
                }
            }
            flush()
            out += "@@ -\(countA == 0 ? startA : startA + 1),\(countA) +\(countB == 0 ? startB : startB + 1),\(countB) @@\n" + body
            i = to + 1
        }
        return out
    }
}
