import AppKit

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    convenience init(_ r: Int, _ g: Int, _ b: Int) {
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

/// Цвета и размеры. Цвета отличий — умолчания WinMerge (Options → Colors → Differences).
enum Theme {
    // Отличие: строка есть / строки нет (заполнитель) / отличие внутри строки.
    static let diff = NSColor(239, 203, 5)
    static let diffDeleted = NSColor(192, 192, 192)
    static let diffWord = NSColor(241, 226, 173)
    // Выбранное отличие.
    static let selDiff = NSColor(239, 119, 116)
    static let selDiffDeleted = NSColor(240, 192, 192)
    static let selDiffWord = NSColor(255, 160, 160)
    // Отличие, которое настройки велят не считать.
    static let trivial = NSColor(251, 242, 191)
    static let trivialDeleted = NSColor(233, 233, 233)

    static let textBackground = NSColor.white
    static let text = NSColor.black
    static let margin = NSColor(240, 240, 240)
    static let marginText = NSColor(96, 96, 96)
    static let whitespace = NSColor(0, 128, 192)
    static let selection = NSColor(0, 120, 215)
    static let selectionInactive = NSColor(200, 200, 200)

    // Рамка окна в духе Windows.
    static let chrome = NSColor(240, 240, 240)
    static let chromeBorder = NSColor(160, 160, 160)
    static let chromeLight = NSColor(218, 218, 218)
    static let hover = NSColor(229, 243, 255)
    static let hoverBorder = NSColor(204, 232, 255)
    static let pressed = NSColor(204, 232, 255)
    static let pressedBorder = NSColor(153, 209, 255)
    static let headerActive = NSColor(197, 210, 225)
    static let headerInactive = NSColor(216, 223, 230)
    static let locationBackground = NSColor(231, 231, 243)
    static let scrollThumb = NSColor(133, 133, 133)
    static let dirDifferent = NSColor(240, 222, 125)
    static let dirMissing = NSColor(221, 221, 221)

    static let uiFont = NSFont.systemFont(ofSize: 11.5)
    static let smallFont = NSFont.systemFont(ofSize: 11)

    static var editorFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "editor.fontSize")
        return v >= 6 ? CGFloat(v) : 11
    }

    static var editorFont: NSFont {
        let name = UserDefaults.standard.string(forKey: "editor.fontName") ?? "Menlo"
        return NSFont(name: name, size: editorFontSize) ?? .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    static var tabSize: Int {
        let v = UserDefaults.standard.integer(forKey: "editor.tabSize")
        return v > 0 ? v : 4
    }
}

/// Настройки вида, которые переключаются из меню View и живут между запусками.
enum ViewFlag: String {
    case lineNumbers = "view.lineNumbers"
    case margin = "view.margin"
    case whitespace = "view.whitespace"
    case lineDiff = "view.lineDiff"
    case wordLevel = "view.wordLevel"
    case locationPane = "view.locationPane"
    case diffPane = "view.diffPane"
    case toolbar = "view.toolbar"
    case statusBar = "view.statusBar"
    case tabBar = "view.tabBar"
    case treeMode = "dir.treeMode"
    case showIdentical = "dir.showIdentical"
    case showDifferent = "dir.showDifferent"
    case showLeftOnly = "dir.showLeftOnly"
    case showRightOnly = "dir.showRightOnly"
    case includeSubfolders = "open.includeSubfolders"

    private static let offByDefault: Set<ViewFlag> = [.lineNumbers, .whitespace, .margin, .diffPane]

    var isOn: Bool {
        UserDefaults.standard.object(forKey: rawValue) == nil ? !ViewFlag.offByDefault.contains(self) : UserDefaults.standard.bool(forKey: rawValue)
    }

    func set(_ on: Bool) { UserDefaults.standard.set(on, forKey: rawValue) }
    func toggle() { set(!isOn) }
}
