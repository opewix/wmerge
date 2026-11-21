import AppKit

/// Подсветка синтаксиса. Цвета — умолчания редактора WinMerge.
enum SyntaxKind {
    case keyword, function, comment, number, op, string, preprocessor, user

    var color: NSColor {
        switch self {
        case .keyword: return NSColor(0, 0, 255)
        case .function: return NSColor(128, 0, 128)
        case .comment: return NSColor(0, 128, 0)
        case .number: return NSColor(255, 0, 0)
        case .op: return NSColor(96, 96, 96)
        case .string: return NSColor(128, 0, 0)
        case .preprocessor: return NSColor(0, 128, 192)
        case .user: return NSColor(255, 128, 0)
        }
    }
}

final class Language {
    var lineComments: [String] = []
    var blockStart: String?
    var blockEnd: String?
    var keywords: Set<String> = []
    var quotes: Set<unichar> = [34, 39]
    var preprocessor = false
    var caseInsensitive = false
    var markup = false

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }

    private static func cLike(_ keywords: String, preprocessor: Bool = false, backtick: Bool = false) -> Language {
        let l = Language()
        l.lineComments = ["//"]
        l.blockStart = "/*"; l.blockEnd = "*/"
        l.keywords = words(keywords)
        l.preprocessor = preprocessor
        if backtick { l.quotes.insert(96) }
        return l
    }

    private static func hash(_ keywords: String) -> Language {
        let l = Language()
        l.lineComments = ["#"]
        l.keywords = words(keywords)
        return l
    }

    private static let cpp = cLike("""
        alignas alignof asm auto bool break case catch char char8_t char16_t char32_t class concept const consteval constexpr \
        constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit \
        export extern false float for friend goto if inline int long mutable namespace new noexcept nullptr operator private \
        protected public register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct \
        switch template this thread_local throw true try typedef typeid typename union unsigned using virtual void volatile \
        wchar_t while override final id self super nil YES NO instancetype
        """, preprocessor: true)
    private static let csharp = cLike("""
        abstract as async await base bool break byte case catch char checked class const continue decimal default delegate do \
        double else enum event explicit extern false finally fixed float for foreach get goto if implicit in int interface \
        internal is lock long namespace new null object operator out override params partial private protected public readonly \
        record ref return sbyte sealed set short sizeof stackalloc static string struct switch this throw true try typeof uint \
        ulong unchecked unsafe ushort using var virtual void volatile when where while yield
        """, preprocessor: true)
    private static let java = cLike("""
        abstract assert boolean break byte case catch char class const continue default do double else enum extends false final \
        finally float for goto if implements import instanceof int interface long native new null package private protected \
        public record return short static strictfp super switch synchronized this throw throws transient true try var void \
        volatile while fun val when object companion data sealed override open internal lateinit by in is as suspend
        """)
    private static let js = cLike("""
        abstract any as async await boolean break case catch class const constructor continue debugger declare default delete do \
        else enum export extends false finally for from function get if implements import in instanceof interface let module \
        namespace new null number of package private protected public readonly return set static string super switch this throw \
        true try type typeof undefined var void while with yield
        """, backtick: true)
    private static let swift = cLike("""
        actor any as associatedtype async await break case catch class continue convenience default defer deinit didSet do \
        dynamic else enum extension fallthrough false fileprivate final for func get guard if import in indirect infix init \
        inout internal is lazy let mutating nil nonisolated open operator optional override postfix prefix private protocol \
        public repeat required rethrows return self Self set some static struct subscript super switch throw throws true try \
        typealias unowned var weak where while willSet
        """)
    private static let go = cLike("""
        break case chan const continue default defer else fallthrough false for func go goto if import interface map nil package \
        range return select struct switch true type var as async await crate dyn enum extern fn impl in let loop match mod move \
        mut pub ref self Self static super trait unsafe use where while
        """, backtick: true)
    private static let php = cLike("""
        abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty \
        enddeclare endfor endforeach endif endswitch endwhile extends false final finally fn for foreach function global goto if \
        implements include include_once instanceof insteadof interface isset list match namespace new null or print private \
        protected public readonly require require_once return static switch throw trait true try unset use var while xor yield
        """)
    private static let css: Language = {
        let l = Language()
        l.blockStart = "/*"; l.blockEnd = "*/"
        return l
    }()
    private static let python = hash("""
        False None True and as assert async await break class continue def del elif else except finally for from global if \
        import in is lambda nonlocal not or pass raise return try while with yield match case self
        """)
    private static let shell = hash("""
        if then else elif fi for while until do done case esac function in select return exit break continue local export \
        readonly declare unset shift source alias echo set
        """)
    private static let ruby = hash("""
        alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo \
        rescue retry return self super then true undef unless until when while yield require attr_accessor attr_reader
        """)
    private static let config = hash("true false yes no on off null")
    private static let sql: Language = {
        let l = Language()
        l.lineComments = ["--"]
        l.blockStart = "/*"; l.blockEnd = "*/"
        l.caseInsensitive = true
        l.keywords = words("""
            add all alter and as asc begin between by case check column commit constraint create cross database default delete \
            desc distinct drop else end exists foreign from full group having if in index inner insert into is join key left \
            like limit not null on or order outer primary procedure references right rollback select set table then top \
            transaction trigger union unique update values view when where with int integer varchar char text date datetime \
            timestamp boolean numeric decimal float
            """)
        return l
    }()
    private static let basic: Language = {
        let l = Language()
        l.lineComments = ["'", "//"]
        l.quotes = [34]
        l.caseInsensitive = true
        l.keywords = words("""
            and as boolean byref byval call case const dim do each else elseif end endif enum exit false for function get if in \
            is loop new next not nothing or private public return select set sub then to true type until wend while with xor \
            процедура функция конецпроцедуры конецфункции если тогда иначе иначеесли конецесли для каждого из по цикл конеццикла \
            пока возврат перем экспорт новый попытка исключение конецпопытки истина ложь неопределено и или не прервать продолжить
            """)
        return l
    }()
    private static let markup: Language = {
        let l = Language()
        l.blockStart = "<!--"; l.blockEnd = "-->"
        l.markup = true
        return l
    }()

    static func forPath(_ path: String?) -> Language? {
        guard let path else { return nil }
        let name = (path as NSString).lastPathComponent.lowercased()
        switch (name as NSString).pathExtension {
        case "c", "cc", "cpp", "cxx", "h", "hh", "hpp", "hxx", "m", "mm", "rc", "inl", "ino": return cpp
        case "cs": return csharp
        case "java", "kt", "kts", "scala", "groovy", "gradle", "dart": return java
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "json", "jsonc": return js
        case "swift": return swift
        case "go", "rs": return go
        case "php": return php
        case "css", "scss", "less": return css
        case "py", "pyw": return python
        case "sh", "bash", "zsh", "fish", "ps1": return shell
        case "rb": return ruby
        case "yml", "yaml", "toml", "ini", "conf", "cfg", "properties", "env": return config
        case "sql": return sql
        case "bas", "vb", "vbs", "bsl", "os", "frm", "cls": return basic
        case "xml", "html", "htm", "xhtml", "xaml", "svg", "plist", "csproj", "razor", "cshtml", "vue", "xsl", "xsd": return markup
        default:
            if name == "makefile" || name == "dockerfile" || name.hasPrefix(".") { return config }
            return nil
        }
    }

    // MARK: Разбор строки

    private static func isWordStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
    }

    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private func has(_ s: NSString, _ i: Int, _ token: String) -> Bool {
        let t = token as NSString
        guard i + t.length <= s.length else { return false }
        return s.compare(token, options: .literal, range: NSRange(location: i, length: t.length)) == .orderedSame
    }

    /// Размечает строку. `state` — «внутри многострочного комментария» на входе и на выходе.
    func highlight(_ s: NSString, state: inout Bool, collect: Bool = true) -> [(NSRange, SyntaxKind)] {
        var out: [(NSRange, SyntaxKind)] = []
        let n = s.length
        var i = 0
        func add(_ from: Int, _ to: Int, _ kind: SyntaxKind) {
            if collect && to > from { out.append((NSRange(location: from, length: to - from), kind)) }
        }
        var inTag = false
        var firstToken = true
        while i < n {
            if state {
                guard let end = blockEnd else { state = false; continue }
                let r = s.range(of: end, options: .literal, range: NSRange(location: i, length: n - i))
                if r.location == NSNotFound { add(i, n, .comment); return out }
                add(i, NSMaxRange(r), .comment)
                i = NSMaxRange(r)
                state = false
                continue
            }
            let c = s.character(at: i)
            if c == 32 || c == 9 { i += 1; continue }
            if let start = blockStart, has(s, i, start) {
                state = true
                let from = i
                i += (start as NSString).length
                if let end = blockEnd {
                    let r = s.range(of: end, options: .literal, range: NSRange(location: i, length: n - i))
                    if r.location == NSNotFound { add(from, n, .comment); return out }
                    add(from, NSMaxRange(r), .comment)
                    i = NSMaxRange(r)
                    state = false
                }
                continue
            }
            if !markup, lineComments.contains(where: { has(s, i, $0) }) {
                add(i, n, .comment)
                return out
            }
            if markup {
                if c == 60 { // <
                    inTag = true
                    var j = i + 1
                    if j < n, s.character(at: j) == 47 { j += 1 }
                    let nameStart = j
                    while j < n, Language.isWordStart(s.character(at: j)) || Language.isDigit(s.character(at: j)) || [45, 58, 46].contains(s.character(at: j)) { j += 1 }
                    add(i, nameStart, .op)
                    add(nameStart, j, .keyword)
                    i = max(j, i + 1)
                    continue
                }
                if c == 62 { inTag = false; add(i, i + 1, .op); i += 1; continue }
                if !inTag { i += 1; continue }
            }
            if preprocessor, firstToken, c == 35 {
                add(i, n, .preprocessor)
                return out
            }
            firstToken = false
            if quotes.contains(c) {
                var j = i + 1
                while j < n {
                    let d = s.character(at: j)
                    if d == 92 { j += 2; continue }
                    if d == c { j += 1; break }
                    j += 1
                }
                j = min(j, n)
                add(i, j, .string)
                i = j
                continue
            }
            if Language.isDigit(c) {
                var j = i + 1
                while j < n {
                    let d = s.character(at: j)
                    if Language.isDigit(d) || Language.isWordStart(d) || d == 46 { j += 1 } else { break }
                }
                add(i, j, .number)
                i = j
                continue
            }
            if Language.isWordStart(c) {
                var j = i + 1
                while j < n, Language.isWordStart(s.character(at: j)) || Language.isDigit(s.character(at: j)) { j += 1 }
                if collect {
                    var word = s.substring(with: NSRange(location: i, length: j - i))
                    if caseInsensitive { word = word.lowercased() }
                    if keywords.contains(word) {
                        add(i, j, .keyword)
                    } else if !markup {
                        var k = j
                        while k < n, s.character(at: k) == 32 { k += 1 }
                        if k < n, s.character(at: k) == 40 { add(i, j, .function) }
                    }
                }
                i = j
                continue
            }
            if !markup { add(i, i + 1, .op) }
            i += 1
        }
        return out
    }

    /// Для каждой строки файла: начинается ли она внутри многострочного комментария.
    func lineStates(_ lines: [TextLine]) -> [Bool] {
        var states = [Bool](repeating: false, count: lines.count)
        guard let start = blockStart else { return states }
        var state = false
        for (i, line) in lines.enumerated() {
            states[i] = state
            // Быстрый путь: в строке нет ни начала, ни конца комментария.
            if !state && !line.text.contains(start) { continue }
            _ = highlight(line.text as NSString, state: &state, collect: false)
        }
        return states
    }
}
