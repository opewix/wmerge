import Foundation

/// Отбор файлов по маскам, как поле Filter в WinMerge: `*.cpp;*.h`, исключение — `!*.obj` .
struct FileMask {
    private var include: [String] = []
    private var exclude: [String] = []

    init(_ text: String) {
        for raw in text.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let part = raw.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if part.hasPrefix("!") { exclude.append(String(part.dropFirst()).lowercased()) } else { include.append(part.lowercased()) }
        }
        if include.contains("*.*") || include.contains("*") { include = [] }
    }

    func matches(_ name: String) -> Bool {
        let n = name.lowercased()
        if exclude.contains(where: { fnmatch($0, n, 0) == 0 }) { return false }
        return include.isEmpty || include.contains { fnmatch($0, n, 0) == 0 }
    }
}

/// Строка сравнения папок: файл или папка с одним относительным путём с обеих сторон.
final class FolderItem {
    enum Result {
        case identical, different, binaryDifferent, binaryIdentical, leftOnly, rightOnly, error, folder, skipped
    }

    let name: String
    /// Папка относительно корня сравнения, без имени; пусто для корня.
    let folder: String
    let isDirectory: Bool
    var existsLeft: Bool
    var existsRight: Bool
    var result: Result = .folder
    var leftDate: Date?, rightDate: Date?
    var leftSize: Int64?, rightSize: Int64?
    var children: [FolderItem] = []
    weak var parent: FolderItem?

    init(name: String, folder: String, isDirectory: Bool, left: Bool, right: Bool) {
        self.name = name
        self.folder = folder
        self.isDirectory = isDirectory
        existsLeft = left
        existsRight = right
    }

    var relativePath: String { folder.isEmpty ? name : folder + "/" + name }
    var ext: String { isDirectory ? "" : (name as NSString).pathExtension }

    /// Папка отличается, если в ней есть хоть что-то отличающееся.
    var isDifferent: Bool {
        switch result {
        case .identical, .binaryIdentical, .skipped: return false
        case .folder:
            if !(existsLeft && existsRight) { return true }
            return children.contains { $0.isDifferent }
        default: return true
        }
    }
}

struct FolderStats {
    var identical = 0, different = 0, leftOnly = 0, rightOnly = 0, folders = 0
}

/// Сравнение двух папок: проход по дереву и сравнение содержимого файлов.
final class FolderComparer {
    let left: String
    let right: String
    let recursive: Bool
    let mask: FileMask
    let options: CompareOptions
    var cancelled = false
    /// Сколько файлов сравнено — для строки хода.
    var progress: ((Int) -> Void)?
    private var done = 0

    init(left: String, right: String, recursive: Bool, mask: FileMask, options: CompareOptions) {
        self.left = left
        self.right = right
        self.recursive = recursive
        self.mask = mask
        self.options = options
    }

    func run() -> [FolderItem] {
        scan(folder: "", parent: nil)
    }

    private func entries(_ dir: String) -> [String: Bool] {
        var out: [String: Bool] = [:]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return out }
        for name in names where name != ".DS_Store" {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir + "/" + name, isDirectory: &isDir) else { continue }
            out[name] = isDir.boolValue
        }
        return out
    }

    private func scan(folder: String, parent: FolderItem?) -> [FolderItem] {
        let l = parent?.existsLeft == false ? [:] : entries(folder.isEmpty ? left : left + "/" + folder)
        let r = parent?.existsRight == false ? [:] : entries(folder.isEmpty ? right : right + "/" + folder)
        var items: [FolderItem] = []
        let names = Set(l.keys).union(r.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in names {
            if cancelled { break }
            let dirL = l[name], dirR = r[name]
            // Папка с одной стороны и файл с другой — две разные строки.
            let kinds: [Bool] = dirL != nil && dirR != nil && dirL != dirR ? [true, false] : [dirL ?? dirR ?? false]
            for isDir in kinds {
                let inL = dirL == isDir, inR = dirR == isDir
                if !isDir && !mask.matches(name) { continue }
                let item = FolderItem(name: name, folder: folder, isDirectory: isDir, left: inL, right: inR)
                item.parent = parent
                fill(item)
                if isDir {
                    if recursive {
                        item.children = scan(folder: item.relativePath, parent: item)
                    }
                    item.result = .folder
                } else if !inL {
                    item.result = .rightOnly
                } else if !inR {
                    item.result = .leftOnly
                } else {
                    item.result = compareFiles(left + "/" + item.relativePath, right + "/" + item.relativePath)
                    done += 1
                    if done % 20 == 0 { progress?(done) }
                }
                items.append(item)
            }
        }
        // Как в WinMerge: сначала папки, потом файлы.
        return items.filter { $0.isDirectory } + items.filter { !$0.isDirectory }
    }

    private func fill(_ item: FolderItem) {
        let fm = FileManager.default
        if item.existsLeft, let a = try? fm.attributesOfItem(atPath: left + "/" + item.relativePath) {
            item.leftDate = a[.modificationDate] as? Date
            item.leftSize = (a[.size] as? NSNumber)?.int64Value
        }
        if item.existsRight, let a = try? fm.attributesOfItem(atPath: right + "/" + item.relativePath) {
            item.rightDate = a[.modificationDate] as? Date
            item.rightSize = (a[.size] as? NSNumber)?.int64Value
        }
    }

    func compareFiles(_ a: String, _ b: String) -> FolderItem.Result {
        guard let da = try? Data(contentsOf: URL(fileURLWithPath: a), options: .mappedIfSafe),
              let db = try? Data(contentsOf: URL(fileURLWithPath: b), options: .mappedIfSafe) else { return .error }
        let binary = TextFile.isBinary(da) || TextFile.isBinary(db)
        if da == db { return binary ? .binaryIdentical : .identical }
        if binary { return .binaryDifferent }
        if options.isExact { return .different }
        // Байты разные, но настройки могут велеть разницу не замечать — сравниваем как текст.
        let la = TextFile.split(TextFile.decode(da).0), lb = TextFile.split(TextFile.decode(db).0)
        return DiffResult.compute(la, lb, options: options).identical ? .identical : .different
    }

    static func stats(_ items: [FolderItem]) -> FolderStats {
        var s = FolderStats()
        func walk(_ list: [FolderItem]) {
            for item in list {
                if item.isDirectory {
                    if item.existsLeft && item.existsRight { s.folders += 1 } else if item.existsLeft { s.leftOnly += 1 } else { s.rightOnly += 1 }
                    walk(item.children)
                    continue
                }
                switch item.result {
                case .identical, .binaryIdentical: s.identical += 1
                case .different, .binaryDifferent: s.different += 1
                case .leftOnly: s.leftOnly += 1
                case .rightOnly: s.rightOnly += 1
                default: break
                }
            }
        }
        walk(items)
        return s
    }
}
