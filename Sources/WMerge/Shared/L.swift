import Foundation

/// Две строки интерфейса — русская и английская. По умолчанию английская, с названиями как в WinMerge;
/// русский включается в настройках (ключ `language` = `ru`, действует после перезапуска).
enum L {
    static let languageKey = "language"

    static let isRussian: Bool = UserDefaults.standard.string(forKey: languageKey) == "ru"

    static func t(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}
