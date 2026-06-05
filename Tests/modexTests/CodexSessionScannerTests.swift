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
    {"timestamp":"2026-06-05T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"model_context_window":1000}}}
    {"timestamp":"2026-06-05T09:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":7,"total_tokens":350},"total_token_usage":{"input_tokens":400,"cached_input_tokens":30,"output_tokens":70,"reasoning_output_tokens":12,"total_tokens":470},"model_context_window":1000}}}
    {"timestamp":"2026-06-05T09:03:00.000Z","type":"event_msg","payload":{"type":"post_compact","trigger":"auto"}}
    """
    try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

    let summary = try CodexSessionScanner(codexHome: temporaryDirectory.appendingPathComponent(".codex")).summary()

    #expect(summary.sessionsScanned == 1)
    #expect(summary.tokenEvents == 2)
    #expect(summary.totalTokens == 470)
    #expect(summary.medianTurnTokens == 235)
    #expect(summary.averageTurnTokens == 235)
    #expect(summary.compactionEvents == 1)
    #expect(summary.latestSession?.sessionID == "thread-1")
    #expect(summary.latestSession?.workingDirectory == "/tmp/project")
    #expect(summary.contextUsagePercent == 30.0)
}
