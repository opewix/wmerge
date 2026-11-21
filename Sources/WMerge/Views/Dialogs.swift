import AppKit

/// Что ищем: строка, настройки и на что заменять.
struct FindQuery {
    var pattern = ""
    var replacement = ""
    var matchCase = false
    var wholeWord = false
    var isRegex = false
    var wrap = true

    static var last = FindQuery()

    var regex: NSRegularExpression? {
        guard !pattern.isEmpty else { return nil }
        var p = isRegex ? pattern : NSRegularExpression.escapedPattern(for: pattern)
        if wholeWord { p = "\\b" + p + "\\b" }
        return try? NSRegularExpression(pattern: p, options: matchCase ? [] : [.caseInsensitive])
    }

    var template: String { isRegex ? replacement : NSRegularExpression.escapedTemplate(for: replacement) }
}

/// Небольшое модальное окно с ручной раскладкой — основа диалогов.
class DialogPanel: NSObject, NSWindowDelegate {
    let panel: NSPanel
    var content: NSView { panel.contentView! }

    init(title: String, width: CGFloat, height: CGFloat) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title
        super.init()
        panel.delegate = self
        panel.contentView = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        view.frame = NSRect(x: x, y: y, width: w, height: h)
        content.addSubview(view)
    }

    func run() {
        panel.center()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) { NSApp.stopModal() }
    @objc func cancel() { panel.close() }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Edit → Find... и Replace...
final class FindDialog: DialogPanel {
    private unowned let view: FileCompareView
    private let what = NSComboBox()
    private let with = NSTextField()
    private var checks: [NSButton] = []
    private static var history: [String] = []
    private static var current: FindDialog?

    static func show(for view: FileCompareView, replace: Bool) {
        let dialog = FindDialog(view: view, replace: replace)
        current = dialog
        dialog.run()
        current = nil
    }

    private init(view: FileCompareView, replace: Bool) {
        self.view = view
        super.init(title: replace ? "Replace" : "Find", width: 430, height: replace ? 176 : 150)
        place(UI.label("Find what:"), 12, 15, 90, 17)
        what.addItems(withObjectValues: FindDialog.history)
        what.stringValue = FindQuery.last.pattern
        place(what, 104, 11, 210, 24)
        var y: CGFloat = 44
        if replace {
            place(UI.label("Replace with:"), 12, 47, 90, 17)
            with.stringValue = FindQuery.last.replacement
            place(with, 104, 44, 207, 22)
            y = 76
        }
        let q = FindQuery.last
        for (i, (title, on)) in [("Match whole word only", q.wholeWord), ("Match case", q.matchCase),
                                 ("Regular expression", q.isRegex), ("Don't wrap end of file", !q.wrap)].enumerated() {
            let c = UI.check(title, on: on)
            checks.append(c)
            place(c, 12, y + CGFloat(i) * 21, 220, 18)
        }
        let find = UI.button("Find Next", target: self, action: #selector(findNext), key: "\r")
        place(find, 322, 8, 100, 28)
        if replace {
            place(UI.button("Replace", target: self, action: #selector(replaceOne)), 322, 38, 100, 28)
            place(UI.button("Replace All", target: self, action: #selector(replaceAll)), 322, 68, 100, 28)
            place(UI.button("Cancel", target: self, action: #selector(cancel), key: "\u{1b}"), 322, 98, 100, 28)
        } else {
            place(UI.button("Find Previous", target: self, action: #selector(findPrevious)), 322, 38, 100, 28)
            place(UI.button("Cancel", target: self, action: #selector(cancel), key: "\u{1b}"), 322, 68, 100, 28)
        }
        panel.initialFirstResponder = what
    }

    private func query() -> FindQuery {
        var q = FindQuery()
        q.pattern = what.stringValue
        q.replacement = with.stringValue
        q.wholeWord = checks[0].state == .on
        q.matchCase = checks[1].state == .on
        q.isRegex = checks[2].state == .on
        q.wrap = checks[3].state != .on
        FindQuery.last = q
        if !q.pattern.isEmpty, !FindDialog.history.contains(q.pattern) { FindDialog.history.insert(q.pattern, at: 0) }
        return q
    }

    @objc private func findNext() { if view.find(query()) && with.superview == nil { panel.close() } }
    @objc private func findPrevious() { if view.find(query(), backward: true) { panel.close() } }
    @objc private func replaceOne() { view.replaceCurrent(query()) }

    @objc private func replaceAll() {
        let n = view.replaceAll(query())
        UI.alert("\(n) replacement(s) made.")
    }
}

/// Edit → Go to...
final class GoToDialog: DialogPanel {
    private unowned let view: FileCompareView
    private let field = NSTextField()
    private var fileRadios: [NSButton] = []
    private var whatRadios: [NSButton] = []

    static func show(for view: FileCompareView) {
        GoToDialog(view: view).run()
    }

    private init(view: FileCompareView) {
        self.view = view
        super.init(title: "Go to", width: 330, height: 150)
        place(UI.label("Go to:"), 12, 15, 50, 17)
        field.stringValue = String(view.caretLine)
        place(field, 64, 12, 150, 22)
        place(UI.label("File"), 12, 46, 100, 17)
        place(UI.label("Go to what"), 150, 46, 100, 17)
        for (i, title) in ["Left", "Right"].enumerated() {
            let r = UI.radio(title, on: i == view.activeSide, target: self, action: #selector(pickFile(_:)))
            fileRadios.append(r)
            place(r, 20, 68 + CGFloat(i) * 22, 100, 18)
        }
        for (i, title) in ["Line", "Difference"].enumerated() {
            let r = UI.radio(title, on: i == 0, target: self, action: #selector(pickWhat(_:)))
            whatRadios.append(r)
            place(r, 158, 68 + CGFloat(i) * 22, 110, 18)
        }
        place(UI.button("OK", target: self, action: #selector(ok), key: "\r"), 232, 8, 90, 28)
        place(UI.button("Cancel", target: self, action: #selector(cancel), key: "\u{1b}"), 232, 38, 90, 28)
        panel.initialFirstResponder = field
    }

    @objc private func pickFile(_ sender: NSButton) { fileRadios.forEach { $0.state = $0 === sender ? .on : .off } }
    @objc private func pickWhat(_ sender: NSButton) { whatRadios.forEach { $0.state = $0 === sender ? .on : .off } }

    @objc private func ok() {
        let n = max(1, field.integerValue)
        panel.close()
        if whatRadios[1].state == .on { view.goTo(difference: n) } else { view.goTo(line: n, side: fileRadios[1].state == .on ? 1 : 0) }
    }
}

/// Edit → Options...: дерево страниц слева, страница справа, как в WinMerge.
final class OptionsDialog: DialogPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let pages = ["General", "Compare", "Editor"]
    private let list = NSTableView()
    private var pageViews: [NSView] = []
    private var whitespace: [NSButton] = []
    private var ignores: [NSButton] = []
    private let tabSize = NSTextField()
    private let fontSize = NSTextField()
    private let language = NSPopUpButton()
    private var viewChecks: [(NSButton, ViewFlag)] = []
    private var saved = false

    /// Показывает окно; true — настройки изменены.
    static func show() -> Bool {
        let d = OptionsDialog()
        d.run()
        return d.saved
    }

    private init() {
        super.init(title: "Options", width: 600, height: 380)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = 130
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self
        list.delegate = self
        list.rowHeight = 19
        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        place(scroll, 10, 10, 150, 320)

        let options = CompareOptions.current
        // General
        let general = FlippedView(frame: NSRect(x: 170, y: 10, width: 420, height: 320))
        general.addSubview(titled("General", in: general))
        add(UI.label("Language:"), to: general, 8, 36, 80, 17)
        language.addItems(withTitles: ["English", "Русский"])
        language.selectItem(at: L.isRussian ? 1 : 0)
        add(language, to: general, 90, 32, 160, 24)
        add(UI.label("The language changes after WMerge is restarted.", size: 11), to: general, 8, 62, 400, 15)
        // Compare
        let compare = FlippedView(frame: general.frame)
        compare.addSubview(titled("Compare", in: compare))
        add(UI.label("Whitespaces"), to: compare, 8, 34, 200, 17)
        for (i, title) in ["Compare", "Ignore change", "Ignore all"].enumerated() {
            let r = UI.radio(title, on: options.whitespace.rawValue == i, target: self, action: #selector(pickWhitespace(_:)))
            whitespace.append(r)
            add(r, to: compare, 20, 56 + CGFloat(i) * 21, 200, 18)
        }
        for (i, (title, on)) in [("Ignore blank lines", options.ignoreBlankLines), ("Ignore case", options.ignoreCase),
                                 ("Ignore EOL differences (Windows/Unix/Mac)", options.ignoreEOL)].enumerated() {
            let c = UI.check(title, on: on)
            ignores.append(c)
            add(c, to: compare, 8, 128 + CGFloat(i) * 22, 380, 18)
        }
        // Editor
        let editor = FlippedView(frame: general.frame)
        editor.addSubview(titled("Editor", in: editor))
        add(UI.label("Tab size:"), to: editor, 8, 37, 80, 17)
        tabSize.integerValue = Theme.tabSize
        add(tabSize, to: editor, 90, 34, 50, 22)
        add(UI.label("Font size:"), to: editor, 8, 65, 80, 17)
        fontSize.integerValue = Int(Theme.editorFontSize)
        add(fontSize, to: editor, 90, 62, 50, 22)
        for (i, (title, flag)) in [("View Line Differences", ViewFlag.lineDiff), ("Word-level line differences", .wordLevel),
                                   ("View Line Numbers", .lineNumbers), ("View Margins", .margin), ("View Whitespace", .whitespace)].enumerated() {
            let c = UI.check(title, on: flag.isOn)
            viewChecks.append((c, flag))
            add(c, to: editor, 8, 98 + CGFloat(i) * 22, 300, 18)
        }
        pageViews = [general, compare, editor]
        pageViews.forEach { content.addSubview($0); $0.isHidden = true }
        pageViews[0].isHidden = false
        list.selectRowIndexes([0], byExtendingSelection: false)

        place(UI.button("OK", target: self, action: #selector(ok), key: "\r"), 396, 342, 94, 28)
        place(UI.button("Cancel", target: self, action: #selector(cancel), key: "\u{1b}"), 496, 342, 94, 28)
    }

    private func titled(_ title: String, in view: NSView) -> NSView {
        let label = UI.label(title, bold: true, size: 13)
        label.frame = NSRect(x: 8, y: 4, width: 300, height: 18)
        return label
    }

    private func add(_ v: NSView, to parent: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        v.frame = NSRect(x: x, y: y, width: w, height: h)
        parent.addSubview(v)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = UI.label(pages[row])
        label.frame = NSRect(x: 4, y: 1, width: 120, height: 17)
        cell.addSubview(label)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        for (i, v) in pageViews.enumerated() { v.isHidden = i != list.selectedRow }
    }

    @objc private func pickWhitespace(_ sender: NSButton) { whitespace.forEach { $0.state = $0 === sender ? .on : .off } }

    @objc private func ok() {
        var o = CompareOptions.current
        o.whitespace = CompareOptions.Whitespace(rawValue: whitespace.firstIndex { $0.state == .on } ?? 0) ?? .compare
        o.ignoreBlankLines = ignores[0].state == .on
        o.ignoreCase = ignores[1].state == .on
        o.ignoreEOL = ignores[2].state == .on
        o.save()
        let d = UserDefaults.standard
        d.set(min(max(tabSize.integerValue, 1), 16), forKey: "editor.tabSize")
        d.set(Double(min(max(fontSize.integerValue, 6), 40)), forKey: "editor.fontSize")
        d.set(language.indexOfSelectedItem == 1 ? "ru" : "en", forKey: L.languageKey)
        for (check, flag) in viewChecks { flag.set(check.state == .on) }
        saved = true
        panel.close()
    }
}

enum About {
    static func show() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        UI.alert("WMerge \(version)",
                 info: L.t("Сравнение и слияние файлов и папок в духе WinMerge.\n\nНезависимая программа; с проектом WinMerge не связана и его кода не содержит.",
                           "File and folder compare and merge in the spirit of WinMerge.\n\nAn independent app, not affiliated with the WinMerge project; it contains none of its code."))
    }
}
