import Foundation

public struct ModexMigrationContext {
    public let defaults: UserDefaults
    public let applicationSupportURL: URL

    public init(defaults: UserDefaults, applicationSupportURL: URL) {
        self.defaults = defaults
        self.applicationSupportURL = applicationSupportURL
    }

    public func removeItemIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}

public struct ModexStartupMigration {
    public let identifier: String
    public let introducedIn: ModexApplicationVersion
    private let operation: (ModexMigrationContext) throws -> Void

    public init(
        identifier: String,
        introducedIn: ModexApplicationVersion,
        operation: @escaping (ModexMigrationContext) throws -> Void
    ) {
        self.identifier = identifier
        self.introducedIn = introducedIn
        self.operation = operation
    }

    fileprivate func run(in context: ModexMigrationContext) throws {
        try operation(context)
    }
}

public struct ModexMigrationResult: Equatable, Sendable {
    public let previousVersion: ModexApplicationVersion?
    public let currentVersion: ModexApplicationVersion
    public let appliedMigrationIDs: [String]
    public let recordedCurrentVersion: Bool
}

public final class ModexStartupMigrator {
    public static let lastRunVersionDefaultsKey = "lastRunApplicationVersion"
    public static let appliedMigrationIDsDefaultsKey = "appliedStartupMigrationIDs"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func migrate(
        to currentVersion: ModexApplicationVersion,
        migrations: [ModexStartupMigration],
        context: ModexMigrationContext
    ) throws -> ModexMigrationResult {
        let previousVersion = defaults.string(forKey: Self.lastRunVersionDefaultsKey)
            .flatMap(ModexApplicationVersion.init(string:))

        guard previousVersion.map({ $0 <= currentVersion }) ?? true else {
            return ModexMigrationResult(
                previousVersion: previousVersion,
                currentVersion: currentVersion,
                appliedMigrationIDs: [],
                recordedCurrentVersion: false
            )
        }

        let orderedMigrations = migrations
            .filter { $0.introducedIn <= currentVersion }
            .sorted { lhs, rhs in
                if lhs.introducedIn == rhs.introducedIn {
                    return lhs.identifier < rhs.identifier
                }
                return lhs.introducedIn < rhs.introducedIn
            }
        guard Set(orderedMigrations.map(\.identifier)).count == orderedMigrations.count else {
            throw ModexStartupMigrationError.duplicateIdentifier
        }

        var completedMigrationIDs = Set(
            defaults.stringArray(forKey: Self.appliedMigrationIDsDefaultsKey) ?? []
        )
        if defaults.object(forKey: Self.appliedMigrationIDsDefaultsKey) == nil,
           let previousVersion {
            completedMigrationIDs.formUnion(
                orderedMigrations
                    .filter { $0.introducedIn <= previousVersion }
                    .map(\.identifier)
            )
            recordCompletedMigrationIDs(completedMigrationIDs)
        }

        let pending = orderedMigrations.filter {
            completedMigrationIDs.contains($0.identifier) == false
        }

        var appliedMigrationIDs: [String] = []
        for migration in pending {
            try migration.run(in: context)
            appliedMigrationIDs.append(migration.identifier)
            completedMigrationIDs.insert(migration.identifier)
            recordCompletedMigrationIDs(completedMigrationIDs)
        }

        defaults.set(currentVersion.description, forKey: Self.lastRunVersionDefaultsKey)
        return ModexMigrationResult(
            previousVersion: previousVersion,
            currentVersion: currentVersion,
            appliedMigrationIDs: appliedMigrationIDs,
            recordedCurrentVersion: true
        )
    }

    private func recordCompletedMigrationIDs(_ identifiers: Set<String>) {
        defaults.set(
            identifiers.sorted(),
            forKey: Self.appliedMigrationIDsDefaultsKey
        )
    }
}

public enum ModexStartupMigrationError: Error, Equatable {
    case duplicateIdentifier
}
