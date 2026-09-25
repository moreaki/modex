import Foundation

/// Dependency-free scanner regression harness. Compile with the ModexCore sources
/// from each revision; use the same generated corpus and concurrency for both.
@main struct CurrentCodexBenchmark {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let root = URL(fileURLWithPath: arguments[1])
        let mode = arguments[2]
        if mode == "generate" {
            let directory = root.appendingPathComponent("sessions")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in 0..<24 {
                var text = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"fixture-\(file)\"}}\n"
                for row in 0..<3_000 {
                    text += """
                    {"type":"response_item","payload":{"type":"function_call","name":"mcp__fixture__read","call_id":"c\(row)"}}
                    {"type":"response_item","payload":{"type":"function_call_output","call_id":"c\(row)","output":"\(String(repeating: "x", count: 1024))"}}
                    {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"total_tokens":120},"total_token_usage":{"input_tokens":\(100 * (row + 1)),"total_tokens":\(120 * (row + 1))},"model_context_window":1000}}}
                    {"type":"token_usage_record","payload":{"response_id":"r\(row)","usage":{"input_tokens":100,"cache_write_input_tokens":10,"total_tokens":120},"thread_token_usage":{"total_tokens":\(120 * (row + 1))}}}

                    """
                }
                try text.write(to: directory.appendingPathComponent("fixture-\(file).jsonl"), atomically: true, encoding: .utf8)
            }
            return
        }
        let scanner = CodexSessionScanner(codexHome: root, configuration: .init(maximumConcurrentParses: 4))
        let cache = CodexSessionScanCache()
        if mode != "cold" { _ = try await scanner.scanResult(cache: cache) }
        if mode == "append" {
            for file in 0..<24 {
                let handle = try FileHandle(forWritingTo: root.appendingPathComponent("sessions/fixture-\(file).jsonl"))
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("{\"type\":\"response_item\",\"payload\":{\"type\":\"web_search_call\",\"id\":\"append\"}}\n".utf8))
                try handle.close()
            }
        }
        let result = try await scanner.scanResult(cache: mode == "cold" ? nil : cache)
        let metrics = result.metrics
        print("mode=\(mode) seconds=\(metrics.durationSeconds) bytes=\(metrics.bytesRead) cpu=\(metrics.cpuTimeSeconds) peak=\(metrics.processPeakMemoryBytes) exact=\(metrics.cacheHits) append=\(metrics.incrementalFiles) voluntary=\(metrics.voluntaryContextSwitches) involuntary=\(metrics.involuntaryContextSwitches)")
    }
}
