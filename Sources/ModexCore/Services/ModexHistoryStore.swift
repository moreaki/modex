import Foundation
import SQLite3

public final class ModexHistoryStore: @unchecked Sendable {
    public let databaseURL: URL

    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    public static func defaultDatabaseURL(appName: String = "Modex") throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }

    public func record(summary: ModexSummary, sampledAt: Date = Date()) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try insertScanSample(summary.scanMetrics, sampledAt: sampledAt)
            for session in summary.sessions {
                try insertThreadSample(session, sampledAt: sampledAt)
            }
            try prune()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func snapshot(
        scanLimit: Int = 120,
        threadSampleLimit: Int = 2_000
    ) throws -> ModexHistorySnapshot {
        let scanSamples = try readScanSamples(limit: scanLimit)
        let threadSamples = try readThreadSamples(limit: threadSampleLimit)
        let grouped = Dictionary(grouping: threadSamples, by: \.sessionKey)
            .mapValues { samples in
                samples.sorted { $0.sampledAt < $1.sampledAt }
            }
        return ModexHistorySnapshot(
            scanSamples: scanSamples.sorted { $0.sampledAt < $1.sampledAt },
            threadSamplesByKey: grouped
        )
    }

    private func open() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            throw error("open")
        }
        database = handle
        sqlite3_busy_timeout(handle, 1_500)
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS scan_samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sampled_at REAL NOT NULL,
                duration_seconds REAL NOT NULL,
                bytes_read INTEGER NOT NULL,
                files_selected INTEGER NOT NULL,
                files_parsed INTEGER NOT NULL,
                cache_hits INTEGER NOT NULL,
                cache_misses INTEGER NOT NULL,
                cache_entries INTEGER NOT NULL,
                cache_bytes_saved INTEGER NOT NULL,
                maximum_concurrent_parses INTEGER NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS scan_samples_sampled_at_idx
            ON scan_samples(sampled_at);
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS thread_samples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sampled_at REAL NOT NULL,
                session_key TEXT NOT NULL,
                session_id TEXT,
                thread_name TEXT,
                project_title TEXT,
                source_path TEXT,
                updated_at REAL,
                context_percent REAL,
                context_used_tokens INTEGER,
                context_window INTEGER,
                total_tokens INTEGER NOT NULL,
                median_turn_tokens INTEGER NOT NULL,
                average_turn_tokens INTEGER NOT NULL,
                compactions INTEGER NOT NULL,
                command_events INTEGER NOT NULL,
                failed_command_events INTEGER NOT NULL,
                tool_call_events INTEGER NOT NULL,
                changed_file_events INTEGER NOT NULL,
                cached_input_percent REAL,
                reasoning_output_percent REAL,
                last_turn_duration_ms INTEGER,
                median_turn_duration_ms INTEGER,
                latest_ttft_ms INTEGER,
                fingerprint TEXT NOT NULL,
                UNIQUE(session_key, fingerprint)
            );
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS thread_samples_session_sampled_idx
            ON thread_samples(session_key, sampled_at);
            """
        )
    }

    private func insertScanSample(_ metrics: ScanMetrics?, sampledAt: Date) throws {
        guard let metrics else {
            return
        }

        try withStatement(
            """
            INSERT INTO scan_samples (
                sampled_at,
                duration_seconds,
                bytes_read,
                files_selected,
                files_parsed,
                cache_hits,
                cache_misses,
                cache_entries,
                cache_bytes_saved,
                maximum_concurrent_parses
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            bind(sampledAt, to: statement, at: 1)
            bind(metrics.durationSeconds, to: statement, at: 2)
            bind(metrics.bytesRead, to: statement, at: 3)
            bind(metrics.filesSelected, to: statement, at: 4)
            bind(metrics.filesParsed, to: statement, at: 5)
            bind(metrics.cacheHits, to: statement, at: 6)
            bind(metrics.cacheMisses, to: statement, at: 7)
            bind(metrics.cacheEntries, to: statement, at: 8)
            bind(metrics.cacheBytesSaved, to: statement, at: 9)
            bind(metrics.maximumConcurrentParses, to: statement, at: 10)
            try step(statement)
        }
    }

    private func insertThreadSample(_ session: SessionSnapshot, sampledAt: Date) throws {
        let sessionKey = ModexHistorySnapshot.sessionKey(for: session)
        let fingerprint = [
            session.fileURL.path,
            session.updatedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "",
            "\(session.contextUsedTokens ?? 0)",
            "\(session.totalTokens)",
            "\(session.medianTurnTokens)",
            "\(session.averageTurnTokens)",
            "\(session.compactionEvents)",
            "\(session.commandEvents)",
            "\(session.failedCommandEvents)",
            "\(session.changedFileEvents)",
            "\(session.latestTimeToFirstTokenMilliseconds ?? 0)",
        ]
        .joined(separator: "|")

        try withStatement(
            """
            INSERT OR IGNORE INTO thread_samples (
                sampled_at,
                session_key,
                session_id,
                thread_name,
                project_title,
                source_path,
                updated_at,
                context_percent,
                context_used_tokens,
                context_window,
                total_tokens,
                median_turn_tokens,
                average_turn_tokens,
                compactions,
                command_events,
                failed_command_events,
                tool_call_events,
                changed_file_events,
                cached_input_percent,
                reasoning_output_percent,
                last_turn_duration_ms,
                median_turn_duration_ms,
                latest_ttft_ms,
                fingerprint
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            bind(sampledAt, to: statement, at: 1)
            bind(sessionKey, to: statement, at: 2)
            bind(session.sessionID, to: statement, at: 3)
            bind(session.threadName, to: statement, at: 4)
            bind(projectTitle(for: session), to: statement, at: 5)
            bind(session.fileURL.path, to: statement, at: 6)
            bind(session.updatedAt, to: statement, at: 7)
            bind(session.contextUsagePercent, to: statement, at: 8)
            bind(session.contextUsedTokens, to: statement, at: 9)
            bind(session.contextWindow, to: statement, at: 10)
            bind(session.totalTokens, to: statement, at: 11)
            bind(session.medianTurnTokens, to: statement, at: 12)
            bind(session.averageTurnTokens, to: statement, at: 13)
            bind(session.compactionEvents, to: statement, at: 14)
            bind(session.commandEvents, to: statement, at: 15)
            bind(session.failedCommandEvents, to: statement, at: 16)
            bind(session.toolCallEvents, to: statement, at: 17)
            bind(session.changedFileEvents, to: statement, at: 18)
            bind(session.cachedInputPercent, to: statement, at: 19)
            bind(session.reasoningOutputPercent, to: statement, at: 20)
            bind(session.lastTurnDurationMilliseconds, to: statement, at: 21)
            bind(session.medianTurnDurationMilliseconds, to: statement, at: 22)
            bind(session.latestTimeToFirstTokenMilliseconds, to: statement, at: 23)
            bind(fingerprint, to: statement, at: 24)
            try step(statement)
        }
    }

    private func readScanSamples(limit: Int) throws -> [ModexScanHistorySample] {
        try read(
            """
            SELECT
                id,
                sampled_at,
                duration_seconds,
                bytes_read,
                files_selected,
                files_parsed,
                cache_hits,
                cache_misses,
                cache_entries,
                cache_bytes_saved,
                maximum_concurrent_parses
            FROM scan_samples
            ORDER BY sampled_at DESC
            LIMIT ?;
            """,
            limit: limit
        ) { statement in
            ModexScanHistorySample(
                id: sqlite3_column_int64(statement, 0),
                sampledAt: date(statement, 1) ?? .distantPast,
                durationSeconds: sqlite3_column_double(statement, 2),
                bytesRead: int(statement, 3),
                filesSelected: int(statement, 4),
                filesParsed: int(statement, 5),
                cacheHits: int(statement, 6),
                cacheMisses: int(statement, 7),
                cacheEntries: int(statement, 8),
                cacheBytesSaved: int(statement, 9),
                maximumConcurrentParses: int(statement, 10)
            )
        }
    }

    private func readThreadSamples(limit: Int) throws -> [ModexThreadHistorySample] {
        try read(
            """
            SELECT
                id,
                sampled_at,
                session_key,
                session_id,
                thread_name,
                project_title,
                source_path,
                updated_at,
                context_percent,
                context_used_tokens,
                context_window,
                total_tokens,
                median_turn_tokens,
                average_turn_tokens,
                compactions,
                command_events,
                failed_command_events,
                tool_call_events,
                changed_file_events,
                cached_input_percent,
                reasoning_output_percent,
                last_turn_duration_ms,
                median_turn_duration_ms,
                latest_ttft_ms
            FROM thread_samples
            ORDER BY sampled_at DESC
            LIMIT ?;
            """,
            limit: limit
        ) { statement in
            ModexThreadHistorySample(
                id: sqlite3_column_int64(statement, 0),
                sampledAt: date(statement, 1) ?? .distantPast,
                sessionKey: text(statement, 2) ?? "",
                sessionID: text(statement, 3),
                threadName: text(statement, 4),
                projectTitle: text(statement, 5),
                sourcePath: text(statement, 6),
                updatedAt: date(statement, 7),
                contextPercent: double(statement, 8),
                contextUsedTokens: optionalInt(statement, 9),
                contextWindow: optionalInt(statement, 10),
                totalTokens: int(statement, 11),
                medianTurnTokens: int(statement, 12),
                averageTurnTokens: int(statement, 13),
                compactions: int(statement, 14),
                commandEvents: int(statement, 15),
                failedCommandEvents: int(statement, 16),
                toolCallEvents: int(statement, 17),
                changedFileEvents: int(statement, 18),
                cachedInputPercent: double(statement, 19),
                reasoningOutputPercent: double(statement, 20),
                lastTurnDurationMilliseconds: optionalInt(statement, 21),
                medianTurnDurationMilliseconds: optionalInt(statement, 22),
                latestTimeToFirstTokenMilliseconds: optionalInt(statement, 23)
            )
        }
    }

    private func prune() throws {
        let oldest = Date().addingTimeInterval(-60 * 24 * 60 * 60).timeIntervalSince1970
        try withStatement("DELETE FROM scan_samples WHERE sampled_at < ?;") { statement in
            sqlite3_bind_double(statement, 1, oldest)
            try step(statement)
        }
        try withStatement("DELETE FROM thread_samples WHERE sampled_at < ?;") { statement in
            sqlite3_bind_double(statement, 1, oldest)
            try step(statement)
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw error("database unavailable")
        }
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &message)
        if status != SQLITE_OK {
            let text = message.map { String(cString: $0) } ?? sqliteErrorMessage
            sqlite3_free(message)
            throw ModexHistoryStoreError.sqlite(text)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        guard let database else {
            throw error("database unavailable")
        }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw error("prepare")
        }
        defer {
            sqlite3_finalize(statement)
        }
        try body(statement)
    }

    private func read<T>(_ sql: String, limit: Int, row: (OpaquePointer) throws -> T) throws -> [T] {
        var values: [T] = []
        try withStatement(sql) { statement in
            bind(limit, to: statement, at: 1)
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_ROW {
                    values.append(try row(statement))
                    continue
                }
                if status == SQLITE_DONE {
                    break
                }
                throw error("read")
            }
        }
        return values
    }

    private func step(_ statement: OpaquePointer) throws {
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else {
            throw error("step")
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func bind(_ value: Int?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    private func bind(_ value: Double?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ value: Date?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    private func int(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    private func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : int(statement, index)
    }

    private func double(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: pointer)
    }

    private func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        double(statement, index).map(Date.init(timeIntervalSince1970:))
    }

    private func projectTitle(for session: SessionSnapshot) -> String? {
        guard let workingDirectory = session.workingDirectory, workingDirectory.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    private func error(_ operation: String) -> ModexHistoryStoreError {
        ModexHistoryStoreError.sqlite("\(operation): \(sqliteErrorMessage)")
    }

    private var sqliteErrorMessage: String {
        guard let database else {
            return "SQLite database is not open"
        }
        return String(cString: sqlite3_errmsg(database))
    }
}

public enum ModexHistoryStoreError: Error, Equatable, Sendable {
    case sqlite(String)
}
