import Foundation

/// Текстовый файл в памяти: строки с их концами, кодировка, признак изменения.
final class TextFile {
    var lines: [TextLine] = [TextLine(text: "", eol: "")]
    var encoding: String.Encoding = .utf8
    var hasBOM = false
    var path: String?
    /// Название для заголовка панели вместо пути — его задаёт программа, открывшая сравнение
    /// (WTortoise: «main.swift : 04b0efe3» вместо пути во временной папке).
    var title: String?
    var modified = false
    var readOnly = false
    /// Время изменения файла на диске в момент чтения — чтобы заметить правку извне.
    var diskDate: Date?

    enum LoadError: Error { case unreadable(String), binary }

    static func isBinary(_ data: Data) -> Bool {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return false }
        return data.prefix(64 * 1024).contains(0)
    }

    static func load(_ path: String) throws -> TextFile {
        guard let data = FileManager.default.contents(atPath: path) else { throw LoadError.unreadable(path) }
        if isBinary(data) { throw LoadError.binary }
        let file = TextFile()
        file.path = path
        file.diskDate = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let (text, encoding, bom) = decode(data)
        file.encoding = encoding
        file.hasBOM = bom
        file.lines = split(text)
        return file
    }

    static func decode(_ data: Data) -> (String, String.Encoding, Bool) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) {
            return (s, .utf8, true)
        }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return (s, .utf16LittleEndian, true)
        }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return (s, .utf16BigEndian, true)
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8, false) }
        // Не UTF-8: однобайтовая кодировка Windows по языку системы.
        let fallback: String.Encoding = Locale.preferredLanguages.first?.hasPrefix("ru") == true || L.isRussian
            ? .windowsCP1251 : .windowsCP1252
        if let s = String(data: data, encoding: fallback) { return (s, fallback, false) }
        return (String(decoding: data, as: UTF8.self), .utf8, false)
    }

    static func split(_ text: String) -> [TextLine] {
        var lines: [TextLine] = []
        let s = text as NSString
        let n = s.length
        var start = 0, i = 0
        while i < n {
            let c = s.character(at: i)
            if c == 10 {
                lines.append(TextLine(text: s.substring(with: NSRange(location: start, length: i - start)), eol: "\n"))
                i += 1; start = i
            } else if c == 13 {
                let crlf = i + 1 < n && s.character(at: i + 1) == 10
                lines.append(TextLine(text: s.substring(with: NSRange(location: start, length: i - start)), eol: crlf ? "\r\n" : "\r"))
                i += crlf ? 2 : 1; start = i
            } else {
                i += 1
            }
        }
        lines.append(TextLine(text: s.substring(with: NSRange(location: start, length: n - start)), eol: ""))
        return lines
    }

    var text: String {
        var out = ""
        for line in lines { out += line.text; out += line.eol }
        return out
    }

    func save(to target: String) throws {
        var data = Data()
        if hasBOM {
            switch encoding {
            case .utf8: data.append(contentsOf: [0xEF, 0xBB, 0xBF])
            case .utf16LittleEndian: data.append(contentsOf: [0xFF, 0xFE])
            case .utf16BigEndian: data.append(contentsOf: [0xFE, 0xFF])
            default: break
            }
        }
        guard let body = text.data(using: encoding, allowLossyConversion: false) ?? text.data(using: .utf8) else {
            throw LoadError.unreadable(target)
        }
        data.append(body)
        try data.write(to: URL(fileURLWithPath: target), options: .atomic)
        path = target
        modified = false
        diskDate = (try? FileManager.default.attributesOfItem(atPath: target))?[.modificationDate] as? Date
    }

    /// Конец строки, которым пишутся новые строки: тот, что в файле преобладает.
    var dominantEOL: String {
        var counts: [String: Int] = [:]
        for line in lines.prefix(2000) where !line.eol.isEmpty { counts[line.eol, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? "\n"
    }

    /// Подпись конца строк для строки состояния — как в WinMerge: Win, Unix, Mac, Mixed.
    var eolName: String {
        var kinds = Set<String>()
        for line in lines where !line.eol.isEmpty { kinds.insert(line.eol) }
        if kinds.count > 1 { return "Mixed" }
        switch kinds.first {
        case "\r\n": return "Win"
        case "\r": return "Mac"
        case "\n": return "Unix"
        default: return ""
        }
    }

    var encodingName: String {
        switch encoding {
        case .utf8: return hasBOM ? "UTF-8 (B)" : "UTF-8"
        case .utf16LittleEndian: return "UCS-2 LE"
        case .utf16BigEndian: return "UCS-2 BE"
        case .windowsCP1251: return "1251"
        case .windowsCP1252: return "1252"
        default: return "\(encoding.rawValue)"
        }
    }
}
