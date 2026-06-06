import Foundation
import Testing
@testable import ModexCore

@Test func parsesTokenEventsAndComputesSummary() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("session.jsonl")
    let jsonl = """
    {"timestamp":"2026-06-05T09:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp/project"}}
    {"timestamp":"2026-06-05T09:00:30.000Z","type":"turn_context","payload":{"model":"gpt-5.5","reasoning_effort":"high","effort":"medium","summary":"auto","realtime_active":true}}
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"model_context_window":1000}}}
    {"timestamp":"2026-06-05T09:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":7,"total_tokens":350},"total_token_usage":{"input_tokens":400,"cached_input_tokens":30,"output_tokens":70,"reasoning_output_tokens":12,"total_tokens":470},"model_context_window":1000},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":9.0,"window_minutes":300,"resets_at":1775764988},"secondary":{"used_percent":19.0,"window_minutes":10080,"resets_at":1776209285},"credits":null,"plan_type":"pro"}}}
    {"timestamp":"2026-06-05T09:03:00.000Z","type":"event_msg","payload":{"type":"post_compact","trigger":"auto"}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)
    try writeSessionIndex(
        ["thread-1": "Explain empty content type"],
        to: temporaryDirectory.appendingPathComponent(".codex")
    )

    let summary = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).summary()

    #expect(summary.sessionsScanned == 1)
    #expect(summary.tokenEvents == 2)
    #expect(summary.totalTokens == 470)
    #expect(summary.medianTurnTokens == 235)
    #expect(summary.averageTurnTokens == 235)
    #expect(summary.compactionEvents == 1)
    #expect(summary.latestSession?.sessionID == "thread-1")
    #expect(summary.latestSession?.threadName == "Explain empty content type")
    #expect(summary.latestSession?.workingDirectory == "/tmp/project")
    #expect(summary.latestSession?.model == "gpt-5.5")
    #expect(summary.latestSession?.reasoningEffort == "high")
    #expect(summary.latestSession?.summaryMode == "auto")
    #expect(summary.latestSession?.realtimeActive == true)
    #expect(summary.latestSession?.totalTokens == 470)
    #expect(summary.latestSession?.medianTurnTokens == 235)
    #expect(summary.latestSession?.averageTurnTokens == 235)
    #expect(summary.latestSession?.contextUsagePercent == 30.0)
    #expect(summary.latestSession?.contextLeftPercent == 70.0)
    #expect(summary.latestSession?.contextUsedTokens == 300)
    #expect(summary.latestSession?.contextWindow == 1000)
    #expect(summary.latestSession?.cachedInputPercent == 7.5)
    #expect(summary.latestSession?.reasoningOutputPercent == 12.0 / 82.0 * 100.0)
    #expect(summary.latestSession?.averageContextGrowthPerTurnTokens == 200)
    #expect(summary.latestSession?.latestContextGrowthTokens == 300)
    #expect(summary.latestSession?.latestRateLimits?.primary?.usedPercent == 9.0)
    #expect(summary.latestSession?.latestRateLimits?.primary?.leftPercent == 91.0)
    #expect(summary.latestSession?.latestRateLimits?.primary?.windowMinutes == 300)
    #expect(summary.latestSession?.latestRateLimits?.primary?.resetsAt != nil)
    #expect(summary.latestSession?.latestRateLimits?.secondary?.usedPercent == 19.0)
    #expect(summary.latestSession?.latestRateLimits?.secondary?.leftPercent == 81.0)
    #expect(summary.latestSession?.latestRateLimits?.secondary?.windowMinutes == 10080)
    #expect(summary.latestSession?.latestRateLimits?.planType == "pro")
    #expect(summary.contextUsagePercent == 30.0)
    #expect(summary.contextLeftPercent == 70.0)
    #expect(summary.latestRateLimits?.primary?.leftPercent == 91.0)
    #expect(summary.latestRateLimits?.secondary?.leftPercent == 81.0)
    #expect(summary.sessions.count == 1)
    #expect(summary.scanMetrics?.filesSelected == 1)
    #expect(summary.scanMetrics?.filesParsed == 1)
    #expect(summary.scanMetrics?.fileMetrics.first?.sessionID == "thread-1")
    #expect(summary.scanMetrics?.fileMetrics.first?.threadName == "Explain empty content type")
    #expect(summary.scanMetrics?.fileMetrics.first?.workingDirectory == "/tmp/project")
    #expect((summary.scanMetrics?.bytesRead ?? 0) > 0)
    #expect((summary.scanMetrics?.durationSeconds ?? 0) >= 0)
    #expect(summary.scanMetrics?.parserMode == "streaming-byte-scan")
}

@Test func parsesSessionActivityAndPerformanceMetrics() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("activity.jsonl")
    let jsonl = """
    {"timestamp":"2026-06-05T09:00:00.000Z","type":"session_meta","payload":{"id":"activity","cwd":"/tmp/activity"}}
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":1780667467,"duration_ms":48071,"time_to_first_token_ms":5294}}
    {"timestamp":"2026-06-05T09:02:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-2","completed_at":1780667468,"duration_ms":120000,"time_to_first_token_ms":1800}}
    {"timestamp":"2026-06-05T09:03:00.000Z","type":"event_msg","payload":{"type":"exec_command_end","exit_code":0,"command":["/bin/echo","ok"],"status":"completed"}}
    {"timestamp":"2026-06-05T09:04:00.000Z","type":"event_msg","payload":{"type":"exec_command_end","exit_code":2,"command":["/bin/false"],"status":"completed"}}
    {"timestamp":"2026-06-05T09:05:00.000Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","name":"web_search","arguments":"{}"}}
    {"timestamp":"2026-06-05T09:06:00.000Z","type":"event_msg","payload":{"changes":{"/tmp/activity/A.swift":{"type":"modify"},"/tmp/activity/B.swift":{"type":"create"}}}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

    let session = try #require(
        CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
            .scan()
            .first
    )

    #expect(session.completedTurns == 2)
    #expect(session.lastTurnDurationMilliseconds == 120_000)
    #expect(session.medianTurnDurationMilliseconds == 84_035)
    #expect(session.averageTurnDurationMilliseconds == 84_035)
    #expect(session.latestTimeToFirstTokenMilliseconds == 1_800)
    #expect(session.medianTimeToFirstTokenMilliseconds == 3_547)
    #expect(session.commandEvents == 2)
    #expect(session.failedCommandEvents == 1)
    #expect(session.toolCallEvents == 1)
    #expect(session.changedFileEvents == 2)
}

@Test func scanParsesRecentFilesConcurrentlyInModificationOrder() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "old", to: sessionsDirectory.appendingPathComponent("old.jsonl"))
    try writeSession(id: "middle", to: sessionsDirectory.appendingPathComponent("middle.jsonl"))
    try writeSession(id: "new", to: sessionsDirectory.appendingPathComponent("new.jsonl"))

    let now = Date()
    try setModificationDate(now.addingTimeInterval(-120), for: sessionsDirectory.appendingPathComponent("old.jsonl"))
    try setModificationDate(now.addingTimeInterval(-60), for: sessionsDirectory.appendingPathComponent("middle.jsonl"))
    try setModificationDate(now, for: sessionsDirectory.appendingPathComponent("new.jsonl"))

    let snapshots = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).scan(limit: 2)

    #expect(snapshots.map(\.sessionID) == ["new", "middle"])
}

@Test func scannerDefaultsToActiveSessionsAndCanIncludeArchivedSessions() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
    let archivedDirectory = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: archivedDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let activeFile = sessionsDirectory.appendingPathComponent("active.jsonl")
    let archivedFile = archivedDirectory.appendingPathComponent("archived.jsonl")
    try writeSession(id: "active", to: activeFile)
    try writeSession(id: "archived", to: archivedFile)

    let now = Date()
    try setModificationDate(now.addingTimeInterval(-60), for: activeFile)
    try setModificationDate(now, for: archivedFile)

    let activeOnly = try CodexSessionScanner(codexHome: codexHome).scan(limit: 10)
    #expect(activeOnly.map(\.sessionID) == ["active"])

    let includingArchived = try CodexSessionScanner(
        codexHome: codexHome,
        configuration: CodexSessionScannerConfiguration(includeArchivedSessions: true)
    )
        .scan(limit: 10)
    #expect(includingArchived.map(\.sessionID) == ["archived", "active"])
}

@Test func scannerConfigurationClampsExpertValues() {
    let configuration = CodexSessionScannerConfiguration(
        maximumConcurrentParses: 10_000,
        chunkSizeBytes: 1,
        maximumLineBufferBytes: 1,
        sessionIndexMaximumLineBufferBytes: 10_000_000
    )

    #expect(configuration.maximumConcurrentParses == CodexSessionScannerConfiguration.maximumAllowedConcurrentParses)
    #expect(configuration.chunkSizeBytes == CodexSessionScannerConfiguration.minimumChunkSizeBytes)
    #expect(configuration.maximumLineBufferBytes == CodexSessionScannerConfiguration.minimumLineBufferBytes)
    #expect(
        configuration.sessionIndexMaximumLineBufferBytes ==
            CodexSessionScannerConfiguration.maximumAllowedSessionIndexLineBufferBytes
    )
}

@Test func scanMetricsReflectCustomParserConfiguration() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "first", to: sessionsDirectory.appendingPathComponent("first.jsonl"))
    try writeSession(id: "second", to: sessionsDirectory.appendingPathComponent("second.jsonl"))
    try writeSession(id: "third", to: sessionsDirectory.appendingPathComponent("third.jsonl"))

    let configuration = CodexSessionScannerConfiguration(
        maximumConcurrentParses: 4,
        chunkSizeBytes: 64 * 1024,
        maximumLineBufferBytes: 256 * 1024,
        sessionIndexMaximumLineBufferBytes: 64 * 1024
    )

    let result = try CodexSessionScanner(
        codexHome: temporaryDirectory.appendingPathComponent(".codex"),
        configuration: configuration
    )
        .scanResult(limit: 3)

    #expect(result.metrics.maximumConcurrentParses == min(3, configuration.maximumConcurrentParses))
    #expect(result.metrics.configuredMaximumConcurrentParses == configuration.maximumConcurrentParses)
    #expect(result.metrics.chunkSizeBytes == 64 * 1024)
    #expect(result.metrics.maximumLineBufferBytes == 256 * 1024)
    #expect(result.metrics.sessionIndexMaximumLineBufferBytes == 64 * 1024)
}

@Test func scanCacheReusesUnchangedSessionFiles() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "first", to: sessionsDirectory.appendingPathComponent("first.jsonl"))
    try writeSession(id: "second", to: sessionsDirectory.appendingPathComponent("second.jsonl"))
    try writeSessionIndex(["first": "First cached thread", "second": "Second cached thread"], to: codexHome)

    let cache = CodexSessionScanCache()
    let scanner = CodexSessionScanner(codexHome: codexHome)

    let cold = try scanner.scanResult(limit: 2, cache: cache)
    #expect(cold.metrics.cacheEnabled)
    #expect(cold.metrics.cacheHits == 0)
    #expect(cold.metrics.cacheMisses == 2)
    #expect(cold.metrics.cacheEntries == 2)
    #expect(cold.metrics.bytesRead > 0)
    #expect(cold.metrics.fileMetrics.allSatisfy { $0.cacheHit == false })
    #expect(cold.sessions.allSatisfy { $0.threadName != nil })

    let warm = try scanner.scanResult(limit: 2, cache: cache)
    #expect(warm.metrics.cacheEnabled)
    #expect(warm.metrics.cacheHits == 2)
    #expect(warm.metrics.cacheMisses == 0)
    #expect(warm.metrics.cacheEntries == 2)
    #expect(warm.metrics.cacheBytesSaved > 0)
    #expect(warm.metrics.bytesRead == 0)
    #expect(warm.metrics.maximumConcurrentParses == 0)
    #expect(
        warm.metrics.configuredMaximumConcurrentParses ==
            CodexSessionScannerConfiguration.default.maximumConcurrentParses
    )
    #expect(warm.metrics.fileMetrics.allSatisfy { $0.cacheHit })
    #expect(warm.sessions.allSatisfy { $0.threadName != nil })

    let changedFile = sessionsDirectory.appendingPathComponent("second.jsonl")
    try writeSession(id: "second", to: changedFile)
    try setModificationDate(Date().addingTimeInterval(60), for: changedFile)

    let mixed = try scanner.scanResult(limit: 2, cache: cache)
    #expect(mixed.metrics.cacheHits == 1)
    #expect(mixed.metrics.cacheMisses == 1)
    #expect(mixed.metrics.maximumConcurrentParses == 1)
    #expect(
        mixed.metrics.configuredMaximumConcurrentParses ==
            CodexSessionScannerConfiguration.default.maximumConcurrentParses
    )
}

@Test func parsesChunkSpanningJSONLLinesAndRecordsBufferMetrics() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("large-line.jsonl")
    let padding = String(repeating: "x", count: 300_000)
    let jsonl = """
    {"timestamp":"2026-06-05T09:00:00.000Z","type":"session_meta","payload":{"id":"chunked","cwd":"/tmp/chunked"},"padding":"\(padding)"}
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"model_context_window":1000}}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).scanResult()

    #expect(result.sessions.first?.sessionID == "chunked")
    #expect(result.sessions.first?.workingDirectory == "/tmp/chunked")
    #expect(result.metrics.fileMetrics.first?.maximumBufferedLineBytes ?? 0 > 200_000)
    #expect(result.metrics.fileMetrics.first?.oversizedLines == 0)
}

@Test func capsOversizedJSONLLinesAfterParsingRelevantPrefix() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("oversized-line.jsonl")
    let padding = String(repeating: "x", count: 1_200_000)
    let jsonl = """
    {"timestamp":"2026-06-05T09:00:00.000Z","type":"session_meta","payload":{"id":"oversized","cwd":"/tmp/oversized"},"padding":"\(padding)"}
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"model_context_window":1000}}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).scanResult()

    #expect(result.sessions.first?.sessionID == "oversized")
    #expect(result.sessions.first?.workingDirectory == "/tmp/oversized")
    #expect(result.sessions.first?.tokenEvents.count == 1)
    #expect(result.metrics.fileMetrics.first?.oversizedLines == 1)
}

@Test func monitorRefreshCachesSummary() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "monitor", to: sessionsDirectory.appendingPathComponent("monitor.jsonl"))

    let monitor = ModexMonitor(
        configuration: ModexMonitorConfiguration(
            codexHome: temporaryDirectory.appendingPathComponent(".codex"),
            scanLimit: 1
        )
    )
    let result = await monitor.refresh()

    guard case .success(let summary) = result else {
        #expect(Bool(false))
        return
    }

    #expect(summary.sessionsScanned == 1)
    #expect(summary.latestSession?.sessionID == "monitor")

    let cachedSummary = await monitor.cachedSummary()
    #expect(cachedSummary?.latestSession?.sessionID == "monitor")
}

@Test func monitorRefreshUsesUpdatedConfiguration() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "first", to: sessionsDirectory.appendingPathComponent("first.jsonl"))
    try writeSession(id: "second", to: sessionsDirectory.appendingPathComponent("second.jsonl"))

    let now = Date()
    try setModificationDate(now, for: sessionsDirectory.appendingPathComponent("first.jsonl"))
    try setModificationDate(now.addingTimeInterval(-60), for: sessionsDirectory.appendingPathComponent("second.jsonl"))

    let monitor = ModexMonitor(
        configuration: ModexMonitorConfiguration(
            codexHome: temporaryDirectory.appendingPathComponent(".codex"),
            scanLimit: 1
        )
    )

    let firstResult = await monitor.refresh()
    guard case .success(let firstSummary) = firstResult else {
        #expect(Bool(false))
        return
    }
    #expect(firstSummary.sessionsScanned == 1)

    await monitor.update(
        configuration: ModexMonitorConfiguration(
            codexHome: temporaryDirectory.appendingPathComponent(".codex"),
            scanLimit: 2
        )
    )

    let secondResult = await monitor.refresh()
    guard case .success(let secondSummary) = secondResult else {
        #expect(Bool(false))
        return
    }
    #expect(secondSummary.sessionsScanned == 2)
}

@Test func oneShotCommandUsesSharedReportFormatter() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "cli", to: sessionsDirectory.appendingPathComponent("cli.jsonl"))

    let report = try ModexOneShotCommand(
        configuration: ModexMonitorConfiguration(
            codexHome: temporaryDirectory.appendingPathComponent(".codex"),
            scanLimit: 1
        )
    ).report()

    #expect(report.contains("sessions: 1"))
    #expect(report.contains("token events: 1"))
    #expect(report.contains("scan parser: streaming-byte-scan"))
    #expect(report.contains("scan index line buffer cap:"))
    #expect(report.contains("latest context usage: 10.0%"))
}

@Test func historyStorePersistsScanAndThreadSamples() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("history.jsonl")
    try writeInsightSession(to: fileURL)

    let summary = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).summary()
    let store = try ModexHistoryStore(
        databaseURL: temporaryDirectory.appendingPathComponent("history.sqlite")
    )
    try store.record(summary: summary, sampledAt: Date(timeIntervalSince1970: 1_800_000_000))
    try store.record(summary: summary, sampledAt: Date(timeIntervalSince1970: 1_800_000_060))

    let snapshot = try store.snapshot()
    let session = try #require(summary.latestSession)
    let samples = snapshot.samples(for: session)

    #expect(snapshot.scanSamples.count == 2)
    #expect(samples.count == 1)
    #expect(samples.first?.sessionID == "insight")
    #expect(samples.first?.threadName == nil)
    #expect(samples.first?.projectTitle == "insight")
    #expect(samples.first?.contextPercent == 92.0)
    #expect(samples.first?.failedCommandEvents == 3)
}

@Test func signalEngineProducesDeterministicInsights() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeInsightSession(to: sessionsDirectory.appendingPathComponent("insight.jsonl"))
    let summary = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).summary()
    let insights = ModexSignalEngine().insights(
        for: summary,
        history: nil,
        thresholds: ModexSignalThresholds(yellowPercent: 55, orangePercent: 78, redPercent: 90)
    )

    #expect(insights.contains { $0.kind == .highContext && $0.severity == .critical })
    #expect(insights.contains { $0.kind == .failedCommands && $0.status == .agentUnavailable })
    #expect(insights.contains { $0.kind == .slowTurn })
    #expect(insights.contains { $0.kind == .repeatedCompactions })
    #expect(insights.contains { $0.kind == .highCacheReuse })
}

private func writeSession(id: String, to fileURL: URL) throws {
    let jsonl = """
    {"timestamp":"2026-06-05T09:00:00.000Z","type":"session_meta","payload":{"id":"\(id)","cwd":"/tmp/\(id)"}}
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"model_context_window":1000}}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)
}

private func writeInsightSession(to fileURL: URL) throws {
    let jsonl = """
    {"timestamp":"2026-06-05T09:00:00.000Z","type":"session_meta","payload":{"id":"insight","cwd":"/tmp/insight"}}
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":520,"cached_input_tokens":400,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":560},"total_token_usage":{"input_tokens":520,"cached_input_tokens":400,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":560},"model_context_window":1000}}}
    {"timestamp":"2026-06-05T09:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":920,"cached_input_tokens":820,"output_tokens":40000,"reasoning_output_tokens":10000,"total_tokens":100000},"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":820000,"output_tokens":120000,"reasoning_output_tokens":40000,"total_tokens":1160000},"model_context_window":1000}}}
    {"timestamp":"2026-06-05T09:03:00.000Z","type":"event_msg","payload":{"type":"task_complete","duration_ms":720000,"time_to_first_token_ms":2400}}
    {"timestamp":"2026-06-05T09:04:00.000Z","type":"event_msg","payload":{"type":"exec_command_end","exit_code":1,"command":["/bin/false"]}}
    {"timestamp":"2026-06-05T09:05:00.000Z","type":"event_msg","payload":{"type":"exec_command_end","exit_code":2,"command":["/bin/false"]}}
    {"timestamp":"2026-06-05T09:06:00.000Z","type":"event_msg","payload":{"type":"exec_command_end","exit_code":127,"command":["missing-tool"]}}
    {"timestamp":"2026-06-05T09:07:00.000Z","type":"event_msg","payload":{"type":"post_compact"}}
    {"timestamp":"2026-06-05T09:08:00.000Z","type":"event_msg","payload":{"type":"pre_compact"}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)
}

private func writeSessionIndex(_ namesBySessionID: [String: String], to codexHome: URL) throws {
    let lines = namesBySessionID
        .sorted { $0.key < $1.key }
        .map { sessionID, threadName in
            #"{"id":"\#(sessionID)","thread_name":"\#(threadName)","updated_at":"2026-06-05T13:50:24.046304Z"}"#
        }
        .joined(separator: "\n")
    try lines.write(
        to: codexHome.appendingPathComponent("session_index.jsonl"),
        atomically: true,
        encoding: .utf8
    )
}

private func setModificationDate(_ date: Date, for fileURL: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
}
