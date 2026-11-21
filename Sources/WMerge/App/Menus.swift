import AppKit

/// Строка меню: состав и порядок — как в WinMerge; Ctrl заменён на ⌘, Alt — на ⌥.
enum Menus {
    private static func key(_ code: Int) -> String { String(UnicodeScalar(code)!) }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ cmd: Cmd, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MainWindowController.menuCommand(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.target = MainWindowController.shared
        item.tag = cmd.rawValue
        menu.addItem(item)
        return item
    }

    private static func sub(_ menu: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu(title: title)
        menu.addItem(item)
        return item.submenu!
    }

    /// kind: 0 — нет документа или окно выбора, 1 — сравнение файлов, 2 — сравнение папок.
    static func build(kind: Int) -> NSMenu {
        let main = NSMenu()
        func top(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            main.addItem(item)
            return item.submenu!
        }
        let up = key(NSUpArrowFunctionKey), down = key(NSDownArrowFunctionKey)
        let left = key(NSLeftArrowFunctionKey), right = key(NSRightArrowFunctionKey)

        let app = top("WMerge")
        add(app, "About WMerge", .about)
        app.addItem(.separator())
        add(app, "Options...", .options, ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide WMerge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        add(app, "Exit", .exit, "q")

        let file = top("File")
        let new = sub(file, "New")
        add(new, "Text", .newText, "n")
        add(file, "Open...", .open, "o")
        if kind == 1 {
            file.addItem(.separator())
            add(file, "Save", .save, "s")
            let save = sub(file, "Save")
            add(save, "Save Left", .saveLeft)
            add(save, "Save Right", .saveRight)
            let saveAs = sub(file, "Save As")
            add(saveAs, "Save Left As...", .saveLeftAs)
            add(saveAs, "Save Right As...", .saveRightAs)
            file.addItem(.separator())
            let ro = sub(file, "Read-Only")
            add(ro, "Left Read-Only", .leftReadOnly)
            add(ro, "Right Read-Only", .rightReadOnly)
            file.addItem(.separator())
            let eol = sub(file, "Convert Line Endings to")
            add(eol, "Windows (CRLF)", .eolWin)
            add(eol, "Unix (LF)", .eolUnix)
            add(eol, "Mac (CR)", .eolMac)
            file.addItem(.separator())
            add(file, "Reload", .reload, key(NSF5FunctionKey), [.command])
        }

        let edit = top("Edit")
        if kind == 1 {
            add(edit, "Undo", .undo, "z")
            add(edit, "Redo", .redo, "y")
            edit.addItem(.separator())
        }
        if kind != 2 {
            add(edit, "Cut", .cut, "x")
            add(edit, "Copy", .copy, "c")
            add(edit, "Paste", .paste, "v")
            edit.addItem(.separator())
        }
        if kind == 1 { add(edit, "Select Line Difference", .selectLineDiff, key(NSF4FunctionKey), []) }
        add(edit, "Select All", .selectAll, "a")
        if kind == 1 {
            edit.addItem(.separator())
            add(edit, "Find...", .find, "f")
            add(edit, "Find Next", .findNext, key(NSF3FunctionKey), [])
            add(edit, "Find Previous", .findPrev, key(NSF3FunctionKey), [.shift])
            add(edit, "Replace...", .replace, "h", [.command, .option])
            edit.addItem(.separator())
            add(edit, "Go to...", .goTo, "g")
        }
        edit.addItem(.separator())
        add(edit, "Options...", .options)

        let view = top("View")
        if kind == 2 {
            add(view, "Show Identical Items", .showIdentical)
            add(view, "Show Different Items", .showDifferent)
            add(view, "Show Left Unique Items", .showLeftOnly)
            add(view, "Show Right Unique Items", .showRightOnly)
            view.addItem(.separator())
            add(view, "Tree Mode", .treeMode)
            let expand = sub(view, "Expand Subfolders")
            add(expand, "All Subfolders", .expandAll)
            add(view, "Collapse All Subfolders", .collapseAll)
            view.addItem(.separator())
        }
        if kind == 1 {
            let zoom = sub(view, "Zoom")
            add(zoom, "Zoom In", .zoomIn, "+")
            add(zoom, "Zoom Out", .zoomOut, "-")
            zoom.addItem(.separator())
            add(zoom, "Normal", .zoomNormal, "0")
            view.addItem(.separator())
            add(view, "View Whitespace", .viewWhitespace)
            add(view, "View Line Differences", .viewLineDiff)
            add(view, "View Line Numbers", .viewLineNumbers)
            add(view, "View Margins", .viewMargins)
            view.addItem(.separator())
            let swap = sub(view, "Swap Panes")
            add(swap, "Swap 1st | 2nd", .swapPanes)
            view.addItem(.separator())
        }
        add(view, "Tab Bar", .tabBar)
        add(view, "Toolbar", .toolbar)
        add(view, "Status Bar", .statusBar)
        if kind == 1 {
            add(view, "Diff Pane", .diffPane)
            add(view, "Location Pane", .locationPane)
        }
        if kind != 0 {
            view.addItem(.separator())
            add(view, "Refresh", .refresh, key(NSF5FunctionKey), [])
        }

        if kind != 0 {
            let merge = top("Merge")
            if kind == 2 {
                add(merge, "Compare", .compare, "\r", [])
                merge.addItem(.separator())
            }
            add(merge, "Next Difference", .nextDiff, down, [.option])
            add(merge, "Previous Difference", .prevDiff, up, [.option])
            merge.addItem(.separator())
            add(merge, "First Difference", .firstDiff, key(NSHomeFunctionKey), [.option])
            add(merge, "Current Difference", .currentDiff, "\r", [.option])
            add(merge, "Last Difference", .lastDiff, key(NSEndFunctionKey), [.option])
            merge.addItem(.separator())
            add(merge, "Copy to Right", .copyRight, right, [.option])
            add(merge, "Copy to Left", .copyLeft, left, [.option])
            if kind == 1 {
                merge.addItem(.separator())
                add(merge, "Copy to Right and Advance", .copyRightAdvance, right, [.command, .option])
                add(merge, "Copy to Left and Advance", .copyLeftAdvance, left, [.command, .option])
                merge.addItem(.separator())
                add(merge, "Copy All to Right", .allRight)
                add(merge, "Copy All to Left", .allLeft)
                // Те же клавиши, что в WinMerge помимо меню: F7 / F8.
                let f8 = add(merge, "Next Difference", .nextDiff, key(NSF8FunctionKey), [])
                let f7 = add(merge, "Previous Difference", .prevDiff, key(NSF7FunctionKey), [])
                for i in [f7, f8] { i.isAlternate = false; i.isHidden = true; i.allowsKeyEquivalentWhenHidden = true }
            } else {
                merge.addItem(.separator())
                add(merge, "Delete", .delete)
            }
        }

        let tools = top("Tools")
        add(tools, "Generate Patch...", .generatePatch)

        let window = top("Window")
        add(window, "Close", .close, "w")
        add(window, "Close All", .closeAll)
        window.addItem(.separator())
        add(window, "Change Pane", .changePane, key(NSF6FunctionKey), [])
        window.addItem(.separator())
        add(window, "Next Tab", .nextTab, "\t", [.control])
        add(window, "Previous Tab", .prevTab, "\t", [.control, .shift])
        window.addItem(.separator())
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        let help = top("Help")
        add(help, "WinMerge Help", .help, key(NSF1FunctionKey), [])
        help.addItem(.separator())
        add(help, "About WMerge...", .about)
        return main
    }
}
