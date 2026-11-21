import Foundation

/// `WMerge -selftest`: проверка движка сравнения и слияния на случайных текстах.
enum SelfTest {
    static func run() -> Never {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL: \(what)") } }
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(n))
        }
        func file(_ text: String) -> TextFile {
            let f = TextFile()
            f.lines = TextFile.split(text)
            return f
        }
        let words = ["alpha", "beta", "gamma {", "}", "", "  x = 1;", "return y;", "if (a)", "delta", "eps"]
        for round in 0..<400 {
            func text() -> String {
                var s = (0..<rnd(30)).map { _ in words[rnd(words.count)] }.joined(separator: "\n")
                if rnd(2) == 0 { s += "\n" }
                return s
            }
            let a = text(), b = rnd(10) == 0 ? a : text()
            // Отличия покрывают все строки, совпадающие строки действительно равны.
            let doc = CompareDocument(left: file(a), right: file(b))
            for row in doc.diff.rows where row.block < 0 {
                if let l = row.left, let r = row.right {
                    check(doc.sides[0].lines[l] == doc.sides[1].lines[r], "round \(round): equal rows differ")
                }
            }
            check(doc.diff.rows.compactMap { $0.left }.count == doc.sides[0].lines.count, "round \(round): left lines lost")
            check(doc.diff.rows.compactMap { $0.right }.count == doc.sides[1].lines.count, "round \(round): right lines lost")
            check((doc.significantCount == 0) == (a == b), "round \(round): identical flag")
            // Копирование всех отличий делает стороны равными, отмена возвращает как было.
            let from = rnd(2)
            doc.copyAll(from: from, caret: TextPos(line: 0, col: 0))
            check(doc.sides[0].text == doc.sides[1].text, "round \(round): copyAll did not converge")
            check(doc.sides[from].text == (from == 0 ? a : b), "round \(round): source changed")
            _ = doc.undo(side: 0, caret: TextPos(line: 0, col: 0))
            check(doc.sides[0].text == a && doc.sides[1].text == b, "round \(round): undo")
            // По одному отличию — тоже сходится.
            var guardCount = 0
            while let first = doc.diff.significant.first, guardCount < 200 {
                doc.copyBlock(first, from: from, caret: TextPos(line: 0, col: 0))
                guardCount += 1
            }
            check(doc.sides[0].text == doc.sides[1].text, "round \(round): block-by-block did not converge")
            // Правка: вставка и удаление текста сохраняют содержимое.
            let doc2 = CompareDocument(left: file(a), right: file(b))
            let p = doc2.clamp(TextPos(line: rnd(40), col: rnd(8)), side: 0)
            let end = doc2.replace(side: 0, from: p, to: p, with: "new\nline")
            doc2.replace(side: 0, from: p, to: end, with: "")
            check(doc2.sides[0].text == a.replacingOccurrences(of: "\r", with: ""), "round \(round): insert/delete round trip")
        }
        var o = CompareOptions()
        o.whitespace = .ignoreChange
        check(o.key("a  b\t c ", eol: "\n") == o.key("a b c", eol: "\n"), "ignore whitespace change")
        o.whitespace = .ignoreAll; o.ignoreCase = true; o.ignoreEOL = true
        check(o.key(" A b", eol: "\r\n") == o.key("ab", eol: "\n"), "ignore all")
        let inline = InlineDiff.compute("success = TRUE;", "success = true;", options: CompareOptions(), wordLevel: true)
        check(inline.a == [NSRange(location: 10, length: 4)] && inline.b == [NSRange(location: 10, length: 4)], "inline diff")
        check(FileMask("*.cpp;*.h;!x.h").matches("a.CPP") && !FileMask("*.cpp;*.h;!x.h").matches("x.h") && !FileMask("*.cpp").matches("a.txt"), "masks")
        print(failures == 0 ? "selftest: OK" : "selftest: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
