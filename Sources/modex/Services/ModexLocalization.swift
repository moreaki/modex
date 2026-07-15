import Foundation

enum ModexStrings {
    static let languagePreferenceDefaultsKey = "language"

    static func text(_ key: String) -> String {
        localizationBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: localizationLocale, arguments: arguments)
    }

    static func decimal(_ value: Double, maximumFractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...maximumFractionDigits))
                .locale(localizationLocale)
        )
    }

    private static var localizationBundle: Bundle {
        if let languageCode = preferredLanguageCode,
           let bundle = bundle(for: languageCode)
        {
            return bundle
        }

        for language in Locale.preferredLanguages {
            let code = normalizedLanguageCode(language)
            if let bundle = bundle(for: code) {
                return bundle
            }
        }

        return bundle(for: "en") ?? .module
    }

    private static var localizationLocale: Locale {
        if let languageCode = preferredLanguageCode {
            return Locale(identifier: languageCode)
        }
        return Locale.autoupdatingCurrent
    }

    private static var preferredLanguageCode: String? {
        guard let value = UserDefaults.standard.string(forKey: languagePreferenceDefaultsKey),
              value.isEmpty == false,
              value != "system"
        else {
            return nil
        }
        return normalizedLanguageCode(value)
    }

    private static func bundle(for languageCode: String) -> Bundle? {
        guard let path = Bundle.module.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private static func normalizedLanguageCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return String(normalized.split(separator: "-").first ?? Substring(normalized))
    }
}
