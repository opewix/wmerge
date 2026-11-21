import AppKit

/// `WMerge -snapshot <папка> [-left <путь> -right <путь>]`: рисует окно программы в PNG и выходит.
/// Для README и сверки вида с оригиналом без разрешения на запись экрана.
enum Snapshot {
    static var directory: String? { argument("-snapshot") }
    static var active: Bool { directory != nil }

    private static func argument(_ key: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run(into directory: String) {
        let out = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let main = MainWindowController.shared
        main.window.setContentSize(NSSize(width: 853, height: 452))
        main.window.orderFront(nil)

        let sample = out.appendingPathComponent("sample")
        let (left, right) = argument("-left").flatMap { l in argument("-right").map { (l, $0) } } ?? makeSample(in: sample)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: left, isDirectory: &isDir)

        var shots: [(String, () -> Void)] = []
        shots.append(("open", { main.showOpen(left: left, right: right) }))
        if isDir.boolValue {
            shots.append(("folders", { main.openFolders(left, right, recursive: true, mask: "*.*") }))
        } else {
            shots.append(("files", {
                main.openFiles(left, right)
                main.run(.nextDiff)
                main.run(.nextDiff)
            }))
            shots.append(("folders", {
                main.openFolders((left as NSString).deletingLastPathComponent, (right as NSString).deletingLastPathComponent, recursive: true, mask: "*.*")
                main.run(.expandAll)
            }))
        }
        // Вызов из WExplorer с одним выбранным файлом: он слева, справа пусто.
        shots.append(("explorer-one", { main.openFromExplorer([left]) }))
        func next(_ index: Int) {
            guard index < shots.count else {
                saveIcons(to: out.appendingPathComponent("icons.png"))
                exit(0)
            }
            shots[index].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                save(main.window, to: out.appendingPathComponent("\(shots[index].0).png"))
                next(index + 1)
            }
        }
        next(0)
    }

    private static func save(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("Saved \(url.path)")
    }

    /// Все значки одним листом — для сверки с оригиналом.
    private static func saveIcons(to url: URL) {
        let all = Glyph.allCases
        let cell: CGFloat = 40
        let image = NSImage(size: NSSize(width: cell * CGFloat(all.count), height: cell * 2))
        image.lockFocus()
        NSColor(240, 240, 240).setFill()
        NSRect(origin: .zero, size: image.size).fill()
        for (i, g) in all.enumerated() {
            g.image(size: 32).draw(in: NSRect(x: CGFloat(i) * cell + 4, y: cell + 4, width: 32, height: 32))
            g.image(size: 32, enabled: false).draw(in: NSRect(x: CGFloat(i) * cell + 4, y: 4, width: 32, height: 32))
        }
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    /// Две версии небольшого дерева исходников, чтобы было что показать.
    private static func makeSample(in dir: URL) -> (String, String) {
        let old = """
        #include "StdAfx.h"
        #include "Merge.h"

        /**
         * @brief Create a backup of the file before saving.
         */
        bool CMergeApp::CreateBackup(bool bFolder, const String& pszPath)
        {
        \tbool success = true;
        \tString bakPath = GetBackupFolder(pszPath);
        \tString filename = paths::FindFileName(pszPath);
        \tString ext = BACKUP_FILE_EXT;

        \tif (GetOptionsMgr()->GetBool(OPT_BACKUP_ADD_TIME))
        \t{
        \t\tstruct tm tm;
        \t\ttime_t curtime = 0;
        \t\ttime(&curtime);
        \t\tlocaltime_s(&tm, &curtime);
        \t\tCString timestr;
        \t\ttimestr.Format(_T("%04d%02d%02d%02d%02d%02d"), tm.tm_year + 1900);
        \t\tfilename += _T("-");
        \t\tfilename += timestr;
        \t}

        \t// Append filename and extension (+ optional .bak) to path
        \tif ((bakPath.length() + filename.length() + ext.length())
        \t\t< MAX_PATH)
        \t{
        \t\tsuccess = TRUE;
        \t\tbakPath = paths::ConcatPath(bakPath, filename);
        \t\tbakPath += _T(".");
        \t\tbakPath += ext;
        \t}

        \tif (success)
        \t\tsuccess = CopyFile(pszPath.c_str(), bakPath.c_str(), FALSE);

        \tif (!success)
        \t{
        \t\tString msg = strutils::format_string1(
        \t\t\t_("Unable to backup original file:\\n%1\\n\\nContinue anyway?"),
        \t\t\tpszPath);
        \t\tif (AfxMessageBox(msg.c_str(), MB_YESNO | MB_ICONWARNING) != IDYES)
        \t\t\treturn false;
        \t}
        \treturn true;
        }

        int CMergeApp::GetActiveOperations() const
        {
        \treturn m_nActiveOperations;
        }
        """
        let new = old
            .replacingOccurrences(of: "< MAX_PATH)", with: "< MAX_PATH_FULL)")
            .replacingOccurrences(of: "success = TRUE;", with: "success = true;")
            .replacingOccurrences(of: "\tif (success)\n\t\tsuccess = CopyFile(pszPath.c_str(), bakPath.c_str(), FALSE);",
                                  with: "\tif (success)\n\t{\n\t\tsuccess = !!CopyFileW(TFile(pszPath).wpath().c_str(), TFile(bakPath).wpath().c_str(), FALSE);\n\t}")
            .replacingOccurrences(of: "int CMergeApp::GetActiveOperations() const", with: "/** @brief Number of running operations. */\nint CMergeApp::GetActiveOperations() const")
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        let files: [(String, String, String?)] = [
            ("Src/Merge.cpp", old, new),
            ("Src/Merge.h", "#pragma once\n\nclass CMergeApp;\n", "#pragma once\n\nclass CMergeApp;\nclass CMainFrame;\n"),
            ("Src/Common/Bitmap.cpp", "// bitmap helpers\n", "// bitmap helpers\n"),
            ("Src/Common/Bitmap.h", "#pragma once\n", "#pragma once\n"),
            ("Src/Common/BCMenu.cpp", "void Draw();\n", "void Draw(int dpi);\n"),
            ("Docs/ReadMe.txt", "WinMerge 2.15.4\n", "WinMerge 2.15.5\n"),
            ("Docs/Changes.txt", "one\ntwo\n", "one\ntwo\n"),
            ("Installer/setup.iss", "; setup\n", nil),
        ]
        for (name, a, b) in files {
            for (side, text) in [("2.15.4", Optional(a)), ("2.15.5", b)] {
                guard let text else { continue }
                let url = dir.appendingPathComponent(side).appendingPathComponent(name)
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        try? fm.createDirectory(at: dir.appendingPathComponent("2.15.5/Plugins"), withIntermediateDirectories: true)
        try? "x\n".write(to: dir.appendingPathComponent("2.15.5/Plugins/list.txt"), atomically: true, encoding: .utf8)
        return (dir.appendingPathComponent("2.15.4/Src/Merge.cpp").path, dir.appendingPathComponent("2.15.5/Src/Merge.cpp").path)
    }
}
