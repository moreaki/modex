import Foundation

public enum ModexPersistedDefaultsKey {
    public static let maximumConcurrentParses = "maximumConcurrentParses"
    public static let obsoleteScanLimit = "scanLimit"
    public static let intelligenceSpeed = "intelligenceSpeed"
    public static let intelligenceModel = "intelligenceModel"
    public static let intelligenceModelSelectionVersion = "intelligenceModelSelectionVersion"
}

public enum ModexBuiltInMigrations {
    public static func all() -> [ModexStartupMigration] {
        [
            ModexStartupMigration(
                identifier: "version-ledger-baseline",
                introducedIn: ModexApplicationVersion(major: 0, minor: 1, patch: 0)
            ) { _ in
                // Establishes the migration ledger for installations that predate versioning.
            },
            ModexStartupMigration(
                identifier: "adopt-adaptive-read-concurrency",
                introducedIn: ModexApplicationVersion(major: 0, minor: 1, patch: 4)
            ) { context in
                let key = ModexPersistedDefaultsKey.maximumConcurrentParses
                guard context.defaults.object(forKey: key) != nil,
                      context.defaults.integer(forKey: key) == 2
                else {
                    return
                }
                context.defaults.removeObject(forKey: key)
            },
            ModexStartupMigration(
                identifier: "normalize-legacy-preferences",
                introducedIn: ModexApplicationVersion(major: 0, minor: 1, patch: 5)
            ) { context in
                context.defaults.removeObject(
                    forKey: ModexPersistedDefaultsKey.obsoleteScanLimit
                )
                if context.defaults.string(
                    forKey: ModexPersistedDefaultsKey.intelligenceSpeed
                ) == "standard" {
                    context.defaults.set(
                        "default",
                        forKey: ModexPersistedDefaultsKey.intelligenceSpeed
                    )
                }
            },
            ModexStartupMigration(
                identifier: "preserve-saved-model-selection",
                introducedIn: ModexApplicationVersion(major: 0, minor: 1, patch: 8)
            ) { context in
                let key = ModexPersistedDefaultsKey.intelligenceModelSelectionVersion
                guard context.defaults.object(forKey: key) == nil else { return }
                let hadModel = context.defaults.object(forKey: ModexPersistedDefaultsKey.intelligenceModel) != nil
                context.defaults.set(hadModel ? 1 : 0, forKey: key)
            },
        ]
    }
}
