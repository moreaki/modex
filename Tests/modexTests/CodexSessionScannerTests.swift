import Foundation
import SQLite3
import Testing
@testable import ModexCore

@Test func parsesTokenEventsAndComputesSummary() async throws {
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
    {"timestamp":"2026-06-05T09:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":7,"total_tokens":350},"total_token_usage":{"input_tokens":400,"cached_input_tokens":30,"output_tokens":70,"reasoning_output_tokens":12,"total_tokens":470},"model_context_window":1000},"rate_limits":{"limit_id":"codex","limit_name":"Codex","primary":{"used_percent":9.0,"window_minutes":300,"resets_at":1775764988},"secondary":{"used_percent":19.0,"window_minutes":10080,"resets_at":1776209285},"credits":null,"plan_type":"pro"}}}
    {"timestamp":"2026-06-05T09:03:00.000Z","type":"event_msg","payload":{"type":"post_compact","trigger":"auto"}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)
    try writeSessionIndex(
        ["thread-1": "Explain empty content type"],
        to: temporaryDirectory.appendingPathComponent(".codex")
    )

    let summary = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .summary()

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
    #expect(summary.latestSession?.latestRateLimits?.limitID == "codex")
    #expect(summary.latestSession?.latestRateLimits?.limitName == "Codex")
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

@Test func summarySeparatesHighestThreadContextFromGeneralAccountLimits() throws {
    var newestModelSpecificSession = SessionSnapshot(
        fileURL: URL(fileURLWithPath: "/tmp/model-specific.jsonl")
    )
    newestModelSpecificSession.threadName = "Latest model-specific thread"
    newestModelSpecificSession.updatedAt = Date(timeIntervalSince1970: 300)
    newestModelSpecificSession.tokenEvents = [
        TokenEvent(
            timestamp: Date(timeIntervalSince1970: 300),
            lastUsage: TokenUsage(inputTokens: 400, totalTokens: 400),
            totalUsage: TokenUsage(inputTokens: 400, totalTokens: 400),
            modelContextWindow: 1_000,
            rateLimits: CodexRateLimits(
                primary: CodexRateLimitWindow(usedPercent: 0, windowMinutes: 10_080),
                limitID: "codex_bengalfox",
                limitName: "GPT-5.3-Codex-Spark"
            )
        ),
    ]

    var highestContextSession = SessionSnapshot(
        fileURL: URL(fileURLWithPath: "/tmp/general.jsonl")
    )
    highestContextSession.threadName = "Highest context thread"
    highestContextSession.updatedAt = Date(timeIntervalSince1970: 200)
    highestContextSession.tokenEvents = [
        TokenEvent(
            timestamp: Date(timeIntervalSince1970: 200),
            lastUsage: TokenUsage(inputTokens: 860, totalTokens: 860),
            totalUsage: TokenUsage(inputTokens: 860, totalTokens: 860),
            modelContextWindow: 1_000,
            rateLimits: CodexRateLimits(
                primary: CodexRateLimitWindow(usedPercent: 7, windowMinutes: 10_080),
                limitID: "codex"
            )
        ),
    ]

    let summary = ModexSummary(sessions: [highestContextSession, newestModelSpecificSession])

    #expect(summary.latestSession?.threadName == "Latest model-specific thread")
    #expect(summary.contextSession?.threadName == "Highest context thread")
    #expect(summary.contextUsagePercent == 86)
    #expect(summary.latestRateLimits?.limitID == "codex")
    #expect(summary.latestRateLimits?.primary?.leftPercent == 93)
    #expect(summary.latestRateLimits?.sevenDayWindow?.leftPercent == 93)
    #expect(summary.latestRateLimitsObservedAt == Date(timeIntervalSince1970: 200))

    let modelSpecificOnly = ModexSummary(sessions: [newestModelSpecificSession])
    #expect(modelSpecificOnly.latestRateLimits == nil)
}

@Test func sevenDayRateLimitCanBePrimaryOrSecondary() {
    let fiveHour = CodexRateLimitWindow(usedPercent: 12, windowMinutes: 300)
    let sevenDay = CodexRateLimitWindow(usedPercent: 26, windowMinutes: 10_080)

    #expect(CodexRateLimits(primary: sevenDay).sevenDayWindow == sevenDay)
    #expect(CodexRateLimits(primary: fiveHour, secondary: sevenDay).sevenDayWindow == sevenDay)
    #expect(CodexRateLimits(primary: fiveHour).sevenDayWindow == nil)
}

@Test func parsesSessionActivityAndPerformanceMetrics() async throws {
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

    let sessions = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .scan()
    let session = try #require(sessions.first)

    #expect(session.completedTurns == 2)
    #expect(session.lastTurnDurationMilliseconds == 120_000)
    #expect(session.medianTurnDurationMilliseconds == 84_035)
    #expect(session.averageTurnDurationMilliseconds == 84_035)
    #expect(session.latestTimeToFirstTokenMilliseconds == 1_800)
    #expect(session.medianTimeToFirstTokenMilliseconds == 3_547)
    #expect(session.commandEvents == 2)
    #expect(session.failedCommandEvents == 1)
    #expect(session.failedCommandSummaries.first?.commandName == "false")
    #expect(session.failedCommandSummaries.first?.exitCode == 2)
    #expect(session.toolCallEvents == 1)
    #expect(session.changedFileEvents == 2)
}

@Test func parsesCurrentCodexActivityAndDeduplicatesCompactionPairs() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("current.jsonl")
    let jsonl = """
    {"timestamp":"2026-07-15T09:00:00.000Z","type":"session_meta","payload":{"id":"current","cwd":"/tmp/current","cli_version":"0.144.3","model_provider":"openai","source":"cli","agent_nickname":"Ada","agent_role":"reviewer","agent_path":"/root/review","parent_thread_id":"parent","git":{"repository_url":"git@github.com:openai/current.git"}}}
    {"timestamp":"2026-07-15T09:01:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-sol","reasoning_effort":"xhigh","service_tier":"fast","personality":"pragmatic","collaboration_mode":{"mode":"default","settings":{}}}}}
    {"timestamp":"2026-07-15T09:02:00.000Z","type":"response_item","payload":{"type":"custom_tool_call","call_id":"call-exec","name":"exec","input":"{}"}}
    {"timestamp":"2026-07-15T09:03:00.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-exec","output":[{"type":"text","text":"Script failed\\nWall time 0.1 seconds"}]}}
    {"timestamp":"2026-07-15T09:04:00.000Z","type":"event_msg","payload":{"type":"patch_apply_end","success":false,"changes":{"/tmp/current/A.swift":{"type":"modify"}}}}
    {"timestamp":"2026-07-15T09:05:00.000Z","type":"event_msg","payload":{"type":"mcp_tool_call_end","duration":0.2}}
    {"timestamp":"2026-07-15T09:06:00.000Z","type":"event_msg","payload":{"type":"web_search_end"}}
    {"timestamp":"2026-07-15T09:07:00.000Z","type":"event_msg","payload":{"type":"sub_agent_activity","agent_thread_id":"child"}}
    {"timestamp":"2026-07-15T09:08:00.000Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}
    {"timestamp":"2026-07-15T09:10:00.000Z","type":"compacted","payload":{"message":"compact"}}
    {"timestamp":"2026-07-15T09:10:00.010Z","type":"event_msg","payload":{"type":"context_compacted"}}
    {"timestamp":"2026-07-15T09:10:02.000Z","type":"event_msg","payload":{"type":"post_compact"}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

    let session = try #require(
        try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
            .scan()
            .first
    )

    #expect(session.cliVersion == "0.144.3")
    #expect(session.modelProvider == "openai")
    #expect(session.source == "cli")
    #expect(session.agentNickname == "Ada")
    #expect(session.agentRole == "reviewer")
    #expect(session.agentPath == "/root/review")
    #expect(session.parentThreadID == "parent")
    #expect(session.gitOriginURL == "git@github.com:openai/current.git")
    #expect(session.model == "gpt-5.6-sol")
    #expect(session.reasoningEffort == "xhigh")
    #expect(session.serviceTier == "fast")
    #expect(session.personality == "pragmatic")
    #expect(session.collaborationMode == "default")
    #expect(session.commandEvents == 1)
    #expect(session.failedCommandEvents == 1)
    #expect(session.failedCommandSummaries.first?.commandName == "exec")
    #expect(session.patchEvents == 1)
    #expect(session.failedPatchEvents == 1)
    #expect(session.changedFileEvents == 1)
    #expect(session.mcpToolCallEvents == 1)
    #expect(session.webSearchEvents == 1)
    #expect(session.subagentActivityEvents == 1)
    #expect(session.abortedTurnEvents == 1)
    #expect(session.compactionEvents == 2)
}

@Test func projectIdentityUsesRepositoryOriginAcrossPathsAndProtocols() {
    var rootSession = SessionSnapshot(fileURL: URL(fileURLWithPath: "/tmp/root.jsonl"))
    rootSession.workingDirectory = "/Users/alice/Dev/sigma-frontend"
    rootSession.gitOriginURL = "git@github.com:convertic-software/sigma-frontend.git"

    var nestedSession = SessionSnapshot(fileURL: URL(fileURLWithPath: "/tmp/nested.jsonl"))
    nestedSession.workingDirectory = "/Users/alice/Dev/sigma-frontend/.angular"
    nestedSession.gitOriginURL = "https://github.com/convertic-software/sigma-frontend.git/"

    let rootIdentity = CodexProjectIdentity.resolve(for: rootSession)
    let nestedIdentity = CodexProjectIdentity.resolve(for: nestedSession)

    #expect(rootIdentity.kind == .repository)
    #expect(rootIdentity.id == nestedIdentity.id)
    #expect(rootIdentity.suggestedName == "sigma-frontend")
}

@Test func projectIdentityCollapsesDatedCodexTaskWorkspaces() {
    let first = CodexProjectIdentity.resolve(
        workingDirectory: "/Users/alice/Documents/Codex/2026-07-08/kann"
    )
    let second = CodexProjectIdentity.resolve(
        workingDirectory: "/Users/alice/Documents/Codex/2026-07-15/kan"
    )
    let ordinaryDirectory = CodexProjectIdentity.resolve(
        workingDirectory: "/Users/alice/Dev/kan"
    )

    #expect(first.kind == .codexTasks)
    #expect(first.id == second.id)
    #expect(first.id != ordinaryDirectory.id)
    #expect(ordinaryDirectory.kind == .directory)
}

@Test func projectIdentityTreatsStandardUserLocationsAsCodexTasks() {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    let homeIdentity = CodexProjectIdentity.resolve(workingDirectory: home.path)
    let downloadsIdentity = CodexProjectIdentity.resolve(
        workingDirectory: home.appendingPathComponent("Downloads", isDirectory: true).path
    )

    #expect(homeIdentity.kind == .codexTasks)
    #expect(downloadsIdentity.kind == .codexTasks)
    #expect(homeIdentity.id == downloadsIdentity.id)
}

@Test func sidebarStateReaderStreamsAndCachesProjectlessThreadIDs() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let padding = String(repeating: "x", count: 70_000)
    let state = "{\"padding\":\"\(padding)\",\"projectless-thread-ids\":[\"task-1\",\"task-2\"]}"
    try state.write(
        to: codexHome.appendingPathComponent(".codex-global-state.json"),
        atomically: true,
        encoding: .utf8
    )

    let firstRead = try #require(CodexSidebarStateReader.read(codexHome: codexHome))
    #expect(firstRead.state.scope(for: "task-1") == .task)
    #expect(firstRead.state.scope(for: "project-1") == .project)
    #expect(firstRead.bytesRead > 64 * 1_024)
    #expect(firstRead.cacheHit == false)

    let cachedRead = try #require(CodexSidebarStateReader.read(codexHome: codexHome))
    #expect(cachedRead.state.projectlessThreadIDs == firstRead.state.projectlessThreadIDs)
    #expect(cachedRead.bytesRead == 0)
    #expect(cachedRead.cacheHit)
}

@Test func stateDatabaseIndexesAndEnrichesRecentThreads() async throws {
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

    let activeURL = sessionsDirectory.appendingPathComponent("active.jsonl")
    let archivedURL = archivedDirectory.appendingPathComponent("archived.jsonl")
    try writeSession(id: "active", to: activeURL)
    try writeSession(id: "archived", to: archivedURL)
    try setModificationDate(Date().addingTimeInterval(-60), for: activeURL)
    try setModificationDate(Date(), for: archivedURL)
    try createCodexStateDatabase(
        at: codexHome.appendingPathComponent("database-cache/current-thread-index.sqlite"),
        rows: [
            StateThreadFixture(
                id: "active",
                path: activeURL.path,
                recencyMilliseconds: 2_000,
                title: "Indexed active thread",
                gitOriginURL: "git@github.com:openai/active.git",
                archived: false
            ),
            StateThreadFixture(
                id: "archived",
                path: archivedURL.path,
                recencyMilliseconds: 3_000,
                title: "Indexed archive",
                gitOriginURL: nil,
                archived: true
            ),
        ]
    )
    try writeCodexSidebarState(projectlessThreadIDs: ["active"], to: codexHome)

    let activeResult = try await CodexSessionScanner(codexHome: codexHome).scanResult(limit: 10)
    let active = try #require(activeResult.sessions.first)
    #expect(activeResult.sessions.count == 1)
    #expect(activeResult.metrics.discoveryMode == "codex-state-db")
    #expect(activeResult.metrics.metadataHits == 1)
    #expect(activeResult.metrics.sessionIndexBytesRead == 0)
    #expect(active.threadName == "Indexed active thread")
    #expect(active.model == "gpt-state")
    #expect(active.reasoningEffort == "high")
    #expect(active.source == "vscode")
    #expect(active.cliVersion == "0.144.3")
    #expect(active.gitOriginURL == "git@github.com:openai/active.git")
    #expect(active.threadScope == .task)
    #expect(active.isArchived == false)

    let allResult = try await CodexSessionScanner(
        codexHome: codexHome,
        configuration: CodexSessionScannerConfiguration(includeArchivedSessions: true)
    )
        .scanResult(limit: 10)
    #expect(allResult.sessions.map(\.sessionID) == ["archived", "active"])
    #expect(allResult.sessions.map(\.threadScope) == [.project, .task])
    #expect(allResult.sessions.first?.isArchived == true)
}

@Test func threadDatabaseDiscoveryUsesSchemaAndToleratesOptionalColumns() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let sessionURL = sessionsDirectory.appendingPathComponent("minimal.jsonl")
    try writeSession(id: "minimal", to: sessionURL)
    try createMinimalThreadDatabase(
        at: codexHome.appendingPathComponent("local-data/arbitrary-name.sqlite"),
        sessionID: "minimal",
        sessionPath: sessionURL.path
    )

    let result = try await CodexSessionScanner(codexHome: codexHome).scanResult()
    let session = try #require(result.sessions.first)

    #expect(result.metrics.discoveryMode == "codex-state-db")
    #expect(result.metrics.metadataHits == 1)
    #expect(session.threadName == "Minimal indexed thread")
    #expect(session.isArchived == false)
    #expect(session.updatedAt == Date(timeIntervalSince1970: 2_000_000_000))
}

@Test func incompatibleStateDatabaseFallsBackToFilesystemDiscovery() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "fallback", to: sessionsDirectory.appendingPathComponent("fallback.jsonl"))
    var database: OpaquePointer?
    #expect(sqlite3_open(codexHome.appendingPathComponent("unrelated-cache.sqlite").path, &database) == SQLITE_OK)
    if let database {
        sqlite3_close(database)
    }

    let result = try await CodexSessionScanner(codexHome: codexHome).scanResult(limit: 1)
    #expect(result.sessions.first?.sessionID == "fallback")
    #expect(result.metrics.discoveryMode == "filesystem")
    #expect(result.metrics.metadataHits == 0)
}

@Test func scanParsesRecentFilesConcurrentlyInModificationOrder() async throws {
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

    let snapshots = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .scan(limit: 2)

    #expect(snapshots.map(\.sessionID) == ["new", "middle"])
}

@Test func progressiveScanPublishesSevenProjectsAndSevenTasksBeforeTheCompleteSet() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let now = Date()
    var rows: [StateThreadFixture] = []
    for index in 0..<16 {
        let fileURL = sessionsDirectory.appendingPathComponent("thread-\(index).jsonl")
        try writeSession(id: "thread-\(index)", to: fileURL)
        try setModificationDate(now.addingTimeInterval(TimeInterval(-index * 60)), for: fileURL)
        rows.append(
            StateThreadFixture(
                id: "thread-\(index)",
                path: fileURL.path,
                recencyMilliseconds: Int64(16_000 - index * 1_000),
                title: "Thread \(index)",
                gitOriginURL: index < 8 ? "git@github.com:example/project.git" : nil,
                archived: false
            )
        )
    }
    try createCodexStateDatabase(
        at: codexHome.appendingPathComponent("state.sqlite"),
        rows: rows
    )
    try writeCodexSidebarState(
        projectlessThreadIDs: Set((8..<16).map { "thread-\($0)" }),
        to: codexHome
    )

    let recorder = ScanProgressRecorder()
    let result = try await CodexSessionScanner(codexHome: codexHome).scanResult(
        initialBatchSize: 7,
        onProgress: { progress in
            await recorder.record(progress)
        }
    )
    let progress = await recorder.results()

    #expect(result.sessions.count == 16)
    #expect(result.metrics.filesSelected == 16)
    #expect((progress.first?.sessions.count ?? 0) > 0)
    #expect((progress.first?.sessions.count ?? 0) <= 14)
    #expect(progress.first?.metrics.filesSelected == 16)
    let initialCheckpoint = try #require(progress.first { $0.sessions.count == 14 })
    #expect(initialCheckpoint.sessions.filter { $0.threadScope == .project }.count == 7)
    #expect(initialCheckpoint.sessions.filter { $0.threadScope == .task }.count == 7)
    #expect(progress.first { $0.sessions.count > 14 } != nil)
    #expect(progress.last?.sessions.count == 16)
    #expect(zip(progress, progress.dropFirst()).allSatisfy { pair in
        pair.0.sessions.count <= pair.1.sessions.count
    })
}

@Test func scannerDefaultsToActiveSessionsAndCanIncludeArchivedSessions() async throws {
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

    let activeOnly = try await CodexSessionScanner(codexHome: codexHome).scan()
    #expect(activeOnly.map(\.sessionID) == ["active"])

    let includingArchived = try await CodexSessionScanner(
        codexHome: codexHome,
        configuration: CodexSessionScannerConfiguration(includeArchivedSessions: true)
    )
        .scan()
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

@Test func scanMetricsReflectCustomParserConfiguration() async throws {
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

    let result = try await CodexSessionScanner(
        codexHome: temporaryDirectory.appendingPathComponent(".codex"),
        configuration: configuration
    )
        .scanResult(limit: 3)

    #expect(result.metrics.maximumConcurrentParses == min(3, configuration.maximumConcurrentParses))
    #expect(result.metrics.configuredMaximumConcurrentParses == configuration.maximumConcurrentParses)
    #expect(result.metrics.chunkSizeBytes == 64 * 1024)
    #expect(result.metrics.maximumLineBufferBytes == 256 * 1024)
    #expect(result.metrics.sessionIndexMaximumLineBufferBytes == 64 * 1024)
    #expect(result.metrics.processMemoryBytes > 0)
    #expect(result.metrics.processPeakMemoryBytes >= result.metrics.processMemoryBytes)
    #expect(result.metrics.cpuTimeSeconds >= 0)
}

@Test func scanCacheReusesUnchangedSessionFiles() async throws {
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

    let cold = try await scanner.scanResult(limit: 2, cache: cache)
    #expect(cold.metrics.cacheEnabled)
    #expect(cold.metrics.cacheHits == 0)
    #expect(cold.metrics.cacheMisses == 2)
    #expect(cold.metrics.cacheEntries == 2)
    #expect(cold.metrics.bytesRead > 0)
    #expect(cold.metrics.fileMetrics.allSatisfy { $0.cacheHit == false })
    #expect(cold.sessions.allSatisfy { $0.threadName != nil })

    let warm = try await scanner.scanResult(limit: 2, cache: cache)
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

    let mixed = try await scanner.scanResult(limit: 2, cache: cache)
    #expect(mixed.metrics.cacheHits == 1)
    #expect(mixed.metrics.cacheMisses == 1)
    #expect(mixed.metrics.maximumConcurrentParses == 1)
    #expect(
        mixed.metrics.configuredMaximumConcurrentParses ==
            CodexSessionScannerConfiguration.default.maximumConcurrentParses
    )
}

@Test func scanCacheResumesGrowingSessionFilesWithoutReparsingTheirHistory() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("growing.jsonl")
    try writeSession(id: "growing", to: fileURL)
    let originalSize = try #require(fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)

    let cache = CodexSessionScanCache()
    let scanner = CodexSessionScanner(codexHome: codexHome)
    let cold = try await scanner.scanResult(cache: cache)
    #expect(cold.sessions.first?.tokenEvents.count == 1)

    let appendedLine = """

    {"timestamp":"2026-06-05T09:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":7,"total_tokens":350},"total_token_usage":{"input_tokens":400,"cached_input_tokens":30,"output_tokens":70,"reasoning_output_tokens":12,"total_tokens":470},"model_context_window":1000}}}
    """
    let handle = try FileHandle(forWritingTo: fileURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(appendedLine.utf8))
    try handle.close()

    let incremental = try await scanner.scanResult(cache: cache)
    #expect(incremental.metrics.cacheHits == 0)
    #expect(incremental.metrics.cacheMisses == 1)
    #expect(incremental.metrics.incrementalFiles == 1)
    #expect(incremental.metrics.incrementalBytesSaved == originalSize)
    #expect(incremental.metrics.bytesRead < originalSize)
    #expect(incremental.sessions.first?.tokenEvents.count == 2)
    #expect(incremental.sessions.first?.latestTokenEvent?.totalUsage.totalTokens == 470)

    let replacement = Data((" " + String(data: try Data(contentsOf: fileURL), encoding: .utf8)!).utf8)
    try replacement.write(to: fileURL, options: .atomic)
    let rewritten = try await scanner.scanResult(cache: cache)
    #expect(rewritten.metrics.incrementalFiles == 0)
    #expect(rewritten.metrics.incrementalBytesSaved == 0)
    #expect(rewritten.metrics.bytesRead >= replacement.count)
}

@Test func parsesChunkSpanningJSONLLinesAndRecordsBufferMetrics() async throws {
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

    let result = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .scanResult()

    #expect(result.sessions.first?.sessionID == "chunked")
    #expect(result.sessions.first?.workingDirectory == "/tmp/chunked")
    #expect(result.metrics.fileMetrics.first?.maximumBufferedLineBytes ?? 0 > 200_000)
    #expect(result.metrics.fileMetrics.first?.oversizedLines == 0)
}

@Test func capsOversizedJSONLLinesAfterParsingRelevantPrefix() async throws {
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

    let result = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .scanResult()

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

@Test func oneShotCommandUsesSharedReportFormatter() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeSession(id: "cli", to: sessionsDirectory.appendingPathComponent("cli.jsonl"))

    let report = try await ModexOneShotCommand(
        configuration: ModexMonitorConfiguration(
            codexHome: temporaryDirectory.appendingPathComponent(".codex"),
            scanLimit: 1
        )
    ).report()

    #expect(report.contains("sessions: 1"))
    #expect(report.contains("token events: 1"))
    #expect(report.contains("scan parser: streaming-byte-scan"))
    #expect(report.contains("scan index line buffer cap:"))
    #expect(report.contains("highest context usage: 10.0%"))
}

@Test func historyStorePersistsScanAndThreadSamples() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let fileURL = sessionsDirectory.appendingPathComponent("history.jsonl")
    try writeInsightSession(to: fileURL)

    let summary = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .summary()
    let historyDatabaseURL = temporaryDirectory.appendingPathComponent("history.sqlite")
    try createLegacyScanHistoryDatabase(at: historyDatabaseURL)
    let store = try ModexHistoryStore(databaseURL: historyDatabaseURL)
    try store.record(summary: summary, sampledAt: Date(timeIntervalSince1970: 1_800_000_000))
    try store.record(summary: summary, sampledAt: Date(timeIntervalSince1970: 1_800_000_060))

    let snapshot = try store.snapshot()
    let session = try #require(summary.latestSession)
    let samples = snapshot.samples(for: session)

    #expect(snapshot.scanSamples.count == 2)
    let scanMetrics = try #require(summary.scanMetrics)
    #expect(snapshot.scanSamples.last?.processMemoryBytes == Int(clamping: scanMetrics.processMemoryBytes))
    #expect(snapshot.scanSamples.last?.cpuTimeSeconds == scanMetrics.cpuTimeSeconds)
    #expect(samples.count == 1)
    #expect(samples.first?.sessionID == "insight")
    #expect(samples.first?.threadName == nil)
    #expect(samples.first?.projectTitle == "insight")
    #expect(samples.first?.contextPercent == 92.0)
    #expect(samples.first?.failedCommandEvents == 3)

    let resourceHistory = ModexHistorySnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_800_000_060),
        scanSamples: snapshot.scanSamples
    )
    let hourlyResources = resourceHistory.scanResourceTotals()
    #expect(hourlyResources.scanCount == 2)
    #expect(hourlyResources.logicalBytesRead == scanMetrics.bytesRead * 2)
    #expect(abs(hourlyResources.cpuTimeSeconds - scanMetrics.cpuTimeSeconds * 2) < 0.000_001)

    let hourlyAverages = resourceHistory.scanResourceAverages()
    #expect(hourlyAverages.scanCount == 2)
    #expect(hourlyAverages.averageMemoryBytes == Int(clamping: scanMetrics.processMemoryBytes))
    #expect(hourlyAverages.highestMemoryBytes == Int(clamping: scanMetrics.processMemoryBytes))
    #expect(abs(hourlyAverages.averageCPUTimeSeconds - scanMetrics.cpuTimeSeconds) < 0.000_001)
    #expect(hourlyAverages.averagePhysicalBytesRead == Int(clamping: scanMetrics.physicalBytesRead))

    let agentResult = ModexAgentInsightResult(
        sourceInsightID: "insight-failed-commands",
        sourceFingerprint: "fingerprint",
        generatedAt: Date(timeIntervalSince1970: 1_800_000_120),
        provider: "local-codex",
        title: "Repeated command failures",
        summary: "Several failed command exits point to a likely local environment issue.",
        category: "failure_cost",
        severity: "warning",
        confidence: 0.8,
        suggestedAction: "Inspect the repeated failing command before continuing.",
        evidenceIDs: ["signal:failedCommands", "session:insight"]
    )
    let rerunAgentResult = ModexAgentInsightResult(
        sourceInsightID: "insight-failed-commands",
        sourceFingerprint: "fingerprint",
        generatedAt: Date(timeIntervalSince1970: 1_800_000_180),
        provider: "local-codex",
        title: "Command loop",
        summary: "The same failing command repeated in the latest sample.",
        category: "command_health",
        severity: "warning",
        confidence: 0.9,
        suggestedAction: "Open the failed command log for this thread.",
        evidenceIDs: ["signal:failedCommands", "session:insight"]
    )
    try store.save(agentInsight: agentResult)
    try store.save(agentInsight: rerunAgentResult)

    let savedAgentResult = try #require(store.agentInsightResults().first)
    #expect(savedAgentResult == rerunAgentResult)

    let agentRuns = try store.agentInsightRuns()
    #expect(agentRuns.count == 2)
    #expect(agentRuns.first == rerunAgentResult)
    #expect(agentRuns.last == agentResult)
}

@Test func signalEngineProducesDeterministicInsights() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeInsightSession(to: sessionsDirectory.appendingPathComponent("insight.jsonl"))
    let summary = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .summary()
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

@Test func agentEvidenceBuilderCreatesMetricsOnlyRequest() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sessionsDirectory = temporaryDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    try writeInsightSession(to: sessionsDirectory.appendingPathComponent("insight.jsonl"))
    let summary = try await CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex"))
        .summary()
    let insight = try #require(
        ModexSignalEngine()
            .insights(
                for: summary,
                history: nil,
                thresholds: ModexSignalThresholds(yellowPercent: 55, orangePercent: 78, redPercent: 90)
            )
            .first { $0.kind == .failedCommands }
    )

    let request = ModexAgentInsightEvidenceBuilder().request(
        for: insight,
        summary: summary,
        history: nil,
        includeCommandNames: true
    )

    #expect(request.sourceInsightID == insight.id)
    #expect(request.sourceFingerprint == insight.agentFingerprint)
    #expect(request.privacyMode == "metrics_and_sanitized_commands")
    #expect(request.signal.analysisState == "needs_interpretation")
    #expect(request.session?.failedCommands.count == 3)
    #expect(request.session?.failedCommands.map(\.commandName) == ["false", "false", "missing-tool"])
    #expect(request.evidenceIDs.contains("signal:failedCommands"))
    #expect(request.evidenceIDs.contains("session:insight"))
}

private struct StateThreadFixture {
    let id: String
    let path: String
    let recencyMilliseconds: Int64
    let title: String
    let gitOriginURL: String?
    let archived: Bool
}

private actor ScanProgressRecorder {
    private var recordedResults: [CodexScanResult] = []

    func record(_ result: CodexScanResult) {
        recordedResults.append(result)
    }

    func results() -> [CodexScanResult] {
        recordedResults
    }
}

private func createCodexStateDatabase(at databaseURL: URL, rows: [StateThreadFixture]) throws {
    try FileManager.default.createDirectory(
        at: databaseURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer {
        sqlite3_close(database)
    }

    let schema = """
    CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        rollout_path TEXT,
        recency_at_ms INTEGER NOT NULL,
        title TEXT,
        cwd TEXT,
        model TEXT,
        reasoning_effort TEXT,
        source TEXT,
        cli_version TEXT,
        model_provider TEXT,
        agent_nickname TEXT,
        agent_role TEXT,
        agent_path TEXT,
        parent_thread_id TEXT,
        thread_source TEXT,
        git_origin_url TEXT,
        archived INTEGER NOT NULL
    );
    """
    guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
        throw CocoaError(.fileWriteUnknown)
    }

    for row in rows {
        let gitOriginSQL = row.gitOriginURL.map { "'\(sqlEscaped($0))'" } ?? "NULL"
        let sql = """
        INSERT INTO threads VALUES (
            '\(sqlEscaped(row.id))',
            '\(sqlEscaped(row.path))',
            \(row.recencyMilliseconds),
            '\(sqlEscaped(row.title))',
            '/tmp/indexed',
            'gpt-state',
            'high',
            'vscode',
            '0.144.3',
            'openai',
            NULL,
            NULL,
            NULL,
            NULL,
            'user',
            \(gitOriginSQL),
            \(row.archived ? 1 : 0)
        );
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private func writeCodexSidebarState(
    projectlessThreadIDs: Set<String>,
    to codexHome: URL
) throws {
    let values = projectlessThreadIDs.sorted().map { "\"\($0)\"" }.joined(separator: ",")
    let state = "{\"projectless-thread-ids\":[\(values)]}"
    try state.write(
        to: codexHome.appendingPathComponent(".codex-global-state.json"),
        atomically: true,
        encoding: .utf8
    )
}

private func createMinimalThreadDatabase(
    at databaseURL: URL,
    sessionID: String,
    sessionPath: String
) throws {
    try FileManager.default.createDirectory(
        at: databaseURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer {
        sqlite3_close(database)
    }

    let sql = """
    CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        rollout_path TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        title TEXT
    );
    INSERT INTO threads VALUES (
        '\(sqlEscaped(sessionID))',
        '\(sqlEscaped(sessionPath))',
        2000000000,
        'Minimal indexed thread'
    );
    """
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw CocoaError(.fileWriteUnknown)
    }
}

private func sqlEscaped(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
}

private func createLegacyScanHistoryDatabase(at databaseURL: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer {
        sqlite3_close(database)
    }
    let sql = """
    CREATE TABLE scan_samples (
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
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw CocoaError(.fileWriteUnknown)
    }
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
