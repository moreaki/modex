import Foundation
import SQLite3
import Testing
@testable import ModexCore

@Test func currentActivityUsesStableIDsAndUsageFallback() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sessions = root.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = sessions.appendingPathComponent("current.jsonl")
    let records = #"""
    {"type":"session_meta","payload":{"id":"current"}}
    {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"wrapper","input":"text(await tools.clock())"}}
    {"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","call_id":"patch"}}
    {"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"patch","output":"apply_patch verification failed: fixture"}}
    {"type":"event_msg","payload":{"type":"patch_apply_end","call_id":"patch","success":false}}
    {"type":"response_item","payload":{"type":"function_call","namespace":"mcp__fixture","name":"read","call_id":"mcp"}}
    {"type":"event_msg","payload":{"type":"mcp_tool_call_end","call_id":"mcp"}}
    {"type":"response_item","payload":{"type":"function_call","namespace":"collaboration","name":"spawn_agent","call_id":"agent"}}
    {"type":"response_item","payload":{"type":"web_search_call","id":"web"}}
    {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"webSearch","id":"web"}}}
    {"payload":{"type":"function_call","name":"future_tool","call_id":"future"},"type":"response_item"}
    {"type":"token_usage_record","payload":{"response_id":"r1","usage":{"input_tokens":100,"cache_write_input_tokens":10,"total_tokens":120},"thread_token_usage":{"input_tokens":100,"cache_write_input_tokens":10,"total_tokens":120}}}
    {"type":"token_usage_record","payload":{"response_id":"r1","usage":{"total_tokens":120},"thread_token_usage":{"total_tokens":120}}}
    {"type":"event_msg","payload":{"type":"token_count","info":null}}
    """# + "\n"
    try records.write(to: file, atomically: true, encoding: .utf8)
    let cache = CodexSessionScanCache()
    let scanner = CodexSessionScanner(codexHome: root)
    let first = try await scanner.scanResult(cache: cache)
    let session = try #require(first.sessions.first)
    #expect(session.commandEvents == 0)
    #expect(session.patchEvents == 1)
    #expect(session.failedPatchEvents == 1)
    #expect(session.mcpToolCallEvents == 1)
    #expect(session.webSearchEvents == 1)
    #expect(session.subagentActivityEvents == 1)
    #expect(session.toolCallEvents == 6)
    #expect(session.tokenEvents.count == 1)
    #expect(session.tokenEvents.first?.lastUsage.cacheWriteInputTokens == 10)
    let report = ModexSummaryReportFormatter().report(for: ModexSummary(sessions: first.sessions))
    #expect(report.contains("MCP calls: 1"))
    #expect(report.contains("web searches: 1"))
    let append = #"""
    {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":120},"total_token_usage":{"total_tokens":120},"model_context_window":1000}}}
    {"type":"token_usage_record","payload":{"response_id":"r2","usage":{"cache_write_input_tokens":7,"total_tokens":120},"thread_token_usage":{"cache_write_input_tokens":11,"total_tokens":120}}}
    {"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","call_id":"patch"}}
    {"type":"response_item","payload":{"type":"function_call","name":"mcp__fixture__read","call_id":"mcp2"}}
    """# + "\n"
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(append.utf8))
    try handle.close()
    let second = try await scanner.scanResult(cache: cache)
    #expect(second.metrics.incrementalFiles == 1)
    #expect(second.sessions.first?.patchEvents == 1)
    #expect(second.sessions.first?.mcpToolCallEvents == 2)
    #expect(second.sessions.first?.tokenEvents.count == 1)
    #expect(second.sessions.first?.contextWindow == 1000)
    #expect(second.sessions.first?.tokenEvents.first?.lastUsage.cacheWriteInputTokens == 7)
    #expect(second.sessions.first?.tokenEvents.first?.totalUsage.cacheWriteInputTokens == 11)
}

@Test func canonicalIndexMetadataWinsWithoutReadingPrompts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let rollout = root.appendingPathComponent("session.jsonl")
    try "{\"type\":\"session_meta\",\"payload\":{\"id\":\"child\"}}\n".write(to: rollout, atomically: true, encoding: .utf8)
    var database: OpaquePointer?
    #expect(sqlite3_open(root.appendingPathComponent("future.sqlite").path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let sql = """
    CREATE TABLE threads (id TEXT, rollout_path TEXT, updated_at INTEGER, archived INTEGER,
      title TEXT, name TEXT, project_id TEXT, originator TEXT, history_mode TEXT, is_pinned INTEGER, source TEXT);
    INSERT INTO threads VALUES ('child','\(rollout.path)',2,0,'Old title','Canonical name','project',
      'codex-app','persisted',1,'{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}');
    """
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    let snapshot = try #require(try await CodexSessionScanner(codexHome: root).scan().first)
    #expect(snapshot.threadName == "Canonical name")
    #expect(snapshot.projectID == "project")
    #expect(snapshot.originator == "codex-app")
    #expect(snapshot.historyMode == "persisted")
    #expect(snapshot.isPinned)
    #expect(snapshot.isSubagent)
    #expect(snapshot.parentThreadID == "parent")
}

@Test func accountLimitsMergeSparseNotificationsWithoutInventingRecovery() throws {
    let decoder = JSONDecoder()
    let original = try decoder.decode(CodexAccountLimits.self, from: Data(#"{"accountId":"a","ordinaryUsageAllowed":false,"rateLimits":{"limitId":"codex","spendControlReached":true,"primary":{"usedPercent":100}},"rateLimitsByLimitId":{"spark":{"limitName":"Spark","primary":{"usedPercent":12}}},"rateLimitResetCredits":{"availableCount":2}}"#.utf8))
    let patch = try decoder.decode(CodexAccountLimits.self, from: Data(#"{"ordinaryUsageAllowed":null,"rateLimits":{"primary":{"usedPercent":5}},"rateLimitsByLimitId":{"spark":{"secondary":{"usedPercent":15}}}}"#.utf8))
    let merged = original.merging(patch)
    #expect(merged.ordinaryUsageAllowed == false)
    #expect(merged.rateLimits?.spendControlReached == true)
    #expect(merged.rateLimitResetCredits?.availableCount == 2)
    #expect(merged.rateLimitsByLimitId?["spark"]?.limitName == "Spark")
    #expect(merged.rateLimitsByLimitId?["spark"]?.primary?.usedPercent == 12)
    #expect(merged.generalLimits?.primary?.leftPercent == 95)
    let report = ModexSummaryReportFormatter().report(for: ModexSummary(
        sessions: [], accountRateLimits: merged.generalLimits, accountMetadata: merged))
    #expect(report.contains("account.ordinaryUsageAllowed: false"))
    #expect(report.contains("account.rateLimitResetCredits.availableCount: 2"))
    let switched = original.merging(try decoder.decode(CodexAccountLimits.self, from: Data(#"{"accountId":"b"}"#.utf8)))
    #expect(switched.ordinaryUsageAllowed == nil)
    #expect(switched.rateLimitResetCredits == nil)
    let spend = try decoder.decode(CodexAccountLimits.self, from: Data(#"{"rateLimits":{"individualLimit":{"used":"12.5","limit":"20","remainingPercent":37,"resetsAt":1780000000},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}}}"#.utf8))
    #expect(spend.rateLimits?.individualLimit?.used == "12.5")
}

@Test func usagePreservesNullsAndOrdersOnlyReportedDates() throws {
    let decoder = JSONDecoder()
    let missing = try decoder.decode(CodexAccountUsage.self, from: Data(#"{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}"#.utf8))
    #expect(missing.summary?.lifetimeTokens == nil)
    #expect(missing.dailyUsageBuckets == nil)
    let usage = try decoder.decode(CodexAccountUsage.self, from: Data(#"{"summary":{"lifetimeTokens":300,"peakDailyTokens":200},"dailyUsageBuckets":[{"startDate":"2026-09-23","tokens":200},{"startDate":"2026-09-21","tokens":100}]}"#.utf8))
    #expect(usage.recentDays.map(\.tokens) == [100, 200])
    #expect(usage.recentDays.count == 2)
}

@Test func modelUpgradeMetadataIsOptionalAndForwardCompatible() throws {
    let model = try JSONDecoder().decode(LocalCodexModelCapability.self, from: Data(#"{"id":"old","upgrade":"new","upgradeInfo":{"model":"new","retirementAt":1790000000},"inputModalities":["text","future"],"multiAgentVersion":"v99","modelSpecialty":"future"}"#.utf8))
    #expect(model.upgradeTarget == "new")
    #expect(model.upgradeInfo?.retirementAt == 1_790_000_000)
    #expect(model.multiAgentVersion == "v99")
    let legacy = try JSONDecoder().decode(LocalCodexModelCapability.self, from: Data(#"{"id":"legacy"}"#.utf8))
    #expect(legacy.upgradeTarget == nil)
}

@Test func runtimeMetadataNeverTreatsNotLoadedAsIdleOrReplacesNewerLocalName() throws {
    let thread = try JSONDecoder().decode(CodexThreadRuntimeMetadata.self, from: Data(#"{"id":"t","name":"old name","projectId":"p","updatedAt":1,"status":{"type":"active","activeFlags":["waitingOnApproval"]}}"#.utf8))
    var local = SessionSnapshot(fileURL: URL(fileURLWithPath: "/tmp/test.jsonl"))
    local.threadName = "new name"
    local.updatedAt = Date(timeIntervalSince1970: 2)
    local.threadScope = .task
    let enriched = thread.enriching(local, live: true)
    #expect(enriched.threadName == "new name")
    #expect(enriched.runtimeStatus?.presentationKey == "runtime.needsInput")
    #expect(thread.enriching(local, live: false).runtimeStatus == nil)
    local.projectID = "canonical"
    #expect(CodexThreadScope.resolve(for: local) == .project)
    for type in ["notLoaded", "futureStatus"] {
        let status = try JSONDecoder().decode(CodexThreadRuntimeStatus.self, from: Data("{\"type\":\"\(type)\"}".utf8))
        #expect(status.presentationKey == nil)
    }
}

private struct EchoResponse: Decodable, Sendable { let value: Int }

@Test func metadataPaginationTTLAndFailedRefreshKeepDatedSuccesses() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("mock")
    let script = #"""
    #!/bin/sh
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
      case "$line" in
        *'"method":"initialize"'*) printf '{"id":%s,"result":{"userAgent":"Fixture/1"}}\n' "$id" ;;
        *'"method":"initialized"'*) printf '{"method":"account/updated","params":{"authMode":"chatgpt","planType":"pro"}}\n' ;;
        *)
          if [ -f "$(dirname "$0")/fail" ]; then
            printf '{"id":%s,"error":{"code":-32601,"message":"Unavailable"}}\n' "$id"
          else
            case "$line" in
              *'"method":"account/rateLimits/read"'*) printf '{"id":%s,"result":{"accountId":"fixture","ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","primary":{"usedPercent":20}}}}\n' "$id" ;;
              *'"method":"account/usage/read"'*) printf '{"id":%s,"result":{"summary":{"lifetimeTokens":123}}}\n' "$id" ;;
              *'"method":"thread/list"'*)
                case "$line" in
                  *'"cursor":"page2"'*) printf '{"id":%s,"result":{"data":[{"id":"b","name":"Second","status":{"type":"notLoaded"}}],"nextCursor":null}}\n' "$id" ;;
                  *) printf '{"id":%s,"result":{"data":[{"id":"a","name":"First","status":{"type":"notLoaded"}}],"nextCursor":"page2"}}\n' "$id" ;;
                esac ;;
            esac
          fi ;;
      esac
    done
    """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let client = LocalCodexAppServerClient()
    defer { Task { await client.shutdown() } }
    let service = LocalCodexMetadataService(client: client)
    let now = Date()
    await service.refresh(executablePath: executable.path, includeArchived: false, now: now)
    let first = await service.cachedSnapshot()
    #expect(first.threads.count == 2)
    #expect(first.usage?.summary?.lifetimeTokens == 123)
    let requests = await client.diagnostics().requests
    await service.refresh(executablePath: executable.path, includeArchived: false, now: now.addingTimeInterval(10))
    #expect(await client.diagnostics().requests == requests)
    try Data().write(to: root.appendingPathComponent("fail"))
    await service.refresh(executablePath: executable.path, includeArchived: false, now: now.addingTimeInterval(901))
    let failed = await service.cachedSnapshot()
    #expect(failed.refreshFailed)
    #expect(failed.usage == first.usage)
    #expect(failed.usageObservedAt == first.usageObservedAt)
    #expect(failed.threads == first.threads)
    #expect(await client.diagnostics().processStarts == 1)
    await service.refresh(executablePath: root.appendingPathComponent("missing").path, includeArchived: false)
    let changed = await service.cachedSnapshot()
    #expect(changed.usage == nil)
    #expect(changed.limits == nil)
    #expect(changed.threads.isEmpty)
    await client.shutdown()
}

@Test func appServerSharesHandshakeRoutesRequestsAndTimesOutWithoutReplay() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("mock")
    let script = #"""
    #!/bin/sh
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
      case "$line" in
        *'"method":"initialize"'*) printf '{"id":%s,"result":{"userAgent":"Fixture/1"}}\n' "$id" ;;
        *'"method":"echo"'*)
          printf '{"method":"future/notification","params":{}}\n'
          printf '{"id":%s,"result":{"value":42,"future":true}}\n' "$id" ;;
        *'"method":"malformed"'*) printf 'not-json\n' ;;
        *'"method":"large"'*)
          printf '{"id":%s,"result":{"value":42,"ignored":"' "$id"
          head -c 3000000 /dev/zero | tr '\000' x
          printf '"}}\n' ;;
        *'"method":"oversized"'*) head -c 4300000 /dev/zero | tr '\000' x ;;
        *'"method":"exit"'*) exit 0 ;;
      esac
    done
    """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let client = LocalCodexAppServerClient()
    defer { Task { await client.shutdown() } }
    let notifications = await client.notifications()
    let received = Task { for await event in notifications where event.method == "future/notification" { return true }; return false }
    async let first: EchoResponse = client.request("echo", executablePath: executable.path)
    async let second: EchoResponse = client.request("echo", executablePath: executable.path)
    #expect(try await first.value == 42)
    #expect(try await second.value == 42)
    #expect(await received.value)
    #expect(await client.diagnostics().processStarts == 1)
    let large: EchoResponse = try await client.request("large", executablePath: executable.path)
    #expect(large.value == 42)
    await #expect(throws: LocalCodexAppServerError.timedOut) {
        let _: EchoResponse = try await client.request("silent", executablePath: executable.path, timeoutSeconds: 1)
    }
    let cancelled = Task { let _: EchoResponse = try await client.request("silent", executablePath: executable.path) }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    let after: EchoResponse = try await client.request("echo", executablePath: executable.path)
    #expect(after.value == 42)
    #expect(await client.diagnostics().processStarts == 1)
    await #expect(throws: LocalCodexAppServerError.disconnected) {
        let _: EchoResponse = try await client.request("malformed", executablePath: executable.path)
    }
    await #expect(throws: LocalCodexAppServerError.unavailable) {
        let _: EchoResponse = try await client.request("echo", executablePath: executable.path)
    }
    #expect(await client.diagnostics().processStarts == 1)
    let alternate = root.appendingPathComponent("alternate")
    try FileManager.default.copyItem(at: executable, to: alternate)
    let switched: EchoResponse = try await client.request("echo", executablePath: alternate.path)
    #expect(switched.value == 42)
    #expect(await client.diagnostics().processStarts == 2)
    await #expect(throws: LocalCodexAppServerError.disconnected) {
        let _: EchoResponse = try await client.request("oversized", executablePath: alternate.path)
    }
    await client.shutdown()
}
