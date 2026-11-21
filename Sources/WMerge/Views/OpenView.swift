import AppKit

/// Вкладка «Select Files or Folders»: что с чем сравнивать. Раскладка — как в WinMerge.
final class OpenView: NSView, DocumentTab {
    private let logo = LogoView()
    private let help = WinButton("Help")
    private let options = WinButton("Options...")
    private var groups: [WinGroup] = []
    private var combos: [WinCombo] = []
    private var readOnly: [WinCheck] = []
    private var swaps: [WinButton] = []
    private var swapLabels: [NSTextField] = []
    private var browse: [WinButton] = []
    private let filterGroup = WinGroup("Folder: Filter")
    private let filter = WinCombo()
    private let filterSelect = WinButton("Select...")
    private let subfolders = WinCheck("Include Subfolders", on: ViewFlag.includeSubfolders.isOn)
    private let pluginGroup = WinGroup("File: Unpacker Plugin")
    private let plugin = WinCombo()
    private let pluginSelect = WinButton("Select...")
    private let saveProject = WinButton("Save Project...")
    private let compare = WinButton("Compare", isDefault: true)
    private let cancel = WinButton("Cancel")
    private let statusLine = NSTextField(labelWithString: "")
    private static let prompt = "Select two (or three) folders or two (or three) files to compare."

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 542, height: 378))
        addSubview(logo)
        addSubview(help)
        addSubview(options)
        help.onClick = { MainWindowController.shared.run(.help) }
        options.onClick = { MainWindowController.shared.run(.options) }
        options.onArrow = { button in
            MainWindowController.shared.optionsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        }
        let titles = ["1st File or Folder", "2nd File or Folder", "3rd File or Folder (Optional)"]
        let swapTitles = ["Swap 1st | 2nd", "Swap 2nd | 3rd", "Swap 1st | 3rd"]
        let pairs = [(0, 1), (1, 2), (0, 2)]
        for i in 0..<3 {
            let group = WinGroup(titles[i])
            groups.append(group)
            addSubview(group)
            let combo = WinCombo()
            combo.items = UserDefaults.standard.stringArray(forKey: "open.history\(i)") ?? []
            combo.onChange = { [unowned self] in self.validate() }
            combos.append(combo)
            addSubview(combo)
            let check = WinCheck("Read-only")
            readOnly.append(check)
            addSubview(check)
            let swap = WinButton("⇕")
            swap.onClick = { [unowned self] in
                let (a, b) = pairs[i]
                let t = self.combos[a].field.stringValue
                self.combos[a].field.stringValue = self.combos[b].field.stringValue
                self.combos[b].field.stringValue = t
                self.validate()
            }
            swaps.append(swap)
            addSubview(swap)
            let label = UI.label(swapTitles[i])
            swapLabels.append(label)
            addSubview(label)
            let button = WinButton("Browse...")
            button.onClick = { [unowned self] in self.pick(i) }
            browse.append(button)
            addSubview(button)
        }
        if combos[0].items.first != nil, combos[1].items.first != nil {
            combos[0].field.stringValue = combos[0].items[0]
            combos[1].field.stringValue = combos[1].items[0]
        }
        addSubview(filterGroup)
        filter.items = ["*.*"] + (UserDefaults.standard.stringArray(forKey: "open.filters") ?? [])
        filter.field.stringValue = UserDefaults.standard.string(forKey: "open.filter") ?? "*.*"
        addSubview(filter)
        addSubview(filterSelect)
        filterSelect.onClick = { [unowned self] in
            UI.alert("File filters", info: "Type masks separated by semicolons, for example *.cpp;*.h — an exclamation mark excludes: !*.obj")
            self.window?.makeFirstResponder(self.filter.field)
        }
        addSubview(subfolders)
        subfolders.onChange = { ViewFlag.includeSubfolders.set($0) }
        pluginGroup.enabled = false
        addSubview(pluginGroup)
        plugin.field.stringValue = "<None>"
        plugin.enabled = false
        addSubview(plugin)
        pluginSelect.enabled = false
        addSubview(pluginSelect)
        addSubview(saveProject)
        saveProject.onClick = { UI.alert("Project files are not supported in this version.") }
        saveProject.onArrow = { _ in UI.alert("Project files are not supported in this version.") }
        addSubview(compare)
        compare.onClick = { [unowned self] in self.run() }
        addSubview(cancel)
        cancel.onClick = { MainWindowController.shared.run(.close) }
        statusLine.font = Theme.uiFont
        statusLine.textColor = .black
        addSubview(statusLine)
        registerForDraggedTypes([.fileURL])
        validate()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width
        logo.frame = NSRect(x: 8, y: 4, width: 270, height: 58)
        help.frame = NSRect(x: w - 95, y: 14, width: 83, height: 18)
        options.frame = NSRect(x: w - 95, y: 39, width: 83, height: 18)
        for i in 0..<3 {
            let y = 75 + CGFloat(i) * 64
            groups[i].frame = NSRect(x: 7, y: y, width: w - 12, height: 57)
            combos[i].frame = NSRect(x: 12, y: y + 14, width: w - 22, height: 19)
            readOnly[i].frame = NSRect(x: 19, y: y + 37, width: 110, height: 16)
            swaps[i].frame = NSRect(x: 141, y: y + 36, width: 16, height: 17)
            swapLabels[i].frame = NSRect(x: 161, y: y + 37, width: 140, height: 16)
            browse[i].frame = NSRect(x: w - 95, y: y + 36, width: 84, height: 17)
        }
        let y: CGFloat = 267
        let half = floor(w / 2)
        filterGroup.frame = NSRect(x: 7, y: y, width: half - 10, height: 51)
        filter.frame = NSRect(x: 12, y: y + 12, width: half - 108, height: 19)
        filterSelect.frame = NSRect(x: half - 92, y: y + 13, width: 84, height: 17)
        subfolders.frame = NSRect(x: 19, y: y + 34, width: 180, height: 16)
        pluginGroup.frame = NSRect(x: half + 4, y: y, width: w - half - 9, height: 51)
        plugin.frame = NSRect(x: half + 9, y: y + 12, width: w - half - 110, height: 19)
        pluginSelect.frame = NSRect(x: w - 95, y: y + 13, width: 84, height: 17)
        saveProject.frame = NSRect(x: 13, y: 327, width: 104, height: 18)
        compare.frame = NSRect(x: w - 136, y: 327, width: 62, height: 25)
        cancel.frame = NSRect(x: w - 69, y: 327, width: 62, height: 25)
        statusLine.frame = NSRect(x: 7, y: bounds.height - 16, width: w - 14, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 67).fill()
        NSColor(218, 218, 218).setFill()
        NSRect(x: 0, y: bounds.height - 18, width: bounds.width, height: 1).fill()
    }

    // MARK: Проверка и запуск

    private func path(_ i: Int) -> String {
        let raw = combos[i].field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return "" }
        let expanded = (raw as NSString).expandingTildeInPath
        return expanded.count > 1 && expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded
    }

    /// nil — пути нет, true — папка, false — файл.
    private func kind(_ i: Int) -> Bool? {
        var isDir: ObjCBool = false
        guard !path(i).isEmpty, FileManager.default.fileExists(atPath: path(i), isDirectory: &isDir) else { return nil }
        return isDir.boolValue
    }

    private func validate() {
        let a = kind(0), b = kind(1)
        for i in 0..<3 { combos[i].glyph = kind(i).map { $0 ? .folderPlain : .filePlain } }
        let folders = a == true && b == true, files = a == false && b == false
        var message = OpenView.prompt
        // Незаполненное поле — ещё не ошибка: остаётся подсказка.
        if !path(0).isEmpty && !path(1).isEmpty {
            if a == nil && b == nil { message = "Both paths are invalid!" } else if a == nil { message = "Left (1st) path is invalid!" } else if b == nil {
                message = "Right (2nd) path is invalid!"
            } else if !folders && !files { message = "Select two existing folders/files to compare." }
        }
        statusLine.stringValue = message
        compare.enabled = folders || files
        // Фильтр — для папок, распаковщик — для файлов; как в оригинале, лишнее сереет.
        filter.enabled = !files
        filterSelect.enabled = !files
        filterGroup.enabled = !files
        filterGroup.needsDisplay = true
    }

    private func pick(_ i: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !path(i).isEmpty { panel.directoryURL = URL(fileURLWithPath: path(i)).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        combos[i].text = url.path
    }

    func setPaths(_ left: String?, _ right: String?) {
        if let left { combos[0].field.stringValue = left }
        if let right { combos[1].field.stringValue = right }
        validate()
    }

    /// Поля заново: слева — заданный путь или пусто, остальные пустые (прежние значения остаются в списках).
    func reset(left: String?) {
        combos[0].field.stringValue = left ?? ""
        combos[1].field.stringValue = ""
        combos[2].field.stringValue = ""
        validate()
        window?.makeFirstResponder(combos[left == nil ? 0 : 1].field)
    }

    private func remember() {
        let d = UserDefaults.standard
        for i in 0..<3 where !path(i).isEmpty {
            var history = combos[i].items.filter { $0 != combos[i].field.stringValue }
            history.insert(combos[i].field.stringValue, at: 0)
            combos[i].items = Array(history.prefix(20))
            d.set(combos[i].items, forKey: "open.history\(i)")
        }
        d.set(filter.field.stringValue, forKey: "open.filter")
        if filter.field.stringValue != "*.*" {
            var filters = (d.stringArray(forKey: "open.filters") ?? []).filter { $0 != filter.field.stringValue }
            filters.insert(filter.field.stringValue, at: 0)
            d.set(Array(filters.prefix(10)), forKey: "open.filters")
        }
    }

    private func run() {
        guard compare.enabled, let folders = kind(0) else { return }
        if !path(2).isEmpty {
            UI.alert("Three-way comparison is not supported in this version.", info: "The 1st and the 2nd items will be compared.")
        }
        remember()
        let main = MainWindowController.shared
        let left = path(0), right = path(1)
        let ro = (readOnly[0].on, readOnly[1].on)
        if folders {
            main.openFolders(left, right, recursive: subfolders.on, mask: filter.field.stringValue, replacing: self)
        } else {
            main.openFiles(left, right, readOnly: ro, replacing: self)
        }
    }

    // MARK: Перетаскивание

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        if urls.count >= 2 { setPaths(urls[0].path, urls[1].path) } else if path(0).isEmpty || !path(1).isEmpty { setPaths(urls[0].path, nil) } else {
            setPaths(nil, urls[0].path)
        }
        return true
    }

    // MARK: Вкладка

    var tabTitle: String { "Select Files or Folders" }
    var tabGlyph: Glyph { .tabOpen }
    var statusRight: String { "" }
    func isEnabled(_ cmd: Cmd) -> Bool { cmd == .compare ? compare.enabled : false }
    func isChecked(_ cmd: Cmd) -> Bool { false }
    func perform(_ cmd: Cmd) { if cmd == .compare { run() } }
    func canClose() -> Bool { true }
    func activated() { window?.makeFirstResponder(combos[0].field) }
    func settingsChanged() { subfolders.on = ViewFlag.includeSubfolders.isOn }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { MainWindowController.shared.run(.close) } else if event.keyCode == 36 { run() } else { super.keyDown(with: event) }
    }
}

/// Название программы на месте логотипа: крупные буквы с отражением.
private final class LogoView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont(name: "Arial Rounded MT Bold", size: 44) ?? NSFont.systemFont(ofSize: 44, weight: .heavy)
        func text(_ alpha: CGFloat) -> NSAttributedString {
            let s = NSMutableAttributedString(string: "WMerge", attributes: [.font: font, .kern: -1.0])
            s.addAttribute(.foregroundColor, value: NSColor(40, 40, 40).withAlphaComponent(alpha), range: NSRange(location: 0, length: 1))
            s.addAttribute(.foregroundColor, value: NSColor(138, 12, 12).withAlphaComponent(alpha), range: NSRange(location: 1, length: 5))
            return s
        }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowOffset = NSSize(width: 1.5, height: -1.5)
        shadow.shadowBlurRadius = 2
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        text(1).draw(at: NSPoint(x: 6, y: -2))
        NSGraphicsContext.restoreGraphicsState()
        // Блик по верхней половине букв.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 24)).addClip()
        let gloss = NSMutableAttributedString(attributedString: text(1))
        gloss.addAttribute(.foregroundColor, value: NSColor(white: 1, alpha: 0.22), range: NSRange(location: 0, length: 6))
        gloss.draw(at: NSPoint(x: 6, y: -2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
