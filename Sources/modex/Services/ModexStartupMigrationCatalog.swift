import Foundation
import ModexCore
import OSLog

@MainActor
enum ModexStartupMigrationCatalog {
    private static let logger = Logger(subsystem: "ch.moreaki.modex", category: "migration")

    static func run(defaults: UserDefaults = .standard) {
        do {
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Modex", isDirectory: true)
            let context = ModexMigrationContext(
                defaults: defaults,
                applicationSupportURL: applicationSupportURL
            )
            let result = try ModexStartupMigrator(defaults: defaults).migrate(
                to: .current,
                migrations: migrations,
                context: context
            )
            if result.appliedMigrationIDs.isEmpty == false {
                logger.info("Applied migrations: \(result.appliedMigrationIDs.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            logger.error("Startup migration failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static let migrations: [ModexStartupMigration] = [
        ModexStartupMigration(
            identifier: "version-ledger-baseline",
            introducedIn: ModexApplicationVersion(major: 0, minor: 1, patch: 0)
        ) { _ in
            // Establishes the version ledger. Existing caches are process-local and already start empty.
        },
    ]
}
