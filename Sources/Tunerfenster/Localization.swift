import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    var id: String { rawValue }
    var name: String { self == .german ? "Deutsch (DE)" : "English (EN)" }
    var locale: Locale { Locale(identifier: self == .german ? "de_DE" : "en_GB") }

    static func initial(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        if let value = defaults.string(forKey: "interfaceLanguage"), let language = AppLanguage(rawValue: value) { return language }
        return preferredLanguages.first?.lowercased().hasPrefix("de") == true ? .german : .english
    }
}

enum L10n {
    static var language: AppLanguage { .initial() }

    static func translations(for language: AppLanguage) -> [String: String] {
        guard let folder = Bundle.module.url(forResource: language.rawValue, withExtension: "lproj"),
              let data = try? Data(contentsOf: folder.appendingPathComponent("Localizable.strings")),
              let result = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return [:] }
        return result
    }

    private static let english = translations(for: .english)
    private static let german = translations(for: .german)

    static func text(_ key: String, _ arguments: String...) -> String {
        text(key, arguments: arguments, language: language)
    }

    static func text(_ key: String, arguments: [String], language: AppLanguage) -> String {
        let table = language == .german ? german : english
        let format = table[key] ?? english[key] ?? key
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    static func decimal(_ value: Double) -> String {
        String(format: "%.1f", locale: language.locale, value)
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(language.locale))
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    private var menuObservers = [NSObjectProtocol]()
    private var translatingMenus = false
    @Published var language = AppLanguage.initial() {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage")
            // SwiftUI changes language immediately. macOS reads this app-specific
            // preference for native panels on the next launch.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
            DispatchQueue.main.async { self.localizeNativeMenus() }
        }
    }

    private init() {
        // SwiftUI can rebuild AppKit's standard menus after a scene update.
        // Translate newly inserted or renamed items as well as existing ones.
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.localizeNativeMenus() }
            })
        }
    }

    func localizeNativeMenus() {
        guard !translatingMenus else { return }
        translatingMenus = true
        defer { translatingMenus = false }
        func translate(_ menu: NSMenu) {
            for item in menu.items {
                if let key = Self.nativeTitles[item.title] {
                    let title = L10n.text(key)
                    if item.title != title { item.title = title }
                }
                if let submenu = item.submenu {
                    if let key = Self.nativeTitles[submenu.title] {
                        let title = L10n.text(key)
                        if submenu.title != title { submenu.title = title }
                    }
                    translate(submenu)
                }
            }
        }
        if let menu = NSApp.mainMenu { translate(menu) }
        for window in NSApp.windows where Self.nativeTitles[window.title] == "softwareUpdates" {
            window.title = L10n.text("softwareUpdates")
        }
    }

    private static let nativeTitles: [String: String] = {
        let keys = ["menuEdit", "menuView", "menuWindow", "menuHelp", "menuServices", "menuUndo", "menuRedo", "menuCut", "menuCopy", "menuPaste", "menuPasteStyle", "menuDelete", "menuSelectAll", "menuMinimize", "menuZoom", "menuBringAll", "menuEnterFullScreen", "menuExitFullScreen", "menuShowToolbar", "menuHideToolbar", "menuCustomizeToolbar", "menuAbout", "menuHideApp", "menuHideOthers", "menuShowAll", "menuQuit", "menuAppHelp", "softwareUpdates"]
        var result = [String: String]()
        for language in AppLanguage.allCases {
            let table = L10n.translations(for: language)
            for key in keys { if let title = table[key] { result[title] = key } }
        }
        return result
    }()
}
