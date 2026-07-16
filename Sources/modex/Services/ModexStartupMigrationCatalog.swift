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
                migrations: ModexBuiltInMigrations.all(),
                context: context
            )
            if result.appliedMigrationIDs.isEmpty == false {
                logger.info("Applied migrations: \(result.appliedMigrationIDs.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            logger.error("Startup migration failed: \(String(describing: error), privacy: .public)")
        }
    }

}
