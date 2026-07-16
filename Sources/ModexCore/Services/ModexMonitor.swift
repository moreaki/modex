import Foundation

public struct ModexMonitorConfiguration: Equatable, Sendable {
    public static let defaultScanLimit = 5
    public static let defaultRefreshIntervalSeconds: TimeInterval = 60

    public let codexHome: URL
    public let scanLimit: Int
    public let refreshIntervalSeconds: TimeInterval
    public let scannerConfiguration: CodexSessionScannerConfiguration
    public let scanCacheEnabled: Bool
    public let codexExecutablePath: String?

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        scanLimit: Int = Self.defaultScanLimit,
        refreshIntervalSeconds: TimeInterval = Self.defaultRefreshIntervalSeconds,
        scannerConfiguration: CodexSessionScannerConfiguration = .default,
        scanCacheEnabled: Bool = true,
        codexExecutablePath: String? = nil
    ) {
        self.codexHome = codexHome
        self.scanLimit = scanLimit
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.scannerConfiguration = scannerConfiguration
        self.scanCacheEnabled = scanCacheEnabled
        self.codexExecutablePath = codexExecutablePath
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

    public func refresh() async -> ModexRefreshResult {
        if let refreshTask {
            return await refreshTask.value
        }

        let configuration = configuration
        let scanCache = scanCache
        let task = Task.detached(priority: .userInitiated) { () -> ModexRefreshResult in
            do {
                let summary = try await CodexSessionScanner(
                    codexHome: configuration.codexHome,
                    configuration: configuration.scannerConfiguration
                )
                    .summary(
                        limit: configuration.scanLimit,
                        cache: configuration.scanCacheEnabled ? scanCache : nil,
                        statusRateLimits: Self.latestAppServerRateLimits(configuration)
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

    private static func latestAppServerRateLimits(_ configuration: ModexMonitorConfiguration) -> CodexRateLimits? {
        guard let executablePath = configuration.codexExecutablePath else {
            return nil
        }
        return try? CodexAppServerRateLimitReader(
            executablePath: executablePath,
            codexHome: configuration.codexHome
        ).latestRateLimits()
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
        let statusRateLimits: CodexRateLimits? = configuration.codexExecutablePath.flatMap { executablePath in
            try? CodexAppServerRateLimitReader(
                executablePath: executablePath,
                codexHome: configuration.codexHome
            ).latestRateLimits()
        }
        let summary = try await CodexSessionScanner(
            codexHome: configuration.codexHome,
            configuration: configuration.scannerConfiguration
        )
            .summary(limit: configuration.scanLimit, statusRateLimits: statusRateLimits)
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
        ]

        if let metrics = summary.scanMetrics {
            lines.append(contentsOf: [
                "scan duration: \(String(format: "%.3fs", metrics.durationSeconds))",
                "scan bytes read: \(formatBytes(metrics.bytesRead))",
                "scan files parsed: \(metrics.filesParsed)/\(metrics.filesSelected)",
                "scan parser: \(metrics.parserMode)",
                "scan concurrency: \(metrics.maximumConcurrentParses)/\(metrics.configuredMaximumConcurrentParses)",
                "scan chunk size: \(formatBytes(metrics.chunkSizeBytes))",
                "scan line buffer cap: \(formatBytes(metrics.maximumLineBufferBytes))",
                "scan index line buffer cap: \(formatBytes(metrics.sessionIndexMaximumLineBufferBytes))",
                "scan max buffered line: \(formatBytes(maxBufferedLineBytes(metrics)))",
                "scan oversized lines: \(oversizedLines(metrics))",
            ])
            if metrics.cacheEnabled {
                lines.append(contentsOf: [
                    "scan cache hits: \(metrics.cacheHits)/\(metrics.filesSelected)",
                    "scan cache misses: \(metrics.cacheMisses)",
                    "scan cache saved: \(formatBytes(metrics.cacheBytesSaved))",
                    "scan cache entries: \(metrics.cacheEntries)",
                ])
            }
        }

        if let percent = summary.contextUsagePercent {
            lines.append("latest context usage: \(String(format: "%.1f%%", percent))")
        } else {
            lines.append("latest context usage: unknown")
        }

        if let percent = summary.contextLeftPercent {
            let usedTokens = summary.latestSession?.contextUsedTokens
                .map { $0.formatted() }
                ?? "unknown"
            let contextWindow = summary.latestSession?.contextWindow
                .map { $0.formatted() }
                ?? "unknown"
            lines.append(
                "latest context left: \(String(format: "%.1f%%", percent)) (\(usedTokens) used / \(contextWindow))"
            )
        } else {
            lines.append("latest context left: unknown")
        }

        if let rateLimits = summary.latestRateLimits {
            let buckets = rateLimits.buckets.isEmpty
                ? [
                    CodexRateLimitBucket(
                        id: CodexRateLimitBucket.generalID,
                        name: "General",
                        primary: rateLimits.primary,
                        secondary: rateLimits.secondary,
                        planType: rateLimits.planType
                    ),
                ]
                : rateLimits.buckets
            for bucket in buckets {
                let prefix = bucket.isGeneral ? "latest" : bucket.displayName.lowercased()
                lines.append(limitLine(title: "\(prefix) 5h limit left", window: bucket.primary))
                lines.append(limitLine(title: "\(prefix) 7d limit left", window: bucket.secondary))
            }
        } else {
            lines.append("latest 5h limit left: unknown")
            lines.append("latest 7d limit left: unknown")
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
