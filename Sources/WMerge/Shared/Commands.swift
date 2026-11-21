import AppKit

/// Команды меню и панели инструментов. Номер — тег пункта меню.
enum Cmd: Int {
    case newText = 1, open, save, saveLeft, saveRight, saveLeftAs, saveRightAs, leftReadOnly, rightReadOnly
    case eolWin, eolUnix, eolMac, reload, exit
    case undo, redo, cut, copy, paste, selectLineDiff, selectAll, find, findNext, findPrev, replace, goTo, options
    case zoomIn, zoomOut, zoomNormal, viewWhitespace, viewLineDiff, viewLineNumbers, viewMargins, swapPanes
    case toolbar, statusBar, tabBar, diffPane, locationPane, refresh
    case showIdentical, showDifferent, showLeftOnly, showRightOnly, treeMode, expandAll, collapseAll
    case nextDiff, prevDiff, firstDiff, currentDiff, lastDiff
    case copyRight, copyLeft, copyRightAdvance, copyLeftAdvance, allRight, allLeft, compare, delete
    case wsCompare, wsIgnoreChange, wsIgnoreAll, ignoreBlank, ignoreCase, ignoreEOL, includeSubfolders
    case generatePatch, close, closeAll, changePane, nextTab, prevTab, about, help
    // Кнопки панели, которым в двухстороннем сравнении нет дела: всегда серые, как в оригинале.
    case nextConflict, prevConflict, autoMerge, firstFile, prevFile, nextFile, lastFile
}

/// Вкладка главного окна: сравнение файлов, сравнение папок или выбор того, что сравнивать.
protocol DocumentTab: NSView {
    var tabTitle: String { get }
    var tabGlyph: Glyph { get }
    /// Правая ячейка строки состояния окна («Difference 2 of 5»).
    var statusRight: String { get }
    func isEnabled(_ cmd: Cmd) -> Bool
    func isChecked(_ cmd: Cmd) -> Bool
    func perform(_ cmd: Cmd)
    /// Можно ли закрыть; при несохранённых правках спрашивает сам.
    func canClose() -> Bool
    func activated()
    func settingsChanged()
}

enum UI {
    static func label(_ text: String, bold: Bool = false, size: CGFloat = 12) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.textColor = .black
        return label
    }

    static func button(_ title: String, target: AnyObject?, action: Selector?, key: String = "") -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.keyEquivalent = key
        b.font = .systemFont(ofSize: 12)
        return b
    }

    static func check(_ title: String, on: Bool, target: AnyObject? = nil, action: Selector? = nil) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: target, action: action)
        b.state = on ? .on : .off
        b.font = .systemFont(ofSize: 12)
        return b
    }

    static func radio(_ title: String, on: Bool, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(radioButtonWithTitle: title, target: target, action: action)
        b.state = on ? .on : .off
        b.font = .systemFont(ofSize: 12)
        return b
    }

    @discardableResult
    static func alert(_ message: String, info: String = "", buttons: [String] = ["OK"], style: NSAlert.Style = .informational) -> Int {
        if Snapshot.active { return 0 }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    /// Путь для показа: домашняя папка — тильдой.
    static func short(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
