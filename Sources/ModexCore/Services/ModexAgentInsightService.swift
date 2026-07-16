import Foundation

public struct ModexAgentInsightRequest: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let privacyMode: String
    public let sourceInsightID: String
    public let sourceFingerprint: String
    public let signal: ModexAgentSignalPayload
    public let session: ModexAgentSessionPayload?
    public let scan: ModexAgentScanPayload?
    public let history: [ModexAgentHistoryPoint]
    public let evidenceIDs: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        privacyMode: String,
        sourceInsightID: String,
        sourceFingerprint: String,
        signal: ModexAgentSignalPayload,
        session: ModexAgentSessionPayload?,
        scan: ModexAgentScanPayload?,
        history: [ModexAgentHistoryPoint],
        evidenceIDs: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.privacyMode = privacyMode
        self.sourceInsightID = sourceInsightID
        self.sourceFingerprint = sourceFingerprint
        self.signal = signal
        self.session = session
        self.scan = scan
        self.history = history
        self.evidenceIDs = evidenceIDs
    }
}

public struct ModexAgentSignalPayload: Equatable, Codable, Sendable {
    public let id: String
    public let kind: String
    public let severity: Int
    public let analysisState: String
    public let primaryValue: Double?
    public let secondaryValue: Double?
    public let count: Int?
    public let evidenceCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case severity
        case analysisState = "analysis_state"
        case primaryValue
        case secondaryValue
        case count
        case evidenceCount
    }
}

public struct ModexAgentSessionPayload: Equatable, Codable, Sendable {
    public let sessionID: String?
    public let threadName: String?
    public let projectTitle: String?
    public let model: String?
    public let reasoningEffort: String?
    public let realtimeActive: Bool?
    public let updatedAt: Date?
    public let contextPercent: Double?
    public let contextUsedTokens: Int?
    public let contextWindow: Int?
    public let totalTokens: Int
    public let medianTurnTokens: Int
    public let averageTurnTokens: Int
    public let compactions: Int
    public let commandEvents: Int
    public let failedCommandEvents: Int
    public let failedCommands: [CommandFailureSummary]
    public let toolCallEvents: Int
    public let changedFileEvents: Int
    public let cachedInputPercent: Double?
    public let reasoningOutputPercent: Double?
    public let lastTurnDurationMilliseconds: Int?
    public let medianTurnDurationMilliseconds: Int?
    public let latestTimeToFirstTokenMilliseconds: Int?
}

public struct ModexAgentScanPayload: Equatable, Codable, Sendable {
    public let parserMode: String
    public let filesSelected: Int
    public let filesParsed: Int
    public let bytesRead: Int
    public let durationSeconds: Double
    public let maximumConcurrentParses: Int
    public let configuredMaximumConcurrentParses: Int
    public let cacheEnabled: Bool
    public let cacheHits: Int
    public let cacheMisses: Int
    public let cacheEntries: Int
    public let cacheBytesSaved: Int
}

public struct ModexAgentHistoryPoint: Equatable, Codable, Sendable {
    public let sampledAt: Date
    public let contextPercent: Double?
    public let totalTokens: Int
    public let medianTurnTokens: Int
    public let averageTurnTokens: Int
    public let failedCommandEvents: Int
    public let compactions: Int
}

public struct ModexAgentInsightEvidenceBuilder: Sendable {
    public init() {}

    public func request(
        for insight: ModexInsight,
        summary: ModexSummary,
        history: ModexHistorySnapshot?,
        includeCommandNames: Bool = true
    ) -> ModexAgentInsightRequest {
        let session = session(for: insight, summary: summary)
        let historyPoints = session
            .map { history?.samples(for: $0) ?? [] }
            .map { samples in
                samples.suffix(12).map {
                    ModexAgentHistoryPoint(
                        sampledAt: $0.sampledAt,
                        contextPercent: $0.contextPercent,
                        totalTokens: $0.totalTokens,
                        medianTurnTokens: $0.medianTurnTokens,
                        averageTurnTokens: $0.averageTurnTokens,
                        failedCommandEvents: $0.failedCommandEvents,
                        compactions: $0.compactions
                    )
                }
            } ?? []

        var evidenceIDs = [
            "signal:\(insight.kind.rawValue)",
            "severity:\(insight.severity.rawValue)",
        ]
        if let sessionID = session?.sessionID {
            evidenceIDs.append("session:\(sessionID)")
        }
        if let scan = summary.scanMetrics {
            evidenceIDs.append("scan:\(scan.filesParsed)-files")
        }
        if historyPoints.isEmpty == false {
            evidenceIDs.append("history:\(historyPoints.count)-samples")
        }

        return ModexAgentInsightRequest(
            privacyMode: includeCommandNames ? "metrics_and_sanitized_commands" : "metrics_only",
            sourceInsightID: insight.id,
            sourceFingerprint: insight.agentFingerprint,
            signal: ModexAgentSignalPayload(
                id: insight.id,
                kind: insight.kind.rawValue,
                severity: insight.severity.rawValue,
                analysisState: "needs_interpretation",
                primaryValue: insight.primaryValue,
                secondaryValue: insight.secondaryValue,
                count: insight.count,
                evidenceCount: insight.evidenceCount
            ),
            session: session.map { payload(for: $0, includeCommandNames: includeCommandNames) },
            scan: summary.scanMetrics.map(Self.scanPayload),
            history: historyPoints,
            evidenceIDs: evidenceIDs
        )
    }

    public func syntheticRequest() -> ModexAgentInsightRequest {
        ModexAgentInsightRequest(
            privacyMode: "metrics_only",
            sourceInsightID: "connection-test",
            sourceFingerprint: "connection-test",
            signal: ModexAgentSignalPayload(
                id: "connection-test",
                kind: "failedCommands",
                severity: ModexInsightSeverity.notice.rawValue,
                analysisState: "connection_test",
                primaryValue: 2,
                secondaryValue: 12,
                count: 2,
                evidenceCount: 3
            ),
            session: ModexAgentSessionPayload(
                sessionID: "synthetic",
                threadName: "Synthetic connection test",
                projectTitle: "modex",
                model: "gpt-5.5",
                reasoningEffort: "high",
                realtimeActive: false,
                updatedAt: Date(),
                contextPercent: 64,
                contextUsedTokens: 164_000,
                contextWindow: 258_400,
                totalTokens: 2_400_000,
                medianTurnTokens: 94_000,
                averageTurnTokens: 112_000,
                compactions: 1,
                commandEvents: 12,
                failedCommandEvents: 2,
                failedCommands: [
                    CommandFailureSummary(timestamp: Date(), commandName: "swift", exitCode: 1),
                ],
                toolCallEvents: 8,
                changedFileEvents: 14,
                cachedInputPercent: 82,
                reasoningOutputPercent: 18,
                lastTurnDurationMilliseconds: 180_000,
                medianTurnDurationMilliseconds: 96_000,
                latestTimeToFirstTokenMilliseconds: 1_500
            ),
            scan: nil,
            history: [],
            evidenceIDs: ["signal:failedCommands", "session:synthetic", "command:swift"]
        )
    }

    private func session(for insight: ModexInsight, summary: ModexSummary) -> SessionSnapshot? {
        if let sessionKey = insight.sessionKey {
            return summary.sessions.first {
                ModexHistorySnapshot.sessionKey(for: $0) == sessionKey
            }
        }
        if let sessionID = insight.sessionID {
            return summary.sessions.first { $0.sessionID == sessionID }
        }
        return nil
    }

    private func payload(
        for session: SessionSnapshot,
        includeCommandNames: Bool
    ) -> ModexAgentSessionPayload {
        ModexAgentSessionPayload(
            sessionID: session.sessionID,
            threadName: session.threadName,
            projectTitle: projectTitle(for: session),
            model: session.model,
            reasoningEffort: session.reasoningEffort,
            realtimeActive: session.realtimeActive,
            updatedAt: session.updatedAt,
            contextPercent: session.contextUsagePercent,
            contextUsedTokens: session.contextUsedTokens,
            contextWindow: session.contextWindow,
            totalTokens: session.totalTokens,
            medianTurnTokens: session.medianTurnTokens,
            averageTurnTokens: session.averageTurnTokens,
            compactions: session.compactionEvents,
            commandEvents: session.commandEvents,
            failedCommandEvents: session.failedCommandEvents,
            failedCommands: includeCommandNames ? session.failedCommandSummaries : [],
            toolCallEvents: session.toolCallEvents,
            changedFileEvents: session.changedFileEvents,
            cachedInputPercent: session.cachedInputPercent,
            reasoningOutputPercent: session.reasoningOutputPercent,
            lastTurnDurationMilliseconds: session.lastTurnDurationMilliseconds,
            medianTurnDurationMilliseconds: session.medianTurnDurationMilliseconds,
            latestTimeToFirstTokenMilliseconds: session.latestTimeToFirstTokenMilliseconds
        )
    }

    private static func scanPayload(for metrics: ScanMetrics) -> ModexAgentScanPayload {
        ModexAgentScanPayload(
            parserMode: metrics.parserMode,
            filesSelected: metrics.filesSelected,
            filesParsed: metrics.filesParsed,
            bytesRead: metrics.bytesRead,
            durationSeconds: metrics.durationSeconds,
            maximumConcurrentParses: metrics.maximumConcurrentParses,
            configuredMaximumConcurrentParses: metrics.configuredMaximumConcurrentParses,
            cacheEnabled: metrics.cacheEnabled,
            cacheHits: metrics.cacheHits,
            cacheMisses: metrics.cacheMisses,
            cacheEntries: metrics.cacheEntries,
            cacheBytesSaved: metrics.cacheBytesSaved
        )
    }

    private func projectTitle(for session: SessionSnapshot) -> String? {
        CodexProjectIdentity.resolve(for: session).suggestedName
    }
}

public struct LocalCodexInsightConfiguration: Equatable, Sendable {
    public let executablePath: String
    public let timeoutSeconds: Int
    public let model: String
    public let reasoningEffort: String
    public let serviceTier: String

    public init(
        executablePath: String = "codex",
        timeoutSeconds: Int = 45,
        model: String = "gpt-5.3-codex-spark",
        reasoningEffort: String = "high",
        serviceTier: String = "default"
    ) {
        self.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "codex"
            : executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeoutSeconds = min(max(timeoutSeconds, 5), 180)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gpt-5.3-codex-spark"
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEffort = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reasoningEffort = reasoningEffort.isEmpty ? "high" : reasoningEffort
        let serviceTier = serviceTier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serviceTier = serviceTier.isEmpty ? "default" : serviceTier
    }

    func commandArguments(schemaPath: String, outputPath: String) -> [String] {
        [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--color",
            "never",
            "--model",
            model,
            "--config",
            "model_reasoning_effort=\"\(reasoningEffort)\"",
            serviceTier == "default" ? "--disable" : "--enable",
            "fast_mode",
            "--config",
            "service_tier=\"\(serviceTier)\"",
            "--output-schema",
            schemaPath,
            "-o",
            outputPath,
            "-",
        ]
    }
}

public struct LocalCodexAgentInsightService: Sendable {
    private let configuration: LocalCodexInsightConfiguration

    public init(
        configuration: LocalCodexInsightConfiguration = LocalCodexInsightConfiguration()
    ) {
        self.configuration = configuration
    }

    public func testConnection() async throws -> ModexAgentInsightResult {
        try await analyze(request: ModexAgentInsightEvidenceBuilder().syntheticRequest())
    }

    public func analyze(request: ModexAgentInsightRequest) async throws -> ModexAgentInsightResult {
        let output = try await runCodex(request: request)
        let response = try Self.decodeResponse(output)
        return ModexAgentInsightResult(
            sourceInsightID: request.sourceInsightID,
            sourceFingerprint: request.sourceFingerprint,
            generatedAt: Date(),
            provider: "local-codex",
            title: Self.clipped(response.title, maxLength: 36),
            summary: Self.clipped(response.summary, maxLength: 130),
            category: response.category,
            severity: response.severity,
            confidence: response.confidence,
            suggestedAction: Self.clipped(response.suggestedAction, maxLength: 90),
            evidenceIDs: response.evidenceIDs
        )
    }

    private func runCodex(request: ModexAgentInsightRequest) async throws -> String {
        try await Task.detached(priority: .utility) {
            try runCodexBlocking(request: request)
        }
        .value
    }

    private func runCodexBlocking(request: ModexAgentInsightRequest) throws -> String {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("modex-codex-insight-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        let schemaURL = root.appendingPathComponent("insight.schema.json")
        let outputURL = root.appendingPathComponent("insight-output.json")
        let stdoutURL = root.appendingPathComponent("codex.out")
        let stderrURL = root.appendingPathComponent("codex.err")
        try Self.outputSchema.write(to: schemaURL, atomically: true, encoding: .utf8)
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        let codexArgs = configuration.commandArguments(
            schemaPath: schemaURL.path,
            outputPath: outputURL.path
        )
        if configuration.executablePath.contains("/") {
            process.executableURL = URL(fileURLWithPath: configuration.executablePath)
            process.arguments = codexArgs
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [configuration.executablePath] + codexArgs
        }
        process.currentDirectoryURL = root
        process.standardOutput = stdout
        process.standardError = stderr

        let input = Pipe()
        process.standardInput = input

        do {
            try process.run()
        } catch {
            throw ModexAgentInsightServiceError.codexUnavailable(configuration.executablePath)
        }

        try input.fileHandleForWriting.write(contentsOf: Data(prompt(for: request).utf8))
        try input.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(TimeInterval(configuration.timeoutSeconds))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw ModexAgentInsightServiceError.timedOut(configuration.timeoutSeconds)
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            throw ModexAgentInsightServiceError.processFailed(
                Int(process.terminationStatus),
                stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            throw ModexAgentInsightServiceError.missingOutput(stderrText)
        }
        return try String(contentsOf: outputURL, encoding: .utf8)
    }

    private func prompt(for request: ModexAgentInsightRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let requestJSON = String(decoding: try encoder.encode(request), as: UTF8.self)
        return """
        You are Modex Intelligence, a concise diagnostic assistant for a macOS Codex monitoring app.

        Analyze only the JSON metrics below. Do not infer prompt text, private code content, user intent, or causes that are not supported by the evidence.
        Return a single JSON object that matches the supplied schema.
        Write for a compact table row:
        - title: 2 to 5 words, plain and specific.
        - summary: one short diagnosis sentence, under 120 characters when possible.
        - suggested_action: one concrete next step, under 80 characters when possible.
        Keep the wording calm, specific, and useful for a developer monitoring local Codex sessions.
        Do not mention Modex UI states, connection states, "agentUnavailable", "Needs Codex", "Limited", or the analysis_state field.
        Do not restate every count or date unless it changes the recommended action.
        Use evidence_ids from the request wherever possible.

        Metrics:
        \(requestJSON)
        """
    }

    private static func decodeResponse(_ rawOutput: String) throws -> AgentResponse {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = fencedJSON(in: trimmed) ?? trimmed
        guard let data = jsonText.data(using: .utf8) else {
            throw ModexAgentInsightServiceError.invalidOutput("Output is not UTF-8.")
        }
        do {
            let response = try JSONDecoder().decode(AgentResponse.self, from: data)
            guard response.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  response.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  response.suggestedAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                throw ModexAgentInsightServiceError.invalidOutput("Insight fields were empty.")
            }
            return response
        } catch let error as ModexAgentInsightServiceError {
            throw error
        } catch {
            throw ModexAgentInsightServiceError.invalidOutput(String(describing: error))
        }
    }

    private static func fencedJSON(in text: String) -> String? {
        guard text.hasPrefix("```") else {
            return nil
        }
        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 3 else {
            return nil
        }
        lines.removeFirst()
        if lines.last?.hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func clipped(_ value: String, maxLength: Int) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max(maxLength - 3, 1))
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static let outputSchema = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "additionalProperties": false,
      "required": ["title", "summary", "category", "severity", "confidence", "suggested_action", "evidence_ids"],
      "properties": {
        "title": {
          "type": "string",
          "minLength": 3,
          "maxLength": 36
        },
        "summary": {
          "type": "string",
          "minLength": 12,
          "maxLength": 130
        },
        "category": {
          "type": "string",
          "enum": ["token_economy", "context_pressure", "failure_cost", "command_health", "latency", "compaction", "cache_reuse", "scan_health", "other"]
        },
        "severity": {
          "type": "string",
          "enum": ["info", "notice", "warning", "critical"]
        },
        "confidence": {
          "type": "number",
          "minimum": 0,
          "maximum": 1
        },
        "suggested_action": {
          "type": "string",
          "minLength": 8,
          "maxLength": 90
        },
        "evidence_ids": {
          "type": "array",
          "items": { "type": "string" },
          "minItems": 1,
          "maxItems": 8
        }
      }
    }
    """

    private struct AgentResponse: Decodable {
        let title: String
        let summary: String
        let category: String
        let severity: String
        let confidence: Double
        let suggestedAction: String
        let evidenceIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case title
            case summary
            case category
            case severity
            case confidence
            case suggestedAction = "suggested_action"
            case evidenceIDs = "evidence_ids"
        }
    }
}

public enum ModexAgentInsightServiceError: Error, Equatable, CustomStringConvertible, Sendable {
    case codexUnavailable(String)
    case timedOut(Int)
    case processFailed(Int, String)
    case missingOutput(String)
    case invalidOutput(String)

    public var description: String {
        switch self {
        case .codexUnavailable(let path):
            return "Codex executable was not found: \(path)"
        case .timedOut(let seconds):
            return "Codex insight request timed out after \(seconds)s."
        case .processFailed(let status, let detail):
            return detail.isEmpty
                ? "Codex exited with status \(status)."
                : "Codex exited with status \(status): \(detail)"
        case .missingOutput(let detail):
            return detail.isEmpty
                ? "Codex did not write a structured insight result."
                : "Codex did not write a structured insight result: \(detail)"
        case .invalidOutput(let detail):
            return "Codex returned invalid insight JSON: \(detail)"
        }
    }
}
