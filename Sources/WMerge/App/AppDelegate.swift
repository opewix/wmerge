import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launched = false
    private var pending: [String] = []
    /// Пути из ссылки `wmerge://compare?path=…`, пришедшей до конца запуска.
    private var pendingLink: [String]?
    private var pendingTitles: [String] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Окно в духе Windows — светлое при любой теме системы.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.mainMenu = Menus.build(kind: 0)
    }

    /// Файлы и папки, брошенные на значок или открытые через «Открыть в программе».
    func application(_ application: NSApplication, open urls: [URL]) {
        // Ссылка от WExplorer или WTortoise: `wmerge://compare?path=…&path=…` — ноль, один или два пути;
        // необязательные `title=…` — названия панелей вместо путей, в том же порядке.
        if let link = urls.first(where: { $0.scheme == "wmerge" }) {
            let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let paths = items.filter { $0.name == "path" }.compactMap { $0.value }
            let titles = items.filter { $0.name == "title" }.map { $0.value ?? "" }
            if launched {
                MainWindowController.shared.openFromExplorer(paths, titles: titles)
            } else {
                pendingLink = paths
                pendingTitles = titles
            }
            return
        }
        let paths = urls.filter { $0.isFileURL }.map { $0.path }
        guard !paths.isEmpty else { return }
        if launched { MainWindowController.shared.open(paths: paths) } else { pending += paths }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        let main = MainWindowController.shared
        if let directory = Snapshot.directory {
            Snapshot.run(into: directory)
            return
        }
        main.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let link = pendingLink {
            pendingLink = nil
            main.openFromExplorer(link, titles: pendingTitles)
            return
        }
        // Пути из командной строки: `WMerge левый правый`.
        var paths = pending
        var skip = false
        for arg in CommandLine.arguments.dropFirst() {
            if skip { skip = false; continue }
            if arg.hasPrefix("-") { skip = true; continue }
            paths.append(URL(fileURLWithPath: arg).standardizedFileURL.path)
        }
        if paths.isEmpty { main.showOpen() } else { main.open(paths: paths) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Snapshot.active || MainWindowController.shared.closeEverything() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.window.makeKeyAndOrderFront(nil) }
        return true
    }
}
