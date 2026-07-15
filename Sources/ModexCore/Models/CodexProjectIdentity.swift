import Foundation

public enum CodexThreadScope: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case project
    case task

    public var id: String { rawValue }

    public static func resolve(for session: SessionSnapshot) -> CodexThreadScope {
        if let threadScope = session.threadScope {
            return threadScope
        }

        switch CodexProjectIdentity.resolve(
            workingDirectory: session.workingDirectory,
            gitOriginURL: session.gitOriginURL
        ).kind {
        case .codexTasks, .unknown:
            return .task
        case .repository, .directory:
            return .project
        }
    }
}

public struct CodexProjectIdentity: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case repository
        case codexTasks
        case directory
        case unknown
    }

    public let id: String
    public let suggestedName: String?
    public let kind: Kind

    public static func resolve(for session: SessionSnapshot) -> CodexProjectIdentity {
        if session.threadScope == .task {
            let taskScope = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            return CodexProjectIdentity(
                id: "codex-tasks:\(taskScope.path)",
                suggestedName: "Codex",
                kind: .codexTasks
            )
        }

        return resolve(
            workingDirectory: session.workingDirectory,
            gitOriginURL: session.gitOriginURL,
            recognizeTaskLocations: session.threadScope != .project
        )
    }

    public static func resolve(
        workingDirectory: String?,
        gitOriginURL: String? = nil
    ) -> CodexProjectIdentity {
        resolve(
            workingDirectory: workingDirectory,
            gitOriginURL: gitOriginURL,
            recognizeTaskLocations: true
        )
    }

    private static func resolve(
        workingDirectory: String?,
        gitOriginURL: String?,
        recognizeTaskLocations: Bool
    ) -> CodexProjectIdentity {
        if let repository = repositoryIdentity(from: gitOriginURL) {
            return CodexProjectIdentity(
                id: "repository:\(repository.id)",
                suggestedName: repository.name,
                kind: .repository
            )
        }

        guard let workingDirectory = nonEmpty(workingDirectory) else {
            return CodexProjectIdentity(id: "__codex__", suggestedName: nil, kind: .unknown)
        }

        let directoryURL = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        if recognizeTaskLocations, let tasksScope = codexTasksScope(for: directoryURL) {
            return CodexProjectIdentity(
                id: "codex-tasks:\(tasksScope.path)",
                suggestedName: "Codex",
                kind: .codexTasks
            )
        }

        let name = directoryURL.lastPathComponent
        return CodexProjectIdentity(
            id: "directory:\(directoryURL.path)",
            suggestedName: name.isEmpty ? workingDirectory : name,
            kind: .directory
        )
    }

    private static func repositoryIdentity(from value: String?) -> (id: String, name: String)? {
        guard var origin = nonEmpty(value) else {
            return nil
        }
        origin = origin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let host: String?
        let path: String
        if let components = URLComponents(string: origin),
           let scheme = components.scheme,
           scheme.isEmpty == false,
           let componentHost = components.host
        {
            host = componentHost
            path = components.path
        } else if let atIndex = origin.lastIndex(of: "@"),
                  let colonIndex = origin[atIndex...].firstIndex(of: ":")
        {
            host = String(origin[origin.index(after: atIndex)..<colonIndex])
            path = String(origin[origin.index(after: colonIndex)...])
        } else {
            host = nil
            path = origin
        }

        var normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.lowercased().hasSuffix(".git") {
            normalizedPath.removeLast(4)
        }
        guard let name = normalizedPath.split(separator: "/").last.map(String.init), name.isEmpty == false else {
            return nil
        }

        let normalizedID = [host, normalizedPath]
            .compactMap { nonEmpty($0) }
            .joined(separator: "/")
            .lowercased()
        return normalizedID.isEmpty ? nil : (normalizedID, name)
    }

    private static func codexTasksScope(for directoryURL: URL) -> URL? {
        if standardTaskLocationPaths.contains(directoryURL.path) {
            return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        }

        let parent = directoryURL.deletingLastPathComponent()
        if isDateDirectory(directoryURL.lastPathComponent), parent.lastPathComponent == "Codex" {
            return userScope(forCodexRoot: parent)
        }

        let grandparent = parent.deletingLastPathComponent()
        guard isDateDirectory(parent.lastPathComponent), grandparent.lastPathComponent == "Codex" else {
            return nil
        }
        return userScope(forCodexRoot: grandparent)
    }

    private static func userScope(forCodexRoot codexRoot: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if codexRoot.path == home.path || codexRoot.path.hasPrefix(home.path + "/") {
            return home
        }

        let documentsDirectory = codexRoot.deletingLastPathComponent()
        if documentsDirectory.lastPathComponent == "Documents" {
            return documentsDirectory.deletingLastPathComponent()
        }
        return codexRoot
    }

    private static func isDateDirectory(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2
        else {
            return false
        }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        return value
    }

    private static let standardTaskLocationPaths: Set<String> = {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        var paths: Set<String> = [home.path]
        for directory in [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory, .downloadsDirectory] {
            paths.formUnion(
                fileManager.urls(for: directory, in: .userDomainMask)
                    .map { $0.standardizedFileURL.path }
            )
        }
        return paths
    }()
}
