import Foundation

public struct ModexMonitorConfiguration: Equatable, Sendable {
    public static let initialDisplayCount = 7
    public static let defaultRefreshIntervalSeconds: TimeInterval = 60

    public let codexHome: URL
    public let scanLimit: Int?
    public let refreshIntervalSeconds: TimeInterval
    public let scannerConfiguration: CodexSessionScannerConfiguration
    public let scanCacheEnabled: Bool

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        scanLimit: Int? = nil,
        refreshIntervalSeconds: TimeInterval = Self.defaultRefreshIntervalSeconds,
        scannerConfiguration: CodexSessionScannerConfiguration = .default,
        scanCacheEnabled: Bool = true
    ) {
        self.codexHome = codexHome
        self.scanLimit = scanLimit
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.scannerConfiguration = scannerConfiguration
        self.scanCacheEnabled = scanCacheEnabled
    }
}

public enum ModexRefreshResult: Equatable, Sendable {
    case success(ModexSummary)
    case failure(String)
}

public actor ModexMonitor {
    private var configuration: ModexMonitorConfiguration
    private var latestSummary: ModexSummary?
    private var refreshTask: Task<ModexRefreshResult, Never>?
    private let scanCache = CodexSessionScanCache()

    public init(configuration: ModexMonitorConfiguration = ModexMonitorConfiguration()) {
        self.configuration = configuration
    }

    public func cachedSummary() -> ModexSummary? {
        latestSummary
    }

    public func update(configuration: ModexMonitorConfiguration) {
        let parserConfigurationChanged = self.configuration.codexHome != configuration.codexHome
            || self.configuration.scannerConfiguration != configuration.scannerConfiguration
        if parserConfigurationChanged || configuration.scanCacheEnabled == false {
            scanCache.removeAll()
        }
        self.configuration = configuration
    }

    public func flushCache() {
        scanCache.removeAll()
    }

    public func refresh(
        onProgress: (@Sendable (ModexSummary) async -> Void)? = nil
    ) async -> ModexRefreshResult {
        if let refreshTask {
            return await refreshTask.value
        }

        let configuration = configuration
        let scanCache = scanCache
        let task = Task.detached(priority: .userInitiated) { () -> ModexRefreshResult in
            do {
                let scanResult = try await CodexSessionScanner(
                    codexHome: configuration.codexHome,
                    configuration: configuration.scannerConfiguration
                )
                    .scanResult(
                        limit: configuration.scanLimit,
                        initialBatchSize: ModexMonitorConfiguration.initialDisplayCount,
                        cache: configuration.scanCacheEnabled ? scanCache : nil,
                        onProgress: { scanResult in
                            guard let onProgress else {
                                return
                            }
                            await onProgress(
                                ModexSummary(
                                    sessions: scanResult.sessions,
                                    scanMetrics: scanResult.metrics
                                )
                            )
                        }
                    )
                let summary = ModexSummary(
                    sessions: scanResult.sessions,
                    scanMetrics: scanResult.metrics
                )
                return .success(summary)
            } catch {
                return .failure(String(describing: error))
            }
        }

        refreshTask = task
        let result = await task.value
        refreshTask = nil

        if case .success(let summary) = result {
            latestSummary = summary
        }

        return result
    }
}

public struct ModexOneShotCommand: Sendable {
    private let configuration: ModexMonitorConfiguration
    private let formatter: ModexSummaryReportFormatter

    public init(
        configuration: ModexMonitorConfiguration = ModexMonitorConfiguration(),
        formatter: ModexSummaryReportFormatter = ModexSummaryReportFormatter()
    ) {
        self.configuration = configuration
        self.formatter = formatter
    }

    public func report() async throws -> String {
        let summary = try await CodexSessionScanner(
            codexHome: configuration.codexHome,
            configuration: configuration.scannerConfiguration
        )
            .summary(limit: configuration.scanLimit)
        return formatter.report(for: summary)
    }
}

public struct ModexSummaryReportFormatter: Sendable {
    public init() {}

    public func report(for summary: ModexSummary) -> String {
        lines(for: summary).joined(separator: "\n")
    }

    public func lines(for summary: ModexSummary) -> [String] {
        var lines = [
            "sessions: \(summary.sessionsScanned)",
            "token events: \(summary.tokenEvents)",
            "total tokens: \(summary.totalTokens)",
            "median turn tokens: \(summary.medianTurnTokens)",
            "average turn tokens: \(summary.averageTurnTokens)",
            "compaction events: \(summary.compactionEvents)",
            "commands: \(summary.sessions.reduce(0) { $0 + $1.commandEvents })",
            "failed commands: \(summary.sessions.reduce(0) { $0 + $1.failedCommandEvents })",
            "patches: \(summary.sessions.reduce(0) { $0 + $1.patchEvents })",
            "failed patches: \(summary.sessions.reduce(0) { $0 + $1.failedPatchEvents })",
            "MCP calls: \(summary.sessions.reduce(0) { $0 + $1.mcpToolCallEvents })",
            "web searches: \(summary.sessions.reduce(0) { $0 + $1.webSearchEvents })",
            "sub-agent activity: \(summary.sessions.reduce(0) { $0 + $1.subagentActivityEvents })",
            "aborted turns: \(summary.sessions.reduce(0) { $0 + $1.abortedTurnEvents })",
        ]

        if let metrics = summary.scanMetrics {
            lines.append(contentsOf: [
                "scan duration: \(String(format: "%.3fs", metrics.durationSeconds))",
                "scan bytes read: \(formatBytes(metrics.bytesRead))",
                "scan files parsed: \(metrics.filesParsed)/\(metrics.filesSelected)",
                "scan parser: \(metrics.parserMode)",
                "scan discovery: \(metrics.discoveryMode)",
                "scan metadata: \(metrics.metadataHits)/\(metrics.filesSelected)",
                "scan session index read: \(formatBytes(metrics.sessionIndexBytesRead))",
                "scan concurrency: \(metrics.maximumConcurrentParses)/\(metrics.configuredMaximumConcurrentParses)",
                "scan chunk size: \(formatBytes(metrics.chunkSizeBytes))",
                "scan line buffer cap: \(formatBytes(metrics.maximumLineBufferBytes))",
                "scan index line buffer cap: \(formatBytes(metrics.sessionIndexMaximumLineBufferBytes))",
                "scan max buffered line: \(formatBytes(maxBufferedLineBytes(metrics)))",
                "scan oversized lines: \(oversizedLines(metrics))",
                "scan memory footprint: \(formatBytes(Int(clamping: metrics.processMemoryBytes)))",
                "scan lifetime peak memory: \(formatBytes(Int(clamping: metrics.processPeakMemoryBytes)))",
                "scan CPU time: \(String(format: "%.3fs", metrics.cpuTimeSeconds)) (\(String(format: "%.1f%%", metrics.averageCPUPercent)) average)",
                "scan wakeups: \(metrics.idleWakeups) idle / \(metrics.interruptWakeups) interrupt",
                "scan physical I/O: \(formatBytes(Int(clamping: metrics.physicalBytesRead))) read / \(formatBytes(Int(clamping: metrics.physicalBytesWritten))) written",
                "scan context switches: \(metrics.voluntaryContextSwitches) voluntary / \(metrics.involuntaryContextSwitches) involuntary",
            ])
            if metrics.cacheEnabled {
                lines.append(contentsOf: [
                    "scan cache hits: \(metrics.cacheHits)/\(metrics.filesSelected)",
                    "scan cache misses: \(metrics.cacheMisses)",
                    "scan cache saved: \(formatBytes(metrics.cacheBytesSaved))",
                    "scan append reuse: \(metrics.incrementalFiles) files / \(formatBytes(metrics.incrementalBytesSaved)) saved",
                    "scan cache entries: \(metrics.cacheEntries)",
                ])
            }
        }

        if let percent = summary.contextUsagePercent {
            lines.append("highest context usage: \(String(format: "%.1f%%", percent))")
        } else {
            lines.append("highest context usage: unknown")
        }

        if let percent = summary.contextLeftPercent {
            let usedTokens = summary.contextSession?.contextUsedTokens
                .map { $0.formatted() }
                ?? "unknown"
            let contextWindow = summary.contextSession?.contextWindow
                .map { $0.formatted() }
                ?? "unknown"
            lines.append(
                "highest context left: \(String(format: "%.1f%%", percent)) (\(usedTokens) used / \(contextWindow))"
            )
        } else {
            lines.append("highest context left: unknown")
        }

        if let rateLimits = summary.latestRateLimits {
            if let primary = rateLimits.primary {
                lines.append(limitLine(title: rateLimitTitle(primary, fallback: "latest primary limit left"), window: primary))
            }
            if let secondary = rateLimits.secondary {
                lines.append(limitLine(title: rateLimitTitle(secondary, fallback: "latest secondary limit left"), window: secondary))
            }
        } else {
            lines.append("latest rate limit: unknown")
        }

        return lines
    }

    private func limitLine(title: String, window: CodexRateLimitWindow?) -> String {
        guard let window else {
            return "\(title): unknown"
        }

        var line = "\(title): \(String(format: "%.1f%%", window.leftPercent))"
        if let resetsAt = window.resetsAt {
            line += " (resets \(resetFormatter.string(from: resetsAt)))"
        }
        return line
    }

    private func rateLimitTitle(_ window: CodexRateLimitWindow, fallback: String) -> String {
        switch window.windowMinutes {
        case 300:
            return "latest 5h limit left"
        case 10_080:
            return "latest 7d limit left"
        default:
            return fallback
        }
    }

    private var resetFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func maxBufferedLineBytes(_ metrics: ScanMetrics) -> Int {
        metrics.fileMetrics.map(\.maximumBufferedLineBytes).max() ?? 0
    }

    private func oversizedLines(_ metrics: ScanMetrics) -> Int {
        metrics.fileMetrics.reduce(0) { $0 + $1.oversizedLines }
    }
}
