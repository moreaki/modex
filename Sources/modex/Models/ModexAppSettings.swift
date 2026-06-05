import Foundation
import ModexCore

struct ModexContextThresholds: Equatable {
    var yellowPercent: Double
    var orangePercent: Double
    var redPercent: Double

    static let `default` = ModexContextThresholds(
        yellowPercent: 55,
        orangePercent: 78,
        redPercent: 90
    )

    func normalized() -> ModexContextThresholds {
        let yellow = min(max(yellowPercent, 1), 95)
        let orange = min(max(orangePercent, yellow + 1), 98)
        let red = min(max(redPercent, orange + 1), 100)
        return ModexContextThresholds(
            yellowPercent: yellow,
            orangePercent: orange,
            redPercent: red
        )
    }
}

enum ModexColorTheme: String, CaseIterable, Identifiable {
    case system
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return ModexStrings.text("config.themeSystem")
        case .black:
            return ModexStrings.text("config.themeBlack")
        }
    }
}

enum ModexLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case de
    case fr
    case es
    case it

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return ModexStrings.text("config.languageSystem")
        case .en:
            return ModexStrings.text("config.languageEnglish")
        case .de:
            return ModexStrings.text("config.languageGerman")
        case .fr:
            return ModexStrings.text("config.languageFrench")
        case .es:
            return ModexStrings.text("config.languageSpanish")
        case .it:
            return ModexStrings.text("config.languageItalian")
        }
    }

    var marker: String {
        switch self {
        case .system:
            return "\u{1F310}"
        case .en:
            return "\u{1F1EC}\u{1F1E7}"
        case .de:
            return "\u{1F1E9}\u{1F1EA}"
        case .fr:
            return "\u{1F1EB}\u{1F1F7}"
        case .es:
            return "\u{1F1EA}\u{1F1F8}"
        case .it:
            return "\u{1F1EE}\u{1F1F9}"
        }
    }

    var shortTitle: String {
        switch self {
        case .system:
            return ModexStrings.text("config.languageSystem")
        case .en:
            return "EN"
        case .de:
            return "DE"
        case .fr:
            return "FR"
        case .es:
            return "ES"
        case .it:
            return "IT"
        }
    }
}

struct ModexParserTuningSettings: Equatable {
    var maximumConcurrentParses: Int
    var chunkSizeKB: Int
    var lineBufferKB: Int
    var sessionIndexLineBufferKB: Int

    static let `default` = ModexParserTuningSettings(
        maximumConcurrentParses: CodexSessionScannerConfiguration.default.maximumConcurrentParses,
        chunkSizeKB: CodexSessionScannerConfiguration.default.chunkSizeBytes / 1024,
        lineBufferKB: CodexSessionScannerConfiguration.default.maximumLineBufferBytes / 1024,
        sessionIndexLineBufferKB: CodexSessionScannerConfiguration.default.sessionIndexMaximumLineBufferBytes / 1024
    )

    static let maximumAllowedConcurrentParses = CodexSessionScannerConfiguration.maximumAllowedConcurrentParses
    static let chunkSizeRangeKB = ClosedRange(
        uncheckedBounds: (
            lower: CodexSessionScannerConfiguration.minimumChunkSizeBytes / 1024,
            upper: CodexSessionScannerConfiguration.maximumAllowedChunkSizeBytes / 1024
        )
    )
    static let lineBufferRangeKB = ClosedRange(
        uncheckedBounds: (
            lower: CodexSessionScannerConfiguration.minimumLineBufferBytes / 1024,
            upper: CodexSessionScannerConfiguration.maximumAllowedLineBufferBytes / 1024
        )
    )
    static let sessionIndexLineBufferRangeKB = ClosedRange(
        uncheckedBounds: (
            lower: CodexSessionScannerConfiguration.minimumSessionIndexLineBufferBytes / 1024,
            upper: CodexSessionScannerConfiguration.maximumAllowedSessionIndexLineBufferBytes / 1024
        )
    )

    func scannerConfiguration(includeArchivedSessions: Bool) -> CodexSessionScannerConfiguration {
        CodexSessionScannerConfiguration(
            maximumConcurrentParses: maximumConcurrentParses,
            chunkSizeBytes: chunkSizeKB * 1024,
            maximumLineBufferBytes: lineBufferKB * 1024,
            sessionIndexMaximumLineBufferBytes: sessionIndexLineBufferKB * 1024,
            includeArchivedSessions: includeArchivedSessions
        )
    }

    func normalized() -> ModexParserTuningSettings {
        let configuration = scannerConfiguration(includeArchivedSessions: false)
        return ModexParserTuningSettings(
            maximumConcurrentParses: configuration.maximumConcurrentParses,
            chunkSizeKB: configuration.chunkSizeBytes / 1024,
            lineBufferKB: configuration.maximumLineBufferBytes / 1024,
            sessionIndexLineBufferKB: configuration.sessionIndexMaximumLineBufferBytes / 1024
        )
    }
}

struct ModexAppSettings: Equatable {
    var scanLimit: Int
    var refreshIntervalSeconds: TimeInterval
    var includeArchivedSessions: Bool
    var scanCacheEnabled: Bool
    var contextThresholds: ModexContextThresholds
    var colorTheme: ModexColorTheme
    var language: ModexLanguage
    var sessionDetailHoverDelayMilliseconds: Int
    var parserTuning: ModexParserTuningSettings

    static let `default` = ModexAppSettings(
        scanLimit: ModexMonitorConfiguration.defaultScanLimit,
        refreshIntervalSeconds: ModexMonitorConfiguration.defaultRefreshIntervalSeconds,
        includeArchivedSessions: false,
        scanCacheEnabled: true,
        contextThresholds: .default,
        colorTheme: .system,
        language: .system,
        sessionDetailHoverDelayMilliseconds: 500,
        parserTuning: .default
    )

    var monitorConfiguration: ModexMonitorConfiguration {
        ModexMonitorConfiguration(
            scanLimit: scanLimit,
            refreshIntervalSeconds: refreshIntervalSeconds,
            scannerConfiguration: parserTuning.scannerConfiguration(
                includeArchivedSessions: includeArchivedSessions
            ),
            scanCacheEnabled: scanCacheEnabled
        )
    }

    func normalized() -> ModexAppSettings {
        ModexAppSettings(
            scanLimit: min(max(scanLimit, 1), 100),
            refreshIntervalSeconds: min(max(refreshIntervalSeconds, 10), 300),
            includeArchivedSessions: includeArchivedSessions,
            scanCacheEnabled: scanCacheEnabled,
            contextThresholds: contextThresholds.normalized(),
            colorTheme: colorTheme,
            language: language,
            sessionDetailHoverDelayMilliseconds: min(max(sessionDetailHoverDelayMilliseconds, 0), 1500),
            parserTuning: parserTuning.normalized()
        )
    }
}

@MainActor
final class ModexSettingsStore {
    private enum Key {
        static let scanLimit = "scanLimit"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let includeArchivedSessions = "includeArchivedSessions"
        static let scanCacheEnabled = "scanCacheEnabled"
        static let yellowPercent = "contextYellowPercent"
        static let orangePercent = "contextOrangePercent"
        static let redPercent = "contextRedPercent"
        static let colorTheme = "colorTheme"
        static let language = ModexStrings.languagePreferenceDefaultsKey
        static let sessionDetailHoverDelayMilliseconds = "sessionDetailHoverDelayMilliseconds"
        static let maximumConcurrentParses = "maximumConcurrentParses"
        static let chunkSizeKB = "chunkSizeKB"
        static let lineBufferKB = "lineBufferKB"
        static let sessionIndexLineBufferKB = "sessionIndexLineBufferKB"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ModexAppSettings {
        let defaults = ModexAppSettings.default
        return ModexAppSettings(
            scanLimit: integer(forKey: Key.scanLimit, defaultValue: defaults.scanLimit),
            refreshIntervalSeconds: double(
                forKey: Key.refreshIntervalSeconds,
                defaultValue: defaults.refreshIntervalSeconds
            ),
            includeArchivedSessions: bool(
                forKey: Key.includeArchivedSessions,
                defaultValue: defaults.includeArchivedSessions
            ),
            scanCacheEnabled: bool(
                forKey: Key.scanCacheEnabled,
                defaultValue: defaults.scanCacheEnabled
            ),
            contextThresholds: ModexContextThresholds(
                yellowPercent: double(
                    forKey: Key.yellowPercent,
                    defaultValue: defaults.contextThresholds.yellowPercent
                ),
                orangePercent: double(
                    forKey: Key.orangePercent,
                    defaultValue: defaults.contextThresholds.orangePercent
                ),
                redPercent: double(
                    forKey: Key.redPercent,
                    defaultValue: defaults.contextThresholds.redPercent
                )
            ),
            colorTheme: colorTheme(forKey: Key.colorTheme, defaultValue: defaults.colorTheme),
            language: language(forKey: Key.language, defaultValue: defaults.language),
            sessionDetailHoverDelayMilliseconds: integer(
                forKey: Key.sessionDetailHoverDelayMilliseconds,
                defaultValue: defaults.sessionDetailHoverDelayMilliseconds
            ),
            parserTuning: ModexParserTuningSettings(
                maximumConcurrentParses: integer(
                    forKey: Key.maximumConcurrentParses,
                    defaultValue: defaults.parserTuning.maximumConcurrentParses
                ),
                chunkSizeKB: integer(
                    forKey: Key.chunkSizeKB,
                    defaultValue: defaults.parserTuning.chunkSizeKB
                ),
                lineBufferKB: integer(
                    forKey: Key.lineBufferKB,
                    defaultValue: defaults.parserTuning.lineBufferKB
                ),
                sessionIndexLineBufferKB: integer(
                    forKey: Key.sessionIndexLineBufferKB,
                    defaultValue: defaults.parserTuning.sessionIndexLineBufferKB
                )
            )
        ).normalized()
    }

    func save(_ settings: ModexAppSettings) {
        let settings = settings.normalized()
        defaults.set(settings.scanLimit, forKey: Key.scanLimit)
        defaults.set(settings.refreshIntervalSeconds, forKey: Key.refreshIntervalSeconds)
        defaults.set(settings.includeArchivedSessions, forKey: Key.includeArchivedSessions)
        defaults.set(settings.scanCacheEnabled, forKey: Key.scanCacheEnabled)
        defaults.set(settings.contextThresholds.yellowPercent, forKey: Key.yellowPercent)
        defaults.set(settings.contextThresholds.orangePercent, forKey: Key.orangePercent)
        defaults.set(settings.contextThresholds.redPercent, forKey: Key.redPercent)
        defaults.set(settings.colorTheme.rawValue, forKey: Key.colorTheme)
        defaults.set(settings.language.rawValue, forKey: Key.language)
        defaults.set(
            settings.sessionDetailHoverDelayMilliseconds,
            forKey: Key.sessionDetailHoverDelayMilliseconds
        )
        defaults.set(settings.parserTuning.maximumConcurrentParses, forKey: Key.maximumConcurrentParses)
        defaults.set(settings.parserTuning.chunkSizeKB, forKey: Key.chunkSizeKB)
        defaults.set(settings.parserTuning.lineBufferKB, forKey: Key.lineBufferKB)
        defaults.set(settings.parserTuning.sessionIndexLineBufferKB, forKey: Key.sessionIndexLineBufferKB)
    }

    private func integer(forKey key: String, defaultValue: Int) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.integer(forKey: key)
    }

    private func double(forKey key: String, defaultValue: Double) -> Double {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.double(forKey: key)
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func colorTheme(forKey key: String, defaultValue: ModexColorTheme) -> ModexColorTheme {
        guard let value = defaults.string(forKey: key) else {
            return defaultValue
        }
        return ModexColorTheme(rawValue: value) ?? defaultValue
    }

    private func language(forKey key: String, defaultValue: ModexLanguage) -> ModexLanguage {
        guard let value = defaults.string(forKey: key) else {
            return defaultValue
        }
        return ModexLanguage(rawValue: value) ?? defaultValue
    }
}
