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

        for databaseURL in stateDatabaseURLs(codexHome: codexHome) {
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

    private static func stateDatabaseURLs(codexHome: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .compactMap { url -> (version: Int, url: URL)? in
                let name = url.lastPathComponent
                guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else {
                    return nil
                }
                let versionText = name.dropFirst("state_".count).dropLast(".sqlite".count)
                guard let version = Int(versionText) else {
                    return nil
                }
                return (version, url)
            }
            .sorted { $0.version > $1.version }
            .map(\.url)
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

        let limitClause = limit == nil ? "" : "LIMIT ?2"
        let sql = """
        SELECT
            id,
            rollout_path,
            recency_at_ms,
            title,
            cwd,
            model,
            reasoning_effort,
            source,
            cli_version,
            model_provider,
            agent_nickname,
            agent_role,
            agent_path,
            NULL AS parent_thread_id,
            thread_source,
            archived
        FROM threads
        WHERE rollout_path IS NOT NULL
          AND (?1 = 1 OR archived = 0)
        ORDER BY recency_at_ms DESC
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

            let recencyMilliseconds = sqlite3_column_int64(statement, 2)
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
                    recencyDate: Date(timeIntervalSince1970: TimeInterval(recencyMilliseconds) / 1_000)
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
