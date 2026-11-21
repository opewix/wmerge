import AppKit

/// Вкладка сравнения папок: заголовки сторон, список с колонками, строка состояния.
final class FolderCompareView: NSView, DocumentTab {
    let leftRoot: String
    let rightRoot: String
    let recursive: Bool
    let maskText: String
    private var items: [FolderItem] = []
    private var comparing = false
    private var comparer: FolderComparer?
    private var elapsed = 0.0

    private let headers = [PaneHeader(), PaneHeader()]
    private let scroll = NSScrollView()
    private var list: DirList!
    private var columnHeader: DirHeader!
    private let status = DirStatus()

    init(left: String, right: String, recursive: Bool, mask: String) {
        leftRoot = left
        rightRoot = right
        self.recursive = recursive
        maskText = mask.isEmpty ? "*.*" : mask
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        list = DirList(host: self)
        columnHeader = DirHeader(list: list)
        headers[0].text = left.hasSuffix("/") ? left : left + "/"
        headers[1].text = right.hasSuffix("/") ? right : right + "/"
        headers[0].active = true
        for (i, h) in headers.enumerated() {
            h.onClick = { [unowned self] in self.headers[0].active = i == 0; self.headers[1].active = i == 1 }
            addSubview(h)
        }
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.borderType = .noBorder
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.columnHeader.offset = self.scroll.contentView.bounds.minX
        }
        addSubview(scroll)
        addSubview(columnHeader)
        addSubview(status)
        status.method = "Full Contents"
        status.filter = maskText
        rescan()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let half = floor((w - 4) / 2)
        headers[0].frame = NSRect(x: 2, y: 2, width: half, height: 19)
        headers[1].frame = NSRect(x: 2 + half + 2, y: 2, width: w - half - 6, height: 19)
        columnHeader.frame = NSRect(x: 0, y: 23, width: w, height: 19)
        scroll.frame = NSRect(x: 0, y: 42, width: w, height: h - 42 - 17)
        status.frame = NSRect(x: 0, y: h - 17, width: w, height: 17)
        list.fit()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
    }

    // MARK: Вкладка

    var tabTitle: String {
        let a = (leftRoot as NSString).lastPathComponent, b = (rightRoot as NSString).lastPathComponent
        return a == b ? "\(a)/ x 2" : "\(a)/ - \(b)/"
    }

    var tabGlyph: Glyph { .tabFolders }

    var statusRight: String {
        if let row = list.focused { return "Item \(row + 1) of \(list.rows.count)" }
        return "Items: \(list.rows.count)"
    }

    func activated() { window?.makeFirstResponder(list) }
    func canClose() -> Bool { comparer?.cancelled = true; return true }

    func settingsChanged() {
        list.rebuild(items)
        updateStatus()
    }

    // MARK: Сравнение

    func rescan() {
        comparer?.cancelled = true
        let job = FolderComparer(left: leftRoot, right: rightRoot, recursive: recursive, mask: FileMask(maskText), options: .current)
        comparer = job
        comparing = true
        status.left = "Comparing items..."
        let started = Date()
        let finish: ([FolderItem]) -> Void = { [weak self] result in
            guard let self, self.comparer === job, !job.cancelled else { return }
            self.items = result
            self.comparing = false
            self.elapsed = Date().timeIntervalSince(started)
            self.list.rebuild(result)
            self.updateStatus()
        }
        if Snapshot.active { finish(job.run()); return }
        job.progress = { [weak self] n in
            DispatchQueue.main.async { if self?.comparer === job { self?.status.left = "Comparing items... \(n)" } }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = job.run()
            DispatchQueue.main.async { finish(result) }
        }
    }

    func updateStatus() {
        if comparing { return }
        let n = list.selected.count
        status.left = n == 0 ? "Elapsed time: \(Int(elapsed * 1000)) ms" : n == 1 ? "1 item selected" : "\(n) items selected"
        MainWindowController.shared.refreshChrome()
    }

    func resultText(_ item: FolderItem) -> String {
        func dir(_ root: String) -> String { item.folder.isEmpty ? root : root + "/" + item.folder }
        if !item.existsRight { return "Left only: \(dir(leftRoot))" }
        if !item.existsLeft { return "Right only: \(dir(rightRoot))" }
        switch item.result {
        case .identical: return "Text files are identical"
        case .different: return "Text files are different"
        case .binaryIdentical: return "Binary files are identical"
        case .binaryDifferent: return "Binary files are different"
        case .error: return "Unable to compare files"
        case .skipped: return "File skipped"
        case .folder: return recursive ? (item.isDifferent ? "Folders are different" : "Identical") : ""
        case .leftOnly, .rightOnly: return ""
        }
    }

    func glyph(_ item: FolderItem) -> Glyph {
        if item.isDirectory {
            if !item.existsRight { return .folderLeft }
            if !item.existsLeft { return .folderRight }
            return recursive ? (item.isDifferent ? .folderDiff : .folderSame) : .folderPlain
        }
        switch item.result {
        case .identical: return .fileSame
        case .different: return .fileDiff
        case .binaryIdentical: return .fileBinarySame
        case .binaryDifferent: return .fileBinaryDiff
        case .leftOnly: return .fileLeft
        case .rightOnly: return .fileRight
        default: return .fileError
        }
    }

    // MARK: Действия

    func open(_ item: FolderItem) {
        if item.isDirectory {
            if recursive && ViewFlag.treeMode.isOn { list.toggle(item); return }
            guard item.existsLeft && item.existsRight else { NSSound.beep(); return }
            MainWindowController.shared.openFolders(leftRoot + "/" + item.relativePath, rightRoot + "/" + item.relativePath,
                                                    recursive: recursive, mask: maskText)
            return
        }
        MainWindowController.shared.openFiles(item.existsLeft ? leftRoot + "/" + item.relativePath : nil,
                                              item.existsRight ? rightRoot + "/" + item.relativePath : nil)
    }

    private func copy(toRight: Bool) {
        let source = toRight ? leftRoot : rightRoot, target = toRight ? rightRoot : leftRoot
        let chosen = list.selectedItems.filter { (toRight ? $0.existsLeft : $0.existsRight) && $0.isDifferent }
        guard !chosen.isEmpty else { NSSound.beep(); return }
        let what = chosen.count == 1 ? "Are you sure you want to copy?" : "Are you sure you want to copy \(chosen.count) items?"
        guard UI.alert(what, info: "From: \(UI.short(source))\nTo: \(UI.short(target))", buttons: ["Yes", "No"], style: .warning) == 0 else { return }
        let fm = FileManager.default
        var failed: [String] = []
        for item in chosen {
            let from = source + "/" + item.relativePath, to = target + "/" + item.relativePath
            do {
                try fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                if item.isDirectory {
                    // Папка накладывается поверх: файлы заменяются, лишнее на той стороне остаётся.
                    try merge(from, into: to)
                } else {
                    if fm.fileExists(atPath: to) { _ = try fm.replaceItemAt(URL(fileURLWithPath: to), withItemAt: temporaryCopy(of: from, near: to)) } else {
                        try fm.copyItem(atPath: from, toPath: to)
                    }
                }
            } catch { failed.append("\(item.relativePath): \(error.localizedDescription)") }
        }
        if !failed.isEmpty { UI.alert("Operation failed.", info: failed.joined(separator: "\n"), style: .warning) }
        rescan()
    }

    private func temporaryCopy(of path: String, near target: String) throws -> URL {
        let temp = URL(fileURLWithPath: target + ".wmerge-" + UUID().uuidString.prefix(8))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: temp)
        return temp
    }

    private func merge(_ from: String, into to: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: to, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: from) where name != ".DS_Store" {
            var isDir: ObjCBool = false
            let a = from + "/" + name, b = to + "/" + name
            fm.fileExists(atPath: a, isDirectory: &isDir)
            if isDir.boolValue { try merge(a, into: b) } else if fm.fileExists(atPath: b) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: b), withItemAt: temporaryCopy(of: a, near: b))
            } else { try fm.copyItem(atPath: a, toPath: b) }
        }
    }

    /// Удаление в Корзину: 0 — слева, 1 — справа, 2 — с обеих сторон.
    func delete(side: Int) {
        var paths: [String] = []
        for item in list.selectedItems {
            if side != 1 && item.existsLeft { paths.append(leftRoot + "/" + item.relativePath) }
            if side != 0 && item.existsRight { paths.append(rightRoot + "/" + item.relativePath) }
        }
        guard !paths.isEmpty else { NSSound.beep(); return }
        let what = paths.count == 1 ? "Are you sure you want to delete\n\(UI.short(paths[0])) ?" : "Are you sure you want to delete \(paths.count) items?"
        guard UI.alert(what, info: "The items are moved to the Trash.", buttons: ["Yes", "No"], style: .warning) == 0 else { return }
        for path in paths { try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) }
        rescan()
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let chosen = list.selectedItems
        let total = chosen.count
        func item(_ title: String, _ action: Selector, _ tag: Int = 0, enabled: Bool = true, to target: NSMenu? = nil) {
            let i = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            i.target = self
            i.tag = tag
            (target ?? menu).addItem(i)
        }
        func sub(_ title: String) -> NSMenu {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.submenu = NSMenu()
            i.submenu?.autoenablesItems = false
            menu.addItem(i)
            return i.submenu!
        }
        menu.autoenablesItems = false
        item("Compare", #selector(menuCompare), enabled: total == 1)
        menu.addItem(.separator())
        let l = chosen.filter { $0.existsLeft }.count, r = chosen.filter { $0.existsRight }.count
        let copyMenu = sub("Copy")
        item("Left to Right (\(l) of \(total))", #selector(menuCopy(_:)), 0, enabled: l > 0, to: copyMenu)
        item("Right to Left (\(r) of \(total))", #selector(menuCopy(_:)), 1, enabled: r > 0, to: copyMenu)
        let deleteMenu = sub("Delete")
        item("Left", #selector(menuDelete(_:)), 0, enabled: l > 0, to: deleteMenu)
        item("Right", #selector(menuDelete(_:)), 1, enabled: r > 0, to: deleteMenu)
        item("Both", #selector(menuDelete(_:)), 2, enabled: l > 0 && r > 0, to: deleteMenu)
        menu.addItem(.separator())
        for (side, title) in ["Open Left", "Open Right"].enumerated() {
            let m = sub(title)
            let ok = side == 0 ? l > 0 : r > 0
            item("With Registered Application", #selector(menuOpen(_:)), side, enabled: ok, to: m)
            item("Open Parent Folder...", #selector(menuReveal(_:)), side, enabled: ok, to: m)
        }
        menu.addItem(.separator())
        let paths = sub("Copy Paths")
        item("Left (\(l) of \(total))", #selector(menuCopyPaths(_:)), 0, enabled: l > 0, to: paths)
        item("Right (\(r) of \(total))", #selector(menuCopyPaths(_:)), 1, enabled: r > 0, to: paths)
        item("Both (\(l + r) of \(total * 2))", #selector(menuCopyPaths(_:)), 2, enabled: l + r > 0, to: paths)
        item("Copy Filenames", #selector(menuCopyPaths(_:)), 3, enabled: total > 0)
        menu.addItem(.separator())
        item("Refresh", #selector(menuRefresh))
        return menu
    }

    @objc private func menuCompare() { if let i = list.selectedItems.first { open(i) } }
    @objc private func menuCopy(_ sender: NSMenuItem) { copy(toRight: sender.tag == 0) }
    @objc private func menuDelete(_ sender: NSMenuItem) { delete(side: sender.tag) }
    @objc private func menuRefresh() { rescan() }

    private func paths(side: Int) -> [String] {
        list.selectedItems.filter { side == 0 ? $0.existsLeft : $0.existsRight }.map { (side == 0 ? leftRoot : rightRoot) + "/" + $0.relativePath }
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        paths(side: sender.tag).forEach { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
    }

    @objc private func menuReveal(_ sender: NSMenuItem) {
        NSWorkspace.shared.activateFileViewerSelecting(paths(side: sender.tag).map { URL(fileURLWithPath: $0) })
    }

    @objc private func menuCopyPaths(_ sender: NSMenuItem) {
        let lines: [String]
        switch sender.tag {
        case 0: lines = paths(side: 0)
        case 1: lines = paths(side: 1)
        case 2: lines = paths(side: 0) + paths(side: 1)
        default: lines = list.selectedItems.map { $0.name }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func isEnabled(_ cmd: Cmd) -> Bool {
        let chosen = list.selectedItems
        switch cmd {
        case .compare: return chosen.count == 1
        case .copyRight: return chosen.contains { $0.existsLeft && $0.isDifferent }
        case .copyLeft: return chosen.contains { $0.existsRight && $0.isDifferent }
        case .delete: return !chosen.isEmpty
        case .nextDiff: return list.differentRow(after: list.focused ?? -1) != nil
        case .prevDiff: return list.differentRow(before: list.focused ?? list.rows.count) != nil
        case .firstDiff, .lastDiff: return list.differentRow(after: -1) != nil
        case .currentDiff: return list.focused != nil
        case .expandAll, .collapseAll: return recursive && ViewFlag.treeMode.isOn
        case .treeMode: return recursive
        case .selectAll, .refresh, .showIdentical, .showDifferent, .showLeftOnly, .showRightOnly: return true
        default: return false
        }
    }

    func isChecked(_ cmd: Cmd) -> Bool { false }

    func perform(_ cmd: Cmd) {
        switch cmd {
        case .compare: menuCompare()
        case .copyRight: copy(toRight: true)
        case .copyLeft: copy(toRight: false)
        case .delete: delete(side: 2)
        case .refresh: rescan()
        case .selectAll: list.selectAll()
        case .nextDiff: if let r = list.differentRow(after: list.focused ?? -1) { list.select(row: r) }
        case .prevDiff: if let r = list.differentRow(before: list.focused ?? list.rows.count) { list.select(row: r) }
        case .firstDiff: if let r = list.differentRow(after: -1) { list.select(row: r) }
        case .lastDiff: if let r = list.differentRow(before: list.rows.count) { list.select(row: r) }
        case .currentDiff: if let r = list.focused { list.select(row: r) }
        case .expandAll: list.expandAll(items)
        case .collapseAll: list.collapseAll()
        default: break
        }
    }
}

/// Строка состояния сравнения папок: слева сообщение, дальше способ сравнения и фильтр.
final class DirStatus: NSView {
    var left = "" { didSet { needsDisplay = true } }
    var method = ""
    var filter = ""
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: NSColor.black]
        (left as NSString).draw(at: NSPoint(x: 5, y: 0.5), withAttributes: attrs)
        (method as NSString).draw(at: NSPoint(x: bounds.width * 0.595, y: 0.5), withAttributes: attrs)
        (filter as NSString).draw(at: NSPoint(x: bounds.width * 0.732, y: 0.5), withAttributes: attrs)
    }
}

/// Колонки списка папок.
enum DirColumn: Int, CaseIterable {
    case name, folder, result, leftDate, rightDate, ext

    var title: String {
        switch self {
        case .name: return "Filename"
        case .folder: return "Folder"
        case .result: return "Comparison result"
        case .leftDate: return "Left Date"
        case .rightDate: return "Right Date"
        case .ext: return "Extension"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 178
        case .folder: return 197
        case .result: return 150
        case .leftDate: return 140
        case .rightDate: return 150
        case .ext: return 75
        }
    }
}

/// Шапка колонок: названия по центру, стрелка сортировки, перетаскивание границ.
final class DirHeader: NSView {
    unowned let list: DirList
    var offset: CGFloat = 0 { didSet { needsDisplay = true } }
    private var resizing: Int?

    init(list: DirList) {
        self.list = list
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        var x = -offset
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: NSColor.black, .paragraphStyle: p]
        for column in DirColumn.allCases {
            let w = list.widths[column.rawValue]
            (column.title as NSString).draw(in: NSRect(x: x + 4, y: 3, width: w - 8, height: 16), withAttributes: attrs)
            if list.sortColumn == column {
                let cx = x + w / 2
                let arrow = NSBezierPath()
                let up = list.sortAscending
                arrow.move(to: NSPoint(x: cx - 3.5, y: up ? 3.5 : 0.5))
                arrow.line(to: NSPoint(x: cx, y: up ? 0.5 : 3.5))
                arrow.line(to: NSPoint(x: cx + 3.5, y: up ? 3.5 : 0.5))
                arrow.lineWidth = 0.8
                NSColor(white: 0.35, alpha: 1).setStroke()
                arrow.stroke()
            }
            x += w
            NSColor(229, 229, 229).setFill()
            NSRect(x: x - 1, y: 0, width: 1, height: bounds.height).fill()
        }
    }

    private func edge(at px: CGFloat) -> Int? {
        var x = -offset
        for column in DirColumn.allCases {
            x += list.widths[column.rawValue]
            if abs(px - x) < 4 { return column.rawValue }
        }
        return nil
    }

    private func column(at px: CGFloat) -> DirColumn? {
        var x = -offset
        for column in DirColumn.allCases {
            x += list.widths[column.rawValue]
            if px < x { return column }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        resizing = edge(at: p.x)
        if resizing == nil, let c = column(at: p.x) { list.sort(by: c) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = resizing else { return }
        let p = convert(event.locationInWindow, from: nil)
        let start = list.widths[..<index].reduce(-offset, +)
        list.widths[index] = max(30, p.x - start)
        list.fit()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { resizing = nil }

    override func resetCursorRects() {
        var x = -offset
        for column in DirColumn.allCases {
            x += list.widths[column.rawValue]
            addCursorRect(NSRect(x: x - 3, y: 0, width: 6, height: bounds.height), cursor: .resizeLeftRight)
        }
    }
}

/// Сам список: дерево или плоский перечень, рисуется вручную.
final class DirList: NSView {
    unowned let host: FolderCompareView
    struct Row { let item: FolderItem; let depth: Int }
    private(set) var rows: [Row] = []
    var widths: [CGFloat] = DirColumn.allCases.map { $0.defaultWidth }
    private(set) var selected = Set<Int>()
    private(set) var focused: Int?
    private var pivot: Int?
    private var expanded = Set<String>()
    private var source: [FolderItem] = []
    private(set) var sortColumn: DirColumn = .name
    private(set) var sortAscending = true
    let rowH: CGFloat = 16
    private static let dates: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    init(host: FolderCompareView) {
        self.host = host
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    var selectedItems: [FolderItem] { selected.sorted().compactMap { $0 < rows.count ? rows[$0].item : nil } }
    private var tree: Bool { host.recursive && ViewFlag.treeMode.isOn }

    // MARK: Состав строк

    private func visible(_ item: FolderItem) -> Bool {
        if item.isDirectory {
            if !(item.existsLeft && item.existsRight) { return item.existsLeft ? ViewFlag.showLeftOnly.isOn : ViewFlag.showRightOnly.isOn }
            return !host.recursive || item.children.contains(where: visible) || (item.children.isEmpty && ViewFlag.showIdentical.isOn)
        }
        switch item.result {
        case .identical, .binaryIdentical: return ViewFlag.showIdentical.isOn
        case .different, .binaryDifferent, .error: return ViewFlag.showDifferent.isOn
        case .leftOnly: return ViewFlag.showLeftOnly.isOn
        case .rightOnly: return ViewFlag.showRightOnly.isOn
        default: return true
        }
    }

    private func value(_ item: FolderItem, _ column: DirColumn) -> String {
        func date(_ d: Date?, newer: Bool) -> String { d.map { (newer ? "* " : "") + DirList.dates.string(from: $0) } ?? "" }
        switch column {
        case .name: return item.name
        case .folder: return item.folder
        case .result: return host.resultText(item)
        case .leftDate: return date(item.leftDate, newer: item.rightDate.map { r in item.leftDate.map { $0 > r } ?? false } ?? (item.leftDate != nil))
        case .rightDate: return date(item.rightDate, newer: item.leftDate.map { l in item.rightDate.map { $0 > l } ?? false } ?? (item.rightDate != nil))
        case .ext: return item.ext
        }
    }

    private func sorted(_ list: [FolderItem]) -> [FolderItem] {
        func less(_ a: FolderItem, _ b: FolderItem) -> Bool {
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let order: ComparisonResult
            switch sortColumn {
            case .leftDate: order = (a.leftDate ?? .distantPast).compare(b.leftDate ?? .distantPast)
            case .rightDate: order = (a.rightDate ?? .distantPast).compare(b.rightDate ?? .distantPast)
            default: order = value(a, sortColumn).localizedStandardCompare(value(b, sortColumn))
            }
            if order == .orderedSame { return a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending }
            return sortAscending ? order == .orderedAscending : order == .orderedDescending
        }
        return list.sorted(by: less)
    }

    func rebuild(_ items: [FolderItem]) {
        source = items
        let keep = Set(selectedItems.map { $0.relativePath + ($0.isDirectory ? "/" : "") })
        rows = []
        if tree {
            func walk(_ list: [FolderItem], _ depth: Int) {
                for item in sorted(list) where visible(item) {
                    rows.append(Row(item: item, depth: depth))
                    if item.isDirectory, expanded.contains(item.relativePath) { walk(item.children, depth + 1) }
                }
            }
            walk(items, 0)
        } else {
            var flat: [FolderItem] = []
            func walk(_ list: [FolderItem]) {
                for item in list {
                    if item.isDirectory && host.recursive {
                        if !(item.existsLeft && item.existsRight) { flat.append(item) } else { walk(item.children) }
                    } else { flat.append(item) }
                }
            }
            walk(items)
            rows = sorted(flat.filter(visible)).map { Row(item: $0, depth: 0) }
        }
        selected = Set(rows.indices.filter { keep.contains(rows[$0].item.relativePath + (rows[$0].item.isDirectory ? "/" : "")) })
        focused = selected.min()
        fit()
        needsDisplay = true
    }

    func fit() {
        let w = max(widths.reduce(0, +) + 20, host.bounds.width - 16)
        let h = max(CGFloat(rows.count) * rowH + 4, enclosingScrollView?.contentSize.height ?? 0)
        setFrameSize(NSSize(width: w, height: h))
        needsDisplay = true
    }

    func sort(by column: DirColumn) {
        if sortColumn == column { sortAscending.toggle() } else {
            sortColumn = column
            sortAscending = !(column == .leftDate || column == .rightDate)
        }
        rebuild(source)
    }

    func toggle(_ item: FolderItem) {
        if expanded.contains(item.relativePath) { expanded.remove(item.relativePath) } else { expanded.insert(item.relativePath) }
        rebuild(source)
    }

    func expandAll(_ items: [FolderItem]) {
        func walk(_ list: [FolderItem]) { for i in list where i.isDirectory { expanded.insert(i.relativePath); walk(i.children) } }
        walk(items)
        rebuild(source)
    }

    func collapseAll() {
        expanded.removeAll()
        rebuild(source)
    }

    // MARK: Выделение

    func select(row: Int, extend: Bool = false, toggle: Bool = false) {
        guard row >= 0, row < rows.count else { return }
        if extend, let pivot { selected = Set(min(pivot, row)...max(pivot, row)) } else if toggle {
            if selected.contains(row) { selected.remove(row) } else { selected.insert(row) }
            pivot = row
        } else {
            selected = [row]
            pivot = row
        }
        focused = row
        scrollToVisible(NSRect(x: visibleRect.minX, y: CGFloat(row) * rowH, width: 10, height: rowH))
        needsDisplay = true
        host.updateStatus()
    }

    func selectAll() {
        selected = Set(rows.indices)
        needsDisplay = true
        host.updateStatus()
    }

    func differentRow(after row: Int) -> Int? {
        rows.indices.first { $0 > row && !rows[$0].item.isDirectory && rows[$0].item.isDifferent }
            ?? rows.indices.first { $0 > row && rows[$0].item.isDifferent }
    }

    func differentRow(before row: Int) -> Int? {
        rows.indices.last { $0 < row && !rows[$0].item.isDirectory && rows[$0].item.isDifferent }
            ?? rows.indices.last { $0 < row && rows[$0].item.isDifferent }
    }

    // MARK: Рисование

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        let first = max(0, Int(dirtyRect.minY / rowH)), last = min(rows.count - 1, Int(dirtyRect.maxY / rowH))
        guard first <= last else { return }
        let total = widths.reduce(0, +)
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: NSColor.black, .paragraphStyle: p]
        let isTree = tree
        for index in first...last {
            let row = rows[index]
            let item = row.item
            let y = CGFloat(index) * rowH
            let indent = isTree ? CGFloat(row.depth) * 11 + 15 : 3
            let textX = indent + 18
            // Цвет строки начинается от названия: значок и стрелка дерева остаются на белом.
            let color: NSColor?
            if selected.contains(index) { color = window?.firstResponder === self ? NSColor(204, 232, 255) : NSColor(240, 240, 240) }
            else if !(item.existsLeft && item.existsRight) { color = Theme.dirMissing }
            else if item.isDifferent { color = Theme.dirDifferent } else { color = nil }
            if let color {
                color.setFill()
                NSRect(x: textX - 2, y: y, width: total - textX + 2, height: rowH).fill()
            }
            if isTree, item.isDirectory {
                let open = expanded.contains(item.relativePath)
                let c = NSBezierPath()
                let cx = indent - 8, cy = y + rowH / 2
                if open {
                    c.move(to: NSPoint(x: cx - 3, y: cy - 1.5)); c.line(to: NSPoint(x: cx, y: cy + 1.5)); c.line(to: NSPoint(x: cx + 3, y: cy - 1.5))
                } else {
                    c.move(to: NSPoint(x: cx - 1.5, y: cy - 3)); c.line(to: NSPoint(x: cx + 1.5, y: cy)); c.line(to: NSPoint(x: cx - 1.5, y: cy + 3))
                }
                c.lineWidth = 1
                NSColor(white: open ? 0.25 : 0.55, alpha: 1).setStroke()
                c.stroke()
            }
            host.glyph(item).image(size: 14).draw(in: NSRect(x: indent + 1, y: y + 1, width: 14, height: 14), from: .zero,
                                                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            var x: CGFloat = 0
            for column in DirColumn.allCases {
                let w = widths[column.rawValue]
                let left = column == .name ? textX : x + 4
                let r = NSRect(x: left, y: y + 0.5, width: x + w - left - 3, height: rowH)
                if r.width > 4 { (value(item, column) as NSString).draw(in: r, withAttributes: attrs) }
                x += w
            }
        }
    }

    // MARK: Мышь и клавиши

    private func row(at event: NSEvent) -> (Int, CGFloat)? {
        let p = convert(event.locationInWindow, from: nil)
        let index = Int(p.y / rowH)
        return index >= 0 && index < rows.count ? (index, p.x) : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let (index, x) = row(at: event) else {
            selected = []; focused = nil; needsDisplay = true; host.updateStatus()
            return
        }
        let row = rows[index]
        if tree, row.item.isDirectory, x < CGFloat(row.depth) * 11 + 15 { toggle(row.item); return }
        select(row: index, extend: event.modifierFlags.contains(.shift), toggle: event.modifierFlags.contains(.command))
        if event.clickCount == 2 { host.open(row.item) }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let (index, _) = row(at: event), !selected.contains(index) { select(row: index) }
        NSMenu.popUpContextMenu(host.contextMenu(), with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return }
        let shift = event.modifierFlags.contains(.shift)
        let current = focused ?? -1
        let page = max(1, Int((enclosingScrollView?.contentSize.height ?? 200) / rowH) - 1)
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: select(row: max(0, current - 1), extend: shift)
        case NSDownArrowFunctionKey: select(row: min(rows.count - 1, current + 1), extend: shift)
        case NSPageUpFunctionKey: select(row: max(0, current - page), extend: shift)
        case NSPageDownFunctionKey: select(row: min(rows.count - 1, current + page), extend: shift)
        case NSHomeFunctionKey: select(row: 0, extend: shift)
        case NSEndFunctionKey: select(row: rows.count - 1, extend: shift)
        case NSRightArrowFunctionKey:
            if tree, current >= 0, rows[current].item.isDirectory, !expanded.contains(rows[current].item.relativePath) { toggle(rows[current].item) }
        case NSLeftArrowFunctionKey:
            if tree, current >= 0, rows[current].item.isDirectory, expanded.contains(rows[current].item.relativePath) { toggle(rows[current].item) }
        case 13, 3: if current >= 0 { host.open(rows[current].item) }
        case 127, NSDeleteFunctionKey: host.delete(side: 2)
        case 27: MainWindowController.shared.run(.close)
        default: super.keyDown(with: event)
        }
    }
}
