import AppKit

/// Панель инструментов: тот же набор и порядок кнопок, что в WinMerge; недоступные — серые.
final class ToolbarView: NSView {
    private enum Item { case button(Glyph, Cmd, String, Bool), separator }
    private let items: [Item] = [
        .button(.new, .newText, "New Documents (Ctrl+N)", true),
        .button(.open, .open, "Open (Ctrl+O)", true),
        .button(.save, .save, "Save (Ctrl+S)", true), .separator,
        .button(.undo, .undo, "Undo (Ctrl+Z)", false),
        .button(.redo, .redo, "Redo (Ctrl+Y)", false), .separator,
        .button(.lineDiff, .selectLineDiff, "Difference in Current Line (F4)", false), .separator,
        .button(.nextDiff, .nextDiff, "Next Difference (Alt+Down)", false),
        .button(.prevDiff, .prevDiff, "Previous Difference (Alt+Up)", false), .separator,
        .button(.nextConflict, .nextConflict, "Next Conflict (Alt+Shift+Down)", false),
        .button(.prevConflict, .prevConflict, "Previous Conflict (Alt+Shift+Up)", false), .separator,
        .button(.firstDiff, .firstDiff, "First Difference (Alt+Home)", false),
        .button(.currentDiff, .currentDiff, "Current Difference (Alt+Enter)", false),
        .button(.lastDiff, .lastDiff, "Last Difference (Alt+End)", false), .separator,
        .button(.copyRight, .copyRight, "Copy to Right (Alt+Right)", false),
        .button(.copyLeft, .copyLeft, "Copy to Left (Alt+Left)", false), .separator,
        .button(.copyRightAdvance, .copyRightAdvance, "Copy to Right and Advance (Ctrl+Alt+Right)", false),
        .button(.copyLeftAdvance, .copyLeftAdvance, "Copy to Left and Advance (Ctrl+Alt+Left)", false), .separator,
        .button(.allRight, .allRight, "Copy All to Right", false),
        .button(.allLeft, .allLeft, "Copy All to Left", false), .separator,
        .button(.autoMerge, .autoMerge, "Auto Merge (Ctrl+Alt+M)", false), .separator,
        .button(.firstFile, .firstFile, "First File", false),
        .button(.prevFile, .prevFile, "Previous File (Ctrl+F7)", false),
        .button(.nextFile, .nextFile, "Next File (Ctrl+F8)", false),
        .button(.lastFile, .lastFile, "Last File", false), .separator,
        .button(.options, .options, "Options", true), .separator,
        .button(.refresh, .refresh, "Refresh (F5)", false), .separator,
    ]
    static let height: CGFloat = 27
    private struct Slot { let rect: NSRect; let arrow: NSRect?; let glyph: Glyph; let cmd: Cmd }
    private var slots: [Slot] = []
    private var separators: [CGFloat] = []
    private var hover: Int?
    private var hoverArrow = false
    private var pressed: Int?
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        var x: CGFloat = 9
        for item in items {
            switch item {
            case .separator:
                separators.append(x + 3)
                x += 8
            case let .button(glyph, cmd, tip, dropdown):
                let rect = NSRect(x: x, y: 2, width: 24, height: 23)
                let arrow = dropdown ? NSRect(x: x + 24, y: 2, width: 12, height: 23) : nil
                slots.append(Slot(rect: rect, arrow: arrow, glyph: glyph, cmd: cmd))
                addToolTip(rect.union(arrow ?? rect), owner: tip.replacingOccurrences(of: "Ctrl+", with: "⌘").replacingOccurrences(of: "Alt+", with: "⌥") as NSString, userData: nil)
                x += dropdown ? 36 : 24
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(tracking!)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        // «Ручка» панели слева.
        NSColor(200, 200, 200).setFill()
        for y in stride(from: 6.0, to: 22.0, by: 3.0) { NSRect(x: 4, y: y, width: 1.3, height: 1.3).fill() }
        NSColor(217, 217, 217).setFill()
        for x in separators { NSRect(x: x, y: 4, width: 1, height: 19).fill() }
        let main = MainWindowController.shared
        for (index, slot) in slots.enumerated() {
            let enabled = main.isEnabled(slot.cmd)
            if enabled, hover == index || pressed == index {
                let area = hoverArrow ? (slot.arrow ?? slot.rect) : slot.rect
                (pressed == index ? Theme.pressed : Theme.hover).setFill()
                area.fill()
                (pressed == index ? Theme.pressedBorder : Theme.hoverBorder).setStroke()
                NSBezierPath.stroke(area.insetBy(dx: 0.5, dy: 0.5))
            }
            slot.glyph.image(size: 20, enabled: enabled).draw(in: NSRect(x: slot.rect.minX + 2, y: slot.rect.minY + 1.5, width: 20, height: 20),
                                                              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if let arrow = slot.arrow {
                (enabled ? NSColor.black : NSColor(160, 160, 160)).setFill()
                let t = NSBezierPath()
                t.move(to: NSPoint(x: arrow.midX - 3.5, y: arrow.midY - 1.5))
                t.line(to: NSPoint(x: arrow.midX + 3.5, y: arrow.midY - 1.5))
                t.line(to: NSPoint(x: arrow.midX, y: arrow.midY + 2.5))
                t.close()
                t.fill()
            }
        }
    }

    private func hit(_ event: NSEvent) -> (Int, Bool)? {
        let p = convert(event.locationInWindow, from: nil)
        for (i, slot) in slots.enumerated() {
            if slot.rect.contains(p) { return (i, false) }
            if let a = slot.arrow, a.contains(p) { return (i, true) }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let h = hit(event)
        if h?.0 != hover || h?.1 != hoverArrow { hover = h?.0; hoverArrow = h?.1 ?? false; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let (index, arrow) = hit(event), MainWindowController.shared.isEnabled(slots[index].cmd) else { return }
        if arrow {
            let menu = MainWindowController.shared.dropdown(for: slots[index].cmd)
            menu.popUp(positioning: nil, at: NSPoint(x: slots[index].rect.minX, y: bounds.height), in: self)
            return
        }
        pressed = index
        hoverArrow = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let index = pressed else { return }
        pressed = nil
        needsDisplay = true
        if hit(event)?.0 == index { MainWindowController.shared.run(slots[index].cmd) }
    }
}

/// Полоса вкладок: значок, название, крестик.
final class TabBarView: NSView {
    static let height: CGFloat = 23
    private var rects: [NSRect] = []
    private var hover: Int?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(tracking!)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(240, 244, 249).setFill()
        bounds.fill()
        let main = MainWindowController.shared
        rects = []
        var x: CGFloat = 6
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.uiFont, .foregroundColor: NSColor.black]
        for (index, tab) in main.tabs.enumerated() {
            let title = tab.tabTitle as NSString
            let w = min(220, title.size(withAttributes: attrs).width + 50)
            let r = NSRect(x: x, y: 2, width: w, height: bounds.height - 3)
            rects.append(r)
            if index == main.currentIndex {
                let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                NSColor.white.setFill()
                p.fill()
                NSColor(200, 206, 214).setStroke()
                p.stroke()
            } else if hover == index {
                NSColor(228, 233, 240).setFill()
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            }
            tab.tabGlyph.image(size: 14).draw(in: NSRect(x: x + 6, y: 5, width: 14, height: 14), from: .zero,
                                             operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let p = NSMutableParagraphStyle()
            p.lineBreakMode = .byTruncatingMiddle
            var a = attrs
            a[.paragraphStyle] = p
            title.draw(in: NSRect(x: x + 24, y: 4, width: w - 44, height: 16), withAttributes: a)
            if index == main.currentIndex || hover == index {
                ("✕" as NSString).draw(at: NSPoint(x: r.maxX - 16, y: 5.5), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor(white: 0.3, alpha: 1)])
            }
            x += w + 2
        }
    }

    private func index(at event: NSEvent) -> (Int, Bool)? {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = rects.firstIndex(where: { $0.contains(p) }) else { return nil }
        return (i, p.x > rects[i].maxX - 20)
    }

    override func mouseMoved(with event: NSEvent) {
        let h = index(at: event)?.0
        if h != hover { hover = h; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let (i, close) = index(at: event) else { return }
        if close { MainWindowController.shared.close(tab: i) } else { MainWindowController.shared.show(tab: i) }
    }

    override func otherMouseDown(with event: NSEvent) {
        if let (i, _) = index(at: event) { MainWindowController.shared.close(tab: i) }
    }
}

/// Строка состояния окна: справа — счёт отличий или строк списка.
final class MainStatusBar: NSView {
    static let height: CGFloat = 17
    var right = "" { didSet { if right != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        (right as NSString).draw(at: NSPoint(x: bounds.width * 0.745, y: 0.5), withAttributes: [.font: Theme.uiFont, .foregroundColor: NSColor.black])
    }
}

private final class RootView: NSView {
    override var isFlipped: Bool { true }
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
    }
}

/// Главное окно: панель инструментов, вкладки, содержимое текущей вкладки, строка состояния.
final class MainWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    static let shared = MainWindowController()
    let window: NSWindow
    private let root = RootView()
    private let toolbar = ToolbarView(frame: .zero)
    private let tabBar = TabBarView()
    private let statusBar = MainStatusBar()
    private let container = FlippedView()
    private(set) var tabs: [DocumentTab] = []
    private(set) var currentIndex = -1
    private var menuKind = -1

    var current: DocumentTab? { currentIndex >= 0 && currentIndex < tabs.count ? tabs[currentIndex] : nil }

    private override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "WMerge"
        window.minSize = NSSize(width: 560, height: 400)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.acceptsMouseMovedEvents = true
        for v in [toolbar, tabBar, container, statusBar] as [NSView] { root.addSubview(v) }
        root.onLayout = { [unowned self] in self.layout() }
        window.setFrameAutosaveName("WMergeMain")
        if window.frame.width < 600 { window.setContentSize(NSSize(width: 1000, height: 640)) }
        window.center()
        _ = window.setFrameUsingName("WMergeMain")
        root.registerForDraggedTypes([.fileURL])
    }

    private func layout() {
        let w = root.bounds.width, h = root.bounds.height
        var y: CGFloat = 0
        toolbar.isHidden = !ViewFlag.toolbar.isOn
        tabBar.isHidden = !ViewFlag.tabBar.isOn
        statusBar.isHidden = !ViewFlag.statusBar.isOn
        if !toolbar.isHidden { toolbar.frame = NSRect(x: 0, y: y, width: w, height: ToolbarView.height); y += ToolbarView.height }
        if !tabBar.isHidden { tabBar.frame = NSRect(x: 0, y: y, width: w, height: TabBarView.height); y += TabBarView.height }
        let bottom: CGFloat = statusBar.isHidden ? 0 : MainStatusBar.height
        statusBar.frame = NSRect(x: 0, y: h - bottom, width: w, height: bottom)
        container.frame = NSRect(x: 0, y: y, width: w, height: h - y - bottom)
        current?.frame = container.bounds
    }

    func refreshChrome() {
        toolbar.needsDisplay = true
        tabBar.needsDisplay = true
        statusBar.right = current?.statusRight ?? ""
        window.title = current.map { "WMerge - [\($0.tabTitle)]" } ?? "WMerge"
        let kind = current is FileCompareView ? 1 : current is FolderCompareView ? 2 : 0
        if kind != menuKind {
            menuKind = kind
            NSApp.mainMenu = Menus.build(kind: kind)
        }
    }

    // MARK: Вкладки

    func add(_ tab: DocumentTab, replacing old: DocumentTab? = nil) {
        if let old, let index = tabs.firstIndex(where: { $0 === old }) {
            old.removeFromSuperview()
            tabs[index] = tab
            currentIndex = -1
            show(tab: index)
        } else {
            tabs.append(tab)
            show(tab: tabs.count - 1)
        }
    }

    func show(tab index: Int) {
        guard index >= 0, index < tabs.count else { return }
        if index != currentIndex { current?.removeFromSuperview() }
        currentIndex = index
        let tab = tabs[index]
        tab.frame = container.bounds
        tab.autoresizingMask = [.width, .height]
        if tab.superview == nil { container.addSubview(tab) }
        tab.layoutSubtreeIfNeeded()
        refreshChrome()
        tab.activated()
    }

    func close(tab index: Int) {
        guard index >= 0, index < tabs.count else { return }
        if index != currentIndex { show(tab: index) }
        guard tabs[index].canClose() else { return }
        tabs[index].removeFromSuperview()
        tabs.remove(at: index)
        currentIndex = -1
        if tabs.isEmpty { refreshChrome() } else { show(tab: min(index, tabs.count - 1)) }
    }

    func showOpen(left: String? = nil, right: String? = nil) {
        if let index = tabs.firstIndex(where: { $0 is OpenView }) {
            show(tab: index)
            (tabs[index] as? OpenView)?.setPaths(left, right)
            return
        }
        let view = OpenView()
        view.setPaths(left, right)
        add(view)
    }

    /// - Parameter titles: названия панелей вместо путей (пустая строка или нехватка — путь).
    func openFiles(_ left: String?, _ right: String?, readOnly: (Bool, Bool) = (false, false), replacing: DocumentTab? = nil,
                   titles: [String] = []) {
        var files: [TextFile] = []
        for path in [left, right] {
            guard let path else { files.append(TextFile()); continue }
            do { files.append(try TextFile.load(path)) } catch TextFile.LoadError.binary {
                // Двоичные файлы построчно не сравниваются: говорим только, равны ли они.
                if let l = left, let r = right, let a = FileManager.default.contents(atPath: l), let b = FileManager.default.contents(atPath: r) {
                    UI.alert(a == b ? "The selected files are identical." : "Binary files are different.",
                             info: "Binary files cannot be shown side by side in this version.")
                } else {
                    UI.alert("The file is binary and cannot be shown.", info: UI.short(path))
                }
                return
            } catch {
                UI.alert("Cannot open file", info: UI.short(path), style: .warning)
                return
            }
        }
        // Файл, который нельзя записать, открываем «только для чтения»: иначе правка в нём упёрлась бы в ошибку
        // при сохранении. Так приходят версии из истории от WTortoise.
        for (index, path) in [left, right].enumerated() {
            let locked = path.map { !FileManager.default.isWritableFile(atPath: $0) } ?? false
            files[index].readOnly = (index == 0 ? readOnly.0 : readOnly.1) || locked
            if index < titles.count, !titles[index].isEmpty { files[index].title = titles[index] }
        }
        let view = FileCompareView(left: files[0], right: files[1])
        add(view, replacing: replacing)
        if left != nil, right != nil, view.doc.significantCount == 0 {
            UI.alert(view.doc.diff.blocks.isEmpty && view.doc.sides[0].text == view.doc.sides[1].text
                     ? "The selected files are identical." : "The selected files are identical with the current compare options.")
        }
    }

    func openFolders(_ left: String, _ right: String, recursive: Bool, mask: String, replacing: DocumentTab? = nil) {
        add(FolderCompareView(left: left, right: right, recursive: recursive, mask: mask), replacing: replacing)
    }

    /// Вызов из контекстного меню WExplorer, как у WinMerge в Проводнике: ничего не выбрано — пустое окно
    /// выбора, один объект — он слева, два — сразу сравнение.
    /// - Parameter titles: названия панелей из ссылки (`&title=…&title=…`), по порядку путей.
    func openFromExplorer(_ paths: [String], titles: [String] = []) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if paths.count >= 2 { open(paths: Array(paths.prefix(2)), titles: titles); return }
        if let index = tabs.firstIndex(where: { $0 is OpenView }) { show(tab: index) } else { add(OpenView()) }
        (current as? OpenView)?.reset(left: paths.first)
    }

    /// Пути из командной строки, из Finder или брошенные на окно.
    func open(paths: [String], titles: [String] = []) {
        var isDir: ObjCBool = false
        if paths.count >= 2 {
            let a = FileManager.default.fileExists(atPath: paths[0], isDirectory: &isDir) && isDir.boolValue
            let b = FileManager.default.fileExists(atPath: paths[1], isDirectory: &isDir) && isDir.boolValue
            if a && b { openFolders(paths[0], paths[1], recursive: ViewFlag.includeSubfolders.isOn, mask: "*.*") } else if !a && !b {
                openFiles(paths[0], paths[1], titles: titles)
            } else { showOpen(left: paths[0], right: paths[1]) }
        } else {
            showOpen(left: paths.first)
        }
    }

    // MARK: Команды

    private var fieldEditor: NSText? {
        guard let text = NSApp.keyWindow?.firstResponder as? NSText, !(text is TextPane) else { return nil }
        return text
    }

    private func flag(for cmd: Cmd) -> ViewFlag? {
        switch cmd {
        case .viewWhitespace: return .whitespace
        case .viewLineDiff: return .lineDiff
        case .viewLineNumbers: return .lineNumbers
        case .viewMargins: return .margin
        case .toolbar: return .toolbar
        case .statusBar: return .statusBar
        case .tabBar: return .tabBar
        case .diffPane: return .diffPane
        case .locationPane: return .locationPane
        case .showIdentical: return .showIdentical
        case .showDifferent: return .showDifferent
        case .showLeftOnly: return .showLeftOnly
        case .showRightOnly: return .showRightOnly
        case .treeMode: return .treeMode
        case .includeSubfolders: return .includeSubfolders
        default: return nil
        }
    }

    func isEnabled(_ cmd: Cmd) -> Bool {
        switch cmd {
        case .newText, .open, .exit, .options, .about, .help, .toolbar, .statusBar, .tabBar,
             .wsCompare, .wsIgnoreChange, .wsIgnoreAll, .ignoreBlank, .ignoreCase, .ignoreEOL, .includeSubfolders:
            return true
        case .close, .closeAll: return !tabs.isEmpty
        case .nextTab, .prevTab: return tabs.count > 1
        case .cut, .copy, .paste, .selectAll, .undo, .redo:
            if fieldEditor != nil { return true }
            return current?.isEnabled(cmd) ?? false
        default: return current?.isEnabled(cmd) ?? false
        }
    }

    func isChecked(_ cmd: Cmd) -> Bool {
        if let flag = flag(for: cmd) { return flag.isOn }
        let o = CompareOptions.current
        switch cmd {
        case .wsCompare: return o.whitespace == .compare
        case .wsIgnoreChange: return o.whitespace == .ignoreChange
        case .wsIgnoreAll: return o.whitespace == .ignoreAll
        case .ignoreBlank: return o.ignoreBlankLines
        case .ignoreCase: return o.ignoreCase
        case .ignoreEOL: return o.ignoreEOL
        default: return current?.isChecked(cmd) ?? false
        }
    }

    private func settingsChanged(recompare: Bool = false) {
        root.needsLayout = true
        for tab in tabs {
            tab.settingsChanged()
            if recompare, tab is FolderCompareView { tab.perform(.refresh) }
        }
        refreshChrome()
    }

    @objc func menuCommand(_ sender: NSMenuItem) {
        if let cmd = Cmd(rawValue: sender.tag) { run(cmd) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let cmd = Cmd(rawValue: item.tag) else { return true }
        item.state = isChecked(cmd) ? .on : .off
        return isEnabled(cmd)
    }

    func run(_ cmd: Cmd) {
        guard isEnabled(cmd) else { NSSound.beep(); return }
        if let editor = fieldEditor {
            switch cmd {
            case .cut: editor.cut(nil); return
            case .copy: editor.copy(nil); return
            case .paste: editor.paste(nil); return
            case .selectAll: editor.selectAll(nil); return
            case .undo: editor.undoManager?.undo(); return
            case .redo: editor.undoManager?.redo(); return
            default: break
            }
        }
        if let flag = flag(for: cmd) {
            flag.toggle()
            settingsChanged()
            return
        }
        var options = CompareOptions.current
        switch cmd {
        case .newText: add(FileCompareView(left: TextFile(), right: TextFile()))
        case .open: showOpen()
        case .exit: NSApp.terminate(nil)
        case .options: if OptionsDialog.show() { settingsChanged(recompare: true) }
        case .about: About.show()
        case .help: if let url = URL(string: "https://manual.winmerge.org/en/") { NSWorkspace.shared.open(url) }
        case .close: close(tab: currentIndex)
        case .closeAll: while !tabs.isEmpty { let n = tabs.count; close(tab: n - 1); if tabs.count == n { break } }
        case .nextTab: show(tab: (currentIndex + 1) % tabs.count)
        case .prevTab: show(tab: (currentIndex - 1 + tabs.count) % tabs.count)
        case .zoomIn, .zoomOut, .zoomNormal:
            let size = cmd == .zoomNormal ? 11 : min(40, max(6, Theme.editorFontSize + (cmd == .zoomIn ? 1 : -1)))
            UserDefaults.standard.set(Double(size), forKey: "editor.fontSize")
            settingsChanged()
        case .wsCompare, .wsIgnoreChange, .wsIgnoreAll:
            options.whitespace = cmd == .wsCompare ? .compare : cmd == .wsIgnoreChange ? .ignoreChange : .ignoreAll
            options.save(); settingsChanged(recompare: true)
        case .ignoreBlank: options.ignoreBlankLines.toggle(); options.save(); settingsChanged(recompare: true)
        case .ignoreCase: options.ignoreCase.toggle(); options.save(); settingsChanged(recompare: true)
        case .ignoreEOL: options.ignoreEOL.toggle(); options.save(); settingsChanged(recompare: true)
        default:
            current?.perform(cmd)
            refreshChrome()
        }
    }

    // MARK: Выпадающие списки кнопок

    private func item(_ title: String, _ cmd: Cmd, in menu: NSMenu) {
        let i = NSMenuItem(title: title, action: #selector(menuCommand(_:)), keyEquivalent: "")
        i.target = self
        i.tag = cmd.rawValue
        menu.addItem(i)
    }

    /// Меню быстрых настроек сравнения — стрелка у кнопки Options.
    func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        let ws = NSMenuItem(title: "Whitespaces", action: nil, keyEquivalent: "")
        ws.submenu = NSMenu()
        item("Compare", .wsCompare, in: ws.submenu!)
        item("Ignore Changes", .wsIgnoreChange, in: ws.submenu!)
        item("Ignore All", .wsIgnoreAll, in: ws.submenu!)
        menu.addItem(ws)
        item("Ignore Blank Lines", .ignoreBlank, in: menu)
        item("Ignore Case", .ignoreCase, in: menu)
        item("Ignore EOL Differences (Windows/Unix/Mac)", .ignoreEOL, in: menu)
        menu.addItem(.separator())
        item("Include Subfolders", .includeSubfolders, in: menu)
        return menu
    }

    func dropdown(for cmd: Cmd) -> NSMenu {
        let menu = NSMenu()
        switch cmd {
        case .newText:
            item("Text", .newText, in: menu)
        case .open:
            let recent = UserDefaults.standard.stringArray(forKey: "open.history0") ?? []
            let other = UserDefaults.standard.stringArray(forKey: "open.history1") ?? []
            if recent.isEmpty || other.isEmpty { menu.addItem(withTitle: "< Empty >", action: nil, keyEquivalent: "") }
            for (a, b) in zip(recent, other).prefix(10) {
                let i = NSMenuItem(title: "\(UI.short(a)) - \(UI.short(b))", action: #selector(openRecent(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = [a, b]
                menu.addItem(i)
            }
        case .save:
            item("Save Left", .saveLeft, in: menu)
            item("Save Right", .saveRight, in: menu)
            menu.addItem(.separator())
            item("Save Left As...", .saveLeftAs, in: menu)
            item("Save Right As...", .saveRightAs, in: menu)
        default:
            return optionsMenu()
        }
        return menu
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let paths = sender.representedObject as? [String] { open(paths: paths) }
    }

    // MARK: Окно

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeEverything()
    }

    /// Закрывает все вкладки, спрашивая о несохранённом; false — пользователь передумал.
    func closeEverything() -> Bool {
        for (index, tab) in tabs.enumerated() where tab is FileCompareView {
            show(tab: index)
            if !tab.canClose() { return false }
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) { current?.needsDisplay = true; current?.subviews.forEach { $0.needsDisplay = true } }
    func windowDidResignKey(_ notification: Notification) { current?.subviews.forEach { $0.needsDisplay = true } }
}
