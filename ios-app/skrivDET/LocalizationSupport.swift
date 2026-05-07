import Foundation

private enum AppLocalizationDefaults {
    static let languageKey = "skrivDetAppLanguage"
    static let legacyLanguageKeys = ["skrivDETAppLanguage", "MeetingTranscribeAppLanguage"]
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case english = "en"
    case norwegian = "nb"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .norwegian:
            return "nb"
        }
    }

    var nativeDisplayName: String {
        switch self {
        case .english:
            return "English"
        case .norwegian:
            return "Norsk"
        }
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("nb") || preferred.hasPrefix("nn") || preferred.hasPrefix("no") {
            return .norwegian
        }
        return .english
    }
}

enum AppLocalizer {
    static var currentLanguage: AppLanguage {
        get {
            guard
                let rawValue = storedLanguageValue(),
                let language = AppLanguage(rawValue: rawValue)
            else {
                return .systemDefault
            }

            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppLocalizationDefaults.languageKey)
            AppLocalizationDefaults.legacyLanguageKeys.forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }
    }

    static var currentLocale: Locale {
        Locale(identifier: currentLanguage.localeIdentifier)
    }

    static func text(_ key: String) -> String {
        if currentLanguage == .english {
            return englishBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        }

        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: currentLocale, arguments: arguments)
    }

    static func shortDateTimeString(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(currentLocale)
        )
    }

    private static var englishBundle: Bundle? {
        guard let path = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj") else {
            return nil
        }

        return Bundle(path: path)
    }

    private static func storedLanguageValue() -> String? {
        if let current = UserDefaults.standard.string(forKey: AppLocalizationDefaults.languageKey) {
            return current
        }

        for legacyKey in AppLocalizationDefaults.legacyLanguageKeys {
            guard let legacy = UserDefaults.standard.string(forKey: legacyKey) else {
                continue
            }

            UserDefaults.standard.set(legacy, forKey: AppLocalizationDefaults.languageKey)
            return legacy
        }

        return nil
    }

    private static var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
