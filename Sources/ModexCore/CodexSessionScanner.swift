import Foundation

public struct TokenUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

public struct TokenEvent: Equatable, Sendable {
    public let timestamp: Date?
    public let lastUsage: TokenUsage
    public let totalUsage: TokenUsage
    public let modelContextWindow: Int?

    public init(
        timestamp: Date?,
        lastUsage: TokenUsage,
        totalUsage: TokenUsage,
        modelContextWindow: Int?
    ) {
        self.timestamp = timestamp
        self.lastUsage = lastUsage
        self.totalUsage = totalUsage
        self.modelContextWindow = modelContextWindow
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public let fileURL: URL
    public var sessionID: String?
    public var workingDirectory: String?
    public var startedAt: Date?
    public var updatedAt: Date?
    public var tokenEvents: [TokenEvent]
    public var compactionEvents: Int

    public init(fileURL: URL) {
        self.fileURL = fileURL
        sessionID = nil
        workingDirectory = nil
        startedAt = nil
        updatedAt = nil
        tokenEvents = []
        compactionEvents = 0
    }

    public var latestTokenEvent: TokenEvent? {
        tokenEvents.last
    }
}

public struct ModexSummary: Equatable, Sendable {
    public let sessionsScanned: Int
    public let tokenEvents: Int
    public let totalTokens: Int
    public let averageTurnTokens: Int
    public let medianTurnTokens: Int
    public let compactionEvents: Int
    public let contextUsagePercent: Double?
    public let latestSession: SessionSnapshot?

    public init(sessions: [SessionSnapshot]) {
        sessionsScanned = sessions.count
        tokenEvents = sessions.reduce(0) { $0 + $1.tokenEvents.count }
        totalTokens = sessions.reduce(0) { total, session in
            total + (session.latestTokenEvent?.totalUsage.totalTokens ?? 0)
        }

        let turnTotals = sessions.flatMap { session in
            session.tokenEvents.map(\.lastUsage.totalTokens)
        }.filter { $0 > 0 }.sorted()

        if turnTotals.isEmpty {
            averageTurnTokens = 0
            medianTurnTokens = 0
        } else {
            averageTurnTokens = turnTotals.reduce(0, +) / turnTotals.count
            medianTurnTokens = Self.median(turnTotals)
        }

        compactionEvents = sessions.reduce(0) { $0 + $1.compactionEvents }
        latestSession = sessions.max { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast)
        }

        if let event = latestSession?.latestTokenEvent,
           let contextWindow = event.modelContextWindow,
           contextWindow > 0
        {
            contextUsagePercent = min(100.0, Double(event.lastUsage.inputTokens) / Double(contextWindow) * 100.0)
        } else {
            contextUsagePercent = nil
        }
    }

    private static func median(_ values: [Int]) -> Int {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

public final class CodexSessionScanner {
    private let codexHome: URL
    private let iso8601 = ISO8601DateFormatter()

    public init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func scan(limit: Int = 5) throws -> [SessionSnapshot] {
        let files = try sessionFiles()
            .sorted { lhs, rhs in
                modificationDate(lhs) > modificationDate(rhs)
            }
            .prefix(limit)

        return files.compactMap { fileURL in
            try? parse(fileURL: fileURL)
        }
    }

    public func summary(limit: Int = 5) throws -> ModexSummary {
        ModexSummary(sessions: try scan(limit: limit))
    }

    public func sessionFiles() throws -> [URL] {
        var urls: [URL] = []
        for directoryName in ["sessions", "archived_sessions"] {
            let directory = codexHome.appendingPathComponent(directoryName, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                urls.append(url)
            }
        }
        return urls
    }

    public func parse(fileURL: URL) throws -> SessionSnapshot {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var snapshot = SessionSnapshot(fileURL: fileURL)

        for line in text.split(whereSeparator: \.isNewline) {
            parseLine(String(line), into: &snapshot)
        }

        if snapshot.updatedAt == nil {
            snapshot.updatedAt = modificationDate(fileURL)
        }

        return snapshot
    }

    private func parseLine(_ line: String, into snapshot: inout SessionSnapshot) {
        let isRelevant = line.contains("session_meta")
            || line.contains("token_count")
            || line.localizedCaseInsensitiveContains("compact")
        guard isRelevant else {
            return
        }

        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let timestamp = parseDate(object["timestamp"])
        if snapshot.startedAt == nil {
            snapshot.startedAt = timestamp
        }
        snapshot.updatedAt = timestamp ?? snapshot.updatedAt

        guard let payload = object["payload"] as? [String: Any] else {
            return
        }

        if object["type"] as? String == "session_meta" {
            snapshot.sessionID = payload["id"] as? String ?? snapshot.sessionID
            snapshot.workingDirectory = payload["cwd"] as? String ?? snapshot.workingDirectory
        }

        if let contextWindow = payload["model_context_window"] as? Int,
           let info = payload["info"] as? [String: Any]
        {
            appendTokenEvent(info: info, timestamp: timestamp, contextWindow: contextWindow, snapshot: &snapshot)
        } else if let info = payload["info"] as? [String: Any] {
            appendTokenEvent(info: info, timestamp: timestamp, contextWindow: nil, snapshot: &snapshot)
        }

        if line.localizedCaseInsensitiveContains("compact") {
            snapshot.compactionEvents += 1
        }
    }

    private func appendTokenEvent(
        info: [String: Any],
        timestamp: Date?,
        contextWindow: Int?,
        snapshot: inout SessionSnapshot
    ) {
        guard let last = info["last_token_usage"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any]
        else {
            return
        }

        let modelContextWindow = info["model_context_window"] as? Int ?? contextWindow
        snapshot.tokenEvents.append(
            TokenEvent(
                timestamp: timestamp,
                lastUsage: tokenUsage(last),
                totalUsage: tokenUsage(total),
                modelContextWindow: modelContextWindow
            )
        )
    }

    private func tokenUsage(_ object: [String: Any]) -> TokenUsage {
        TokenUsage(
            inputTokens: object["input_tokens"] as? Int ?? 0,
            cachedInputTokens: object["cached_input_tokens"] as? Int ?? 0,
            outputTokens: object["output_tokens"] as? Int ?? 0,
            reasoningOutputTokens: object["reasoning_output_tokens"] as? Int ?? 0,
            totalTokens: object["total_tokens"] as? Int ?? 0
        )
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let value = value as? String else {
            return nil
        }
        if let date = iso8601.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
