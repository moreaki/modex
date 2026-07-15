import Foundation
import SQLite3

struct CodexThreadMetadata: Sendable {
    let sessionID: String
    let fileURL: URL
    let threadName: String?
    let workingDirectory: String?
    let model: String?
    let reasoningEffort: String?
    let source: String?
    let cliVersion: String?
    let modelProvider: String?
    let agentNickname: String?
    let agentRole: String?
    let agentPath: String?
    let parentThreadID: String?
    let threadSource: String?
    let archived: Bool
    let recencyDate: Date
}

struct CodexThreadIndexResult: Sendable {
    let threads: [CodexThreadMetadata]
}

enum CodexThreadIndex {
    static let discoveryMode = "codex-state-db"

    static func recentThreads(
        codexHome: URL,
        limit: Int?,
        includeArchived: Bool
    ) -> CodexThreadIndexResult? {
        if let limit, limit <= 0 {
            return nil
        }

        for databaseURL in threadDatabaseURLs(codexHome: codexHome) {
            if let threads = readThreads(
                databaseURL: databaseURL,
                limit: limit,
                includeArchived: includeArchived
            ) {
                return CodexThreadIndexResult(threads: threads)
            }
        }
        return nil
    }

    private static func threadDatabaseURLs(codexHome: URL) -> [URL] {
        let rootURLs = (try? FileManager.default.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var candidates = rootURLs.filter(isSQLiteDatabase)
        for directoryURL in rootURLs where isDirectory(directoryURL) {
            let nestedURLs = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            candidates.append(contentsOf: nestedURLs.filter(isSQLiteDatabase))
        }

        var seenPaths: Set<String> = []
        return candidates
            .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
            .sorted { lhs, rhs in
                let lhsDate = modificationDate(lhs)
                let rhsDate = modificationDate(rhs)
                if lhsDate == rhsDate {
                    return lhs.path < rhs.path
                }
                return lhsDate > rhsDate
            }
    }

    private static func isSQLiteDatabase(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "sqlite" else {
            return false
        }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func readThreads(
        databaseURL: URL,
        limit: Int?,
        includeArchived: Bool
    ) -> [CodexThreadMetadata]? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer {
            sqlite3_close(database)
        }
        sqlite3_busy_timeout(database, 100)

        guard let schema = ThreadDatabaseSchema(database: database) else {
            return nil
        }

        let limitClause = limit == nil ? "" : "LIMIT ?2"
        let sql = """
        SELECT
            \(schema.select("id")),
            \(schema.select("rollout_path")),
            \(schema.recencyExpression),
            \(schema.select("title")),
            \(schema.select("cwd")),
            \(schema.select("model")),
            \(schema.select("reasoning_effort")),
            \(schema.select("source")),
            \(schema.select("cli_version")),
            \(schema.select("model_provider")),
            \(schema.select("agent_nickname")),
            \(schema.select("agent_role")),
            \(schema.select("agent_path")),
            \(schema.select("parent_thread_id")),
            \(schema.select("thread_source")),
            \(schema.archivedExpression)
        FROM threads
        WHERE \(schema.select("rollout_path")) IS NOT NULL
          AND (?1 = 1 OR \(schema.archivedExpression) = 0)
        ORDER BY \(schema.recencyExpression) DESC
        \(limitClause);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int(statement, 1, includeArchived ? 1 : 0)
        if let limit {
            let candidateLimit = limit > Int.max / 3 ? Int.max : limit * 3
            sqlite3_bind_int64(statement, 2, Int64(candidateLimit))
        }

        var threads: [CodexThreadMetadata] = []
        if let limit {
            threads.reserveCapacity(limit)
        }
        while (limit.map { threads.count < $0 } ?? true), sqlite3_step(statement) == SQLITE_ROW {
            guard let sessionID = text(statement, at: 0),
                  let path = text(statement, at: 1)
            else {
                continue
            }

            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }

            let recencyValue = sqlite3_column_int64(statement, 2)
            let recencyDate = recencyValue > 0
                ? Date(
                    timeIntervalSince1970: TimeInterval(recencyValue)
                        / (schema.recencyIsMilliseconds ? 1_000 : 1)
                )
                : modificationDate(fileURL)
            threads.append(
                CodexThreadMetadata(
                    sessionID: sessionID,
                    fileURL: fileURL,
                    threadName: text(statement, at: 3),
                    workingDirectory: text(statement, at: 4),
                    model: text(statement, at: 5),
                    reasoningEffort: text(statement, at: 6),
                    source: text(statement, at: 7),
                    cliVersion: text(statement, at: 8),
                    modelProvider: text(statement, at: 9),
                    agentNickname: text(statement, at: 10),
                    agentRole: text(statement, at: 11),
                    agentPath: text(statement, at: 12),
                    parentThreadID: text(statement, at: 13),
                    threadSource: text(statement, at: 14),
                    archived: sqlite3_column_int(statement, 15) != 0,
                    recencyDate: recencyDate
                )
            )
        }

        return threads
    }

    private static func text(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        let value = String(cString: pointer)
        return value.isEmpty ? nil : value
    }
}

private struct ThreadDatabaseSchema {
    let columns: Set<String>
    let recencyColumn: String?
    let recencyIsMilliseconds: Bool

    init?(database: OpaquePointer) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads);", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer {
            sqlite3_finalize(statement)
        }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(statement, 1) else {
                continue
            }
            columns.insert(String(cString: pointer))
        }
        guard columns.contains("id"), columns.contains("rollout_path") else {
            return nil
        }

        self.columns = columns
        let recencyCandidates = [
            "recency_at_ms",
            "updated_at_ms",
            "recency_at",
            "updated_at",
            "created_at_ms",
            "created_at",
        ]
        recencyColumn = recencyCandidates.first(where: columns.contains)
        recencyIsMilliseconds = recencyColumn?.hasSuffix("_ms") == true
    }

    var recencyExpression: String {
        recencyColumn.map(quoted) ?? "0"
    }

    var archivedExpression: String {
        columns.contains("archived") ? "COALESCE(\(quoted("archived")), 0)" : "0"
    }

    func select(_ column: String) -> String {
        columns.contains(column) ? quoted(column) : "NULL"
    }

    private func quoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
