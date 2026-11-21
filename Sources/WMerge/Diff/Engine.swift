import Foundation

/// Настройки сравнения — те же, что в WinMerge на странице Options → Compare → General.
struct CompareOptions: Equatable {
    enum Whitespace: Int { case compare = 0, ignoreChange, ignoreAll }
    var whitespace: Whitespace = .compare
    var ignoreBlankLines = false
    var ignoreCase = false
    var ignoreEOL = false

    static var current: CompareOptions {
        let d = UserDefaults.standard
        return CompareOptions(
            whitespace: Whitespace(rawValue: d.integer(forKey: "cmp.whitespace")) ?? .compare,
            ignoreBlankLines: d.bool(forKey: "cmp.ignoreBlankLines"),
            ignoreCase: d.bool(forKey: "cmp.ignoreCase"),
            ignoreEOL: d.bool(forKey: "cmp.ignoreEOL"))
    }

    func save() {
        let d = UserDefaults.standard
        d.set(whitespace.rawValue, forKey: "cmp.whitespace")
        d.set(ignoreBlankLines, forKey: "cmp.ignoreBlankLines")
        d.set(ignoreCase, forKey: "cmp.ignoreCase")
        d.set(ignoreEOL, forKey: "cmp.ignoreEOL")
    }

    /// Ничего не игнорируется: равенство строк — это равенство байтов.
    var isExact: Bool { whitespace == .compare && !ignoreBlankLines && !ignoreCase && !ignoreEOL }

    /// То, по чему строки сравниваются: текст после всех «игнорировать».
    func key(_ text: String, eol: String) -> String {
        var s = ignoreCase ? text.lowercased() : text
        switch whitespace {
        case .compare: break
        case .ignoreAll:
            s = String(s.unicodeScalars.filter { $0 != " " && $0 != "\t" })
        case .ignoreChange:
            var out = String.UnicodeScalarView()
            var pendingSpace = false
            for u in s.unicodeScalars {
                if u == " " || u == "\t" { pendingSpace = true; continue }
                if pendingSpace { out.append(" "); pendingSpace = false }
                out.append(u)
            }
            s = String(out)
        }
        if !ignoreEOL { s += eol }
        return s
    }

    static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" }
    }
}

/// Сравнение двух последовательностей чисел по Майерсу в линейной памяти («средняя змейка»).
enum Myers {
    /// Возвращает отметки «элемента нет в общей подпоследовательности» для каждой стороны.
    static func diff(_ a: [Int], _ b: [Int]) -> (a: [Bool], b: [Bool]) {
        var ma = [Bool](repeating: false, count: a.count)
        var mb = [Bool](repeating: false, count: b.count)
        let max = a.count + b.count + 1
        var down = [Int](repeating: 0, count: 2 * max + 2)
        var up = [Int](repeating: 0, count: 2 * max + 2)
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                // Свой стек вместо рекурсии: на файлах в сотни тысяч строк рекурсия уходит глубоко.
                var stack: [(Int, Int, Int, Int)] = [(0, a.count, 0, b.count)]
                while let (la0, ua0, lb0, ub0) = stack.popLast() {
                    var la = la0, ua = ua0, lb = lb0, ub = ub0
                    while la < ua && lb < ub && pa[la] == pb[lb] { la += 1; lb += 1 }
                    while la < ua && lb < ub && pa[ua - 1] == pb[ub - 1] { ua -= 1; ub -= 1 }
                    if la == ua {
                        while lb < ub { mb[lb] = true; lb += 1 }
                    } else if lb == ub {
                        while la < ua { ma[la] = true; la += 1 }
                    } else {
                        let (x, y) = middleSnake(pa, la, ua, pb, lb, ub, &down, &up, max)
                        stack.append((x, ua, y, ub))
                        stack.append((la, x, lb, y))
                    }
                }
            }
        }
        return (ma, mb)
    }

    private static func middleSnake(_ a: UnsafeBufferPointer<Int>, _ lowerA: Int, _ upperA: Int,
                                    _ b: UnsafeBufferPointer<Int>, _ lowerB: Int, _ upperB: Int,
                                    _ down: inout [Int], _ up: inout [Int], _ max: Int) -> (Int, Int) {
        let downK = lowerA - lowerB
        let upK = upperA - upperB
        let delta = (upperA - lowerA) - (upperB - lowerB)
        let oddDelta = (delta & 1) != 0
        let downOffset = max - downK
        let upOffset = max - upK
        let maxD = ((upperA - lowerA + upperB - lowerB) / 2) + 1
        down[downOffset + downK + 1] = lowerA
        up[upOffset + upK - 1] = upperA
        for d in 0...maxD {
            var k = downK - d
            while k <= downK + d {
                var x: Int
                if k == downK - d {
                    x = down[downOffset + k + 1]
                } else {
                    x = down[downOffset + k - 1] + 1
                    if k < downK + d && down[downOffset + k + 1] >= x { x = down[downOffset + k + 1] }
                }
                var y = x - k
                while x < upperA && y < upperB && a[x] == b[y] { x += 1; y += 1 }
                down[downOffset + k] = x
                if oddDelta && upK - d < k && k < upK + d && up[upOffset + k] <= down[downOffset + k] {
                    return (down[downOffset + k], down[downOffset + k] - k)
                }
                k += 2
            }
            k = upK - d
            while k <= upK + d {
                var x: Int
                if k == upK + d {
                    x = up[upOffset + k - 1]
                } else {
                    x = up[upOffset + k + 1] - 1
                    if k > upK - d && up[upOffset + k - 1] < x { x = up[upOffset + k - 1] }
                }
                var y = x - k
                while x > lowerA && y > lowerB && a[x - 1] == b[y - 1] { x -= 1; y -= 1 }
                up[upOffset + k] = x
                if !oddDelta && downK - d <= k && k <= downK + d && up[upOffset + k] <= down[downOffset + k] {
                    return (down[downOffset + k], down[downOffset + k] - k)
                }
                k += 2
            }
        }
        return (lowerA, lowerB) // недостижимо
    }

    /// Сравнение строк: одинаковым ключам — одинаковые номера.
    static func diff(keys a: [String], _ b: [String]) -> (a: [Bool], b: [Bool]) {
        var ids: [String: Int] = [:]
        ids.reserveCapacity(a.count + b.count)
        func id(_ s: String) -> Int {
            if let v = ids[s] { return v }
            let v = ids.count
            ids[s] = v
            return v
        }
        return diff(a.map(id), b.map(id))
    }
}

/// Строка документа: текст и её конец (`\n`, `\r\n`, `\r` или пусто у последней).
struct TextLine: Equatable {
    var text: String
    var eol: String
}

/// Отличие: строки `aStart..<aStart+aCount` слева против `bStart..<bStart+bCount` справа.
struct DiffBlock {
    var aStart: Int, aCount: Int
    var bStart: Int, bCount: Int
    var rowStart = 0
    var rowCount = 0
    /// Отличие, которое настройки велят не считать (пустые строки).
    var trivial = false
}

/// Строка экрана: номер строки слева и справа (nil — «призрачная» строка-заполнитель) и номер отличия.
struct DiffRow {
    var left: Int?
    var right: Int?
    var block: Int   // -1 — строки совпадают
}

struct DiffResult {
    var blocks: [DiffBlock] = []
    var rows: [DiffRow] = []
    /// Номера значимых отличий (без trivial) — по ним ходит навигация.
    var significant: [Int] = []
    /// Строка экрана по номеру строки документа.
    var leftRow: [Int] = []
    var rightRow: [Int] = []

    var identical: Bool { significant.isEmpty }

    static func compute(_ left: [TextLine], _ right: [TextLine], options: CompareOptions) -> DiffResult {
        // Пустая последняя строка (после завершающего перевода строки) в сравнении не участвует:
        // отсутствие перевода строки и так видно по концу предыдущей.
        func body(_ lines: [TextLine]) -> Int {
            if let last = lines.last, last.text.isEmpty, last.eol.isEmpty, lines.count > 0 { return lines.count - 1 }
            return lines.count
        }
        let na = body(left), nb = body(right)
        let ka = (0..<na).map { options.key(left[$0].text, eol: left[$0].eol) }
        let kb = (0..<nb).map { options.key(right[$0].text, eol: right[$0].eol) }
        let (ma, mb) = Myers.diff(keys: ka, kb)

        var result = DiffResult()
        result.leftRow = [Int](repeating: 0, count: left.count)
        result.rightRow = [Int](repeating: 0, count: right.count)
        var i = 0, j = 0
        while i < na || j < nb {
            if i < na && j < nb && !ma[i] && !mb[j] {
                result.leftRow[i] = result.rows.count
                result.rightRow[j] = result.rows.count
                result.rows.append(DiffRow(left: i, right: j, block: -1))
                i += 1; j += 1
                continue
            }
            var block = DiffBlock(aStart: i, aCount: 0, bStart: j, bCount: 0)
            while i < na && ma[i] { i += 1 }
            while j < nb && mb[j] { j += 1 }
            block.aCount = i - block.aStart
            block.bCount = j - block.bStart
            block.rowStart = result.rows.count
            if options.ignoreBlankLines {
                let blankA = (block.aStart..<i).allSatisfy { CompareOptions.isBlank(left[$0].text) }
                let blankB = (block.bStart..<j).allSatisfy { CompareOptions.isBlank(right[$0].text) }
                block.trivial = blankA && blankB
            }
            let index = result.blocks.count
            for (l, rr) in align(left, block.aStart, block.aCount, right, block.bStart, block.bCount) {
                if let l { result.leftRow[l] = result.rows.count }
                if let rr { result.rightRow[rr] = result.rows.count }
                result.rows.append(DiffRow(left: l, right: rr, block: index))
            }
            block.rowCount = result.rows.count - block.rowStart
            if !block.trivial { result.significant.append(index) }
            result.blocks.append(block)
        }
        // Хвостовые пустые строки — парой, без отличия.
        if na < left.count || nb < right.count {
            let l = na < left.count ? na : nil
            let r = nb < right.count ? nb : nil
            if let l { result.leftRow[l] = result.rows.count }
            if let r { result.rightRow[r] = result.rows.count }
            result.rows.append(DiffRow(left: l, right: r, block: -1))
        }
        return result
    }
}

/// Раскладка строк внутри отличия: похожие строки ставятся друг против друга, остальные — подряд сверху,
/// нехватка добивается «призрачными» строками.
private func align(_ left: [TextLine], _ aStart: Int, _ aCount: Int,
                   _ right: [TextLine], _ bStart: Int, _ bCount: Int) -> [(Int?, Int?)] {
    var out: [(Int?, Int?)] = []
    func plain(_ a0: Int, _ a1: Int, _ b0: Int, _ b1: Int) {
        for r in 0..<max(a1 - a0, b1 - b0) {
            out.append((a0 + r < a1 ? a0 + r : nil, b0 + r < b1 ? b0 + r : nil))
        }
    }
    if aCount == bCount || aCount == 0 || bCount == 0 || aCount * bCount > 40_000 {
        plain(aStart, aStart + aCount, bStart, bStart + bCount)
        return out
    }
    func words(_ s: String) -> Set<Substring> {
        Set(s.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }))
    }
    let wa = (0..<aCount).map { words(left[aStart + $0].text) }
    let wb = (0..<bCount).map { words(right[bStart + $0].text) }
    func similarity(_ i: Int, _ j: Int) -> Double {
        let m = max(wa[i].count, wb[j].count)
        if m == 0 {
            return left[aStart + i].text.trimmingCharacters(in: .whitespaces) == right[bStart + j].text.trimmingCharacters(in: .whitespaces) ? 1 : 0
        }
        return Double(wa[i].intersection(wb[j]).count) / Double(m)
    }
    // Наибольшая по сумме похожести цепочка пар (как LCS, но совпадение — «похожи хотя бы наполовину»).
    var score = [[Double]](repeating: [Double](repeating: 0, count: bCount + 1), count: aCount + 1)
    var sim = [[Double]](repeating: [Double](repeating: 0, count: bCount), count: aCount)
    for i in stride(from: aCount - 1, through: 0, by: -1) {
        for j in stride(from: bCount - 1, through: 0, by: -1) {
            let s = similarity(i, j)
            sim[i][j] = s
            var best = max(score[i + 1][j], score[i][j + 1])
            if s >= 0.5 { best = max(best, score[i + 1][j + 1] + s) }
            score[i][j] = best
        }
    }
    var i = 0, j = 0, lastA = 0, lastB = 0
    while i < aCount && j < bCount {
        if sim[i][j] >= 0.5 && score[i][j] == score[i + 1][j + 1] + sim[i][j] {
            plain(aStart + lastA, aStart + i, bStart + lastB, bStart + j)
            out.append((aStart + i, bStart + j))
            i += 1; j += 1
            lastA = i; lastB = j
        } else if score[i + 1][j] >= score[i][j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    plain(aStart + lastA, aStart + aCount, bStart + lastB, bStart + bCount)
    return out
}

/// Отличия внутри пары строк: диапазоны UTF-16, которые подсвечиваются темнее.
enum InlineDiff {
    private static func tokens(_ s: NSString, wordLevel: Bool) -> [NSRange] {
        var out: [NSRange] = []
        let n = s.length
        var i = 0
        func cls(_ c: unichar) -> Int {
            if c == 32 || c == 9 { return 0 }
            if let u = Unicode.Scalar(c), CharacterSet.alphanumerics.contains(u) || c == 95 { return 1 }
            if c >= 0xD800 && c <= 0xDFFF { return 1 }
            return 2
        }
        while i < n {
            if !wordLevel {
                let r = s.rangeOfComposedCharacterSequence(at: i)
                out.append(r)
                i = NSMaxRange(r)
                continue
            }
            let c = cls(s.character(at: i))
            var j = i + 1
            if c != 2 { while j < n && cls(s.character(at: j)) == c { j += 1 } }
            out.append(NSRange(location: i, length: j - i))
            i = j
        }
        return out
    }

    static func compute(_ a: String, _ b: String, options: CompareOptions, wordLevel: Bool) -> (a: [NSRange], b: [NSRange]) {
        let sa = a as NSString, sb = b as NSString
        if sa.length > 4000 || sb.length > 4000 { return ([], []) }
        func prepare(_ s: NSString) -> (ranges: [NSRange], keys: [String]) {
            var ranges: [NSRange] = [], keys: [String] = []
            for r in tokens(s, wordLevel: wordLevel) {
                var t = s.substring(with: r)
                let space = CompareOptions.isBlank(t)
                if space {
                    if options.whitespace == .ignoreAll { continue }
                    if options.whitespace == .ignoreChange { t = " " }
                }
                if options.ignoreCase { t = t.lowercased() }
                ranges.append(r)
                keys.append(t)
            }
            return (ranges, keys)
        }
        let pa = prepare(sa), pb = prepare(sb)
        let (ma, mb) = Myers.diff(keys: pa.keys, pb.keys)
        func merge(_ ranges: [NSRange], _ marks: [Bool]) -> [NSRange] {
            var out: [NSRange] = []
            for (i, r) in ranges.enumerated() where marks[i] {
                if let last = out.last, NSMaxRange(last) == r.location {
                    out[out.count - 1].length += r.length
                } else {
                    out.append(r)
                }
            }
            return out
        }
        return (merge(pa.ranges, ma), merge(pb.ranges, mb))
    }
}
