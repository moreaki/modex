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
    public let rateLimits: CodexRateLimits?

    public init(
        timestamp: Date?,
        lastUsage: TokenUsage,
        totalUsage: TokenUsage,
        modelContextWindow: Int?,
        rateLimits: CodexRateLimits? = nil
    ) {
        self.timestamp = timestamp
        self.lastUsage = lastUsage
        self.totalUsage = totalUsage
        self.modelContextWindow = modelContextWindow
        self.rateLimits = rateLimits
    }
}

public struct CodexRateLimits: Equatable, Sendable {
    public let buckets: [CodexRateLimitBucket]
    public let planType: String?

    public init(
        primary: CodexRateLimitWindow? = nil,
        secondary: CodexRateLimitWindow? = nil,
        planType: String? = nil
    ) {
        self.planType = planType
        if primary != nil || secondary != nil || planType != nil {
            buckets = [
                CodexRateLimitBucket(
                    id: CodexRateLimitBucket.generalID,
                    name: "General",
                    primary: primary,
                    secondary: secondary,
                    planType: planType
                ),
            ]
        } else {
            buckets = []
        }
    }

    public init(buckets: [CodexRateLimitBucket], planType: String? = nil) {
        self.buckets = buckets
        self.planType = planType ?? buckets.compactMap(\.planType).first
    }

    public var primary: CodexRateLimitWindow? {
        preferredBucket?.primary
    }

    public var secondary: CodexRateLimitWindow? {
        preferredBucket?.secondary
    }

    public var generalBucket: CodexRateLimitBucket? {
        buckets.first { $0.isGeneral } ?? buckets.first
    }

    public var sparkBucket: CodexRateLimitBucket? {
        buckets.first { $0.isSpark }
    }

    public var mostConstrainedLeftPercent: Double? {
        buckets.flatMap { [$0.primary?.leftPercent, $0.secondary?.leftPercent] }
            .compactMap(\.self)
            .min()
    }

    private var preferredBucket: CodexRateLimitBucket? {
        generalBucket ?? buckets.first
    }
}

public struct CodexRateLimitBucket: Equatable, Sendable {
    public static let generalID = "codex"
    public static let sparkID = "gpt-5.3-codex-spark"

    public let id: String?
    public let name: String?
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let planType: String?

    public init(
        id: String?,
        name: String?,
        primary: CodexRateLimitWindow? = nil,
        secondary: CodexRateLimitWindow? = nil,
        planType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }

    public var displayName: String {
        if isGeneral {
            return "General"
        }
        if isSpark {
            return "GPT-5.3-Codex-Spark"
        }
        if let name, name.isEmpty == false {
            return name
        }
        if let id, id.isEmpty == false {
            return id
        }
        return "Codex"
    }

    public var key: String {
        Self.normalizedKey(id ?? name ?? displayName)
    }

    public var isGeneral: Bool {
        let values = normalizedIDAndName
        return values.contains(Self.generalID) || values.contains("general")
    }

    public var isSpark: Bool {
        normalizedIDAndName.contains { value in
            value.contains("spark")
        }
    }

    public var hasLimitWindows: Bool {
        primary != nil || secondary != nil
    }

    public func hasFreshLimitWindow(at date: Date) -> Bool {
        [primary, secondary].contains { window in
            guard let window else {
                return false
            }
            guard let resetsAt = window.resetsAt else {
                return true
            }
            return resetsAt >= date
        }
    }

    private var normalizedIDAndName: [String] {
        [id, name]
            .compactMap(\.self)
            .map(Self.normalizedKey)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct CodexRateLimitWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var leftPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }
}

public struct CommandFailureSummary: Equatable, Codable, Sendable {
    public let timestamp: Date?
    public let commandName: String?
    public let exitCode: Int

    public init(timestamp: Date?, commandName: String?, exitCode: Int) {
        self.timestamp = timestamp
        self.commandName = commandName
        self.exitCode = exitCode
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public let fileURL: URL
    public var sessionID: String?
    public var threadName: String?
    public var workingDirectory: String?
    public var model: String?
    public var reasoningEffort: String?
    public var summaryMode: String?
    public var realtimeActive: Bool?
    public var startedAt: Date?
    public var updatedAt: Date?
    public var tokenEvents: [TokenEvent]
    public var compactionEvents: Int
    public var turnDurationsMilliseconds: [Int]
    public var timeToFirstTokenMilliseconds: [Int]
    public var commandEvents: Int
    public var failedCommandEvents: Int
    public var failedCommandSummaries: [CommandFailureSummary]
    public var toolCallEvents: Int
    public var changedFileEvents: Int

    public init(fileURL: URL) {
        self.fileURL = fileURL
        sessionID = nil
        threadName = nil
        workingDirectory = nil
        model = nil
        reasoningEffort = nil
        summaryMode = nil
        realtimeActive = nil
        startedAt = nil
        updatedAt = nil
        tokenEvents = []
        compactionEvents = 0
        turnDurationsMilliseconds = []
        timeToFirstTokenMilliseconds = []
        commandEvents = 0
        failedCommandEvents = 0
        failedCommandSummaries = []
        toolCallEvents = 0
        changedFileEvents = 0
    }

    public var latestTokenEvent: TokenEvent? {
        tokenEvents.last
    }

    public var totalTokens: Int {
        latestTokenEvent?.totalUsage.totalTokens ?? 0
    }

    public var averageTurnTokens: Int {
        let totals = turnTokenTotals
        guard totals.isEmpty == false else {
            return 0
        }
        return totals.reduce(0, +) / totals.count
    }

    public var medianTurnTokens: Int {
        Self.median(turnTokenTotals.sorted())
    }

    public var contextUsagePercent: Double? {
        guard let event = latestTokenEvent,
              let contextWindow = event.modelContextWindow,
              contextWindow > 0
        else {
            return nil
        }
        return min(100.0, Double(event.lastUsage.inputTokens) / Double(contextWindow) * 100.0)
    }

    public var contextLeftPercent: Double? {
        contextUsagePercent.map { min(max(100 - $0, 0), 100) }
    }

    public var contextUsedTokens: Int? {
        latestTokenEvent?.lastUsage.inputTokens
    }

    public var contextWindow: Int? {
        latestTokenEvent?.modelContextWindow
    }

    public var latestRateLimits: CodexRateLimits? {
        tokenEvents.reversed().first { $0.rateLimits != nil }?.rateLimits
    }

    public var completedTurns: Int {
        turnDurationsMilliseconds.count
    }

    public var lastTurnDurationMilliseconds: Int? {
        turnDurationsMilliseconds.last
    }

    public var medianTurnDurationMilliseconds: Int? {
        medianValue(turnDurationsMilliseconds.sorted())
    }

    public var averageTurnDurationMilliseconds: Int? {
        guard turnDurationsMilliseconds.isEmpty == false else {
            return nil
        }
        return turnDurationsMilliseconds.reduce(0, +) / turnDurationsMilliseconds.count
    }

    public var medianTimeToFirstTokenMilliseconds: Int? {
        medianValue(timeToFirstTokenMilliseconds.sorted())
    }

    public var latestTimeToFirstTokenMilliseconds: Int? {
        timeToFirstTokenMilliseconds.last
    }

    public var cachedInputPercent: Double? {
        guard let usage = latestTokenEvent?.totalUsage,
              usage.inputTokens > 0
        else {
            return nil
        }
        return min(max(Double(usage.cachedInputTokens) / Double(usage.inputTokens) * 100, 0), 100)
    }

    public var reasoningOutputPercent: Double? {
        guard let usage = latestTokenEvent?.totalUsage else {
            return nil
        }
        let totalOutput = usage.outputTokens + usage.reasoningOutputTokens
        guard totalOutput > 0 else {
            return nil
        }
        return min(max(Double(usage.reasoningOutputTokens) / Double(totalOutput) * 100, 0), 100)
    }

    public var averageContextGrowthPerTurnTokens: Int {
        let values = tokenEvents.map(\.lastUsage.inputTokens).filter { $0 > 0 }
        guard values.isEmpty == false else {
            return 0
        }
        return values.reduce(0, +) / values.count
    }

    public var latestContextGrowthTokens: Int {
        latestTokenEvent?.lastUsage.inputTokens ?? 0
    }

    private var turnTokenTotals: [Int] {
        tokenEvents.map(\.lastUsage.totalTokens).filter { $0 > 0 }
    }

    private static func median(_ values: [Int]) -> Int {
        guard values.isEmpty == false else {
            return 0
        }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private func medianValue(_ values: [Int]) -> Int? {
        guard values.isEmpty == false else {
            return nil
        }
        return Self.median(values)
    }
}

public struct ModexSummary: Equatable, Sendable {
    public let sessions: [SessionSnapshot]
    public let scanMetrics: ScanMetrics?
    public let sessionsScanned: Int
    public let tokenEvents: Int
    public let totalTokens: Int
    public let averageTurnTokens: Int
    public let medianTurnTokens: Int
    public let compactionEvents: Int
    public let contextUsagePercent: Double?
    public let contextLeftPercent: Double?
    public let latestRateLimits: CodexRateLimits?
    public let latestSession: SessionSnapshot?

    public init(
        sessions: [SessionSnapshot],
        scanMetrics: ScanMetrics? = nil,
        statusRateLimits: CodexRateLimits? = nil
    ) {
        self.sessions = sessions.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
        self.scanMetrics = scanMetrics
        sessionsScanned = sessions.count
        tokenEvents = sessions.reduce(0) { $0 + $1.tokenEvents.count }
        totalTokens = sessions.reduce(0) { total, session in
            total + session.totalTokens
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
        latestSession = self.sessions.first
        contextUsagePercent = latestSession?.contextUsagePercent
        contextLeftPercent = latestSession?.contextLeftPercent
        let scannedRateLimits = Self.latestRateLimits(from: self.sessions, now: Date())
        latestRateLimits = Self.mergedRateLimits(preferred: statusRateLimits, fallback: scannedRateLimits)
    }

    private static func mergedRateLimits(
        preferred: CodexRateLimits?,
        fallback: CodexRateLimits?
    ) -> CodexRateLimits? {
        guard preferred != nil || fallback != nil else {
            return nil
        }

        var bucketsByKey: [String: CodexRateLimitBucket] = [:]
        for bucket in fallback?.buckets ?? [] {
            bucketsByKey[bucket.key] = bucket
        }
        for bucket in preferred?.buckets ?? [] {
            bucketsByKey[bucket.key] = bucket
        }

        let buckets = orderedBuckets(Array(bucketsByKey.values))
        let planType = preferred?.planType ?? fallback?.planType
        guard buckets.isEmpty == false || planType != nil else {
            return nil
        }
        return CodexRateLimits(buckets: buckets, planType: planType)
    }

    private static func latestRateLimits(from sessions: [SessionSnapshot], now: Date) -> CodexRateLimits? {
        var latestBuckets: [String: (timestamp: Date, bucket: CodexRateLimitBucket)] = [:]
        var latestPlanType: (timestamp: Date, value: String)?

        for session in sessions {
            let fallbackTimestamp = session.updatedAt ?? .distantPast
            for event in session.tokenEvents {
                guard let rateLimits = event.rateLimits else {
                    continue
                }

                let timestamp = event.timestamp ?? fallbackTimestamp
                if let planType = rateLimits.planType,
                   latestPlanType == nil || timestamp >= latestPlanType!.timestamp
                {
                    latestPlanType = (timestamp, planType)
                }

                for bucket in rateLimits.buckets where bucket.hasFreshLimitWindow(at: now) {
                    let key = bucket.key
                    if latestBuckets[key] == nil || timestamp >= latestBuckets[key]!.timestamp {
                        latestBuckets[key] = (timestamp, bucket)
                    }
                }
            }
        }

        let buckets = latestBuckets.values
            .sorted { lhs, rhs in
                if lhs.bucket.isGeneral != rhs.bucket.isGeneral {
                    return lhs.bucket.isGeneral
                }
                if lhs.bucket.isSpark != rhs.bucket.isSpark {
                    return rhs.bucket.isSpark == false
                }
                return lhs.timestamp > rhs.timestamp
            }
            .map(\.bucket)

        guard buckets.isEmpty == false || latestPlanType != nil else {
            return nil
        }
        return CodexRateLimits(buckets: buckets, planType: latestPlanType?.value)
    }

    private static func orderedBuckets(_ buckets: [CodexRateLimitBucket]) -> [CodexRateLimitBucket] {
        buckets.sorted { lhs, rhs in
            if lhs.isGeneral != rhs.isGeneral {
                return lhs.isGeneral
            }
            if lhs.isSpark != rhs.isSpark {
                return rhs.isSpark == false
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
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

public struct CodexScanResult: Equatable, Sendable {
    public let sessions: [SessionSnapshot]
    public let metrics: ScanMetrics

    public init(sessions: [SessionSnapshot], metrics: ScanMetrics) {
        self.sessions = sessions
        self.metrics = metrics
    }
}

public struct ScanMetrics: Equatable, Sendable {
    public let parserMode: String
    public let filesSelected: Int
    public let filesParsed: Int
    public let bytesRead: Int
    public let durationSeconds: Double
    public let maximumConcurrentParses: Int
    public let configuredMaximumConcurrentParses: Int
    public let chunkSizeBytes: Int
    public let maximumLineBufferBytes: Int
    public let sessionIndexMaximumLineBufferBytes: Int
    public let cacheEnabled: Bool
    public let cacheHits: Int
    public let cacheMisses: Int
    public let cacheEntries: Int
    public let cacheBytesSaved: Int
    public let fileMetrics: [FileScanMetrics]

    public init(
        parserMode: String,
        filesSelected: Int,
        filesParsed: Int,
        bytesRead: Int,
        durationSeconds: Double,
        maximumConcurrentParses: Int,
        configuredMaximumConcurrentParses: Int? = nil,
        chunkSizeBytes: Int,
        maximumLineBufferBytes: Int,
        sessionIndexMaximumLineBufferBytes: Int,
        cacheEnabled: Bool = false,
        cacheHits: Int = 0,
        cacheMisses: Int = 0,
        cacheEntries: Int = 0,
        cacheBytesSaved: Int = 0,
        fileMetrics: [FileScanMetrics]
    ) {
        self.parserMode = parserMode
        self.filesSelected = filesSelected
        self.filesParsed = filesParsed
        self.bytesRead = bytesRead
        self.durationSeconds = durationSeconds
        self.maximumConcurrentParses = maximumConcurrentParses
        self.configuredMaximumConcurrentParses = configuredMaximumConcurrentParses ?? maximumConcurrentParses
        self.chunkSizeBytes = chunkSizeBytes
        self.maximumLineBufferBytes = maximumLineBufferBytes
        self.sessionIndexMaximumLineBufferBytes = sessionIndexMaximumLineBufferBytes
        self.cacheEnabled = cacheEnabled
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.cacheEntries = cacheEntries
        self.cacheBytesSaved = cacheBytesSaved
        self.fileMetrics = fileMetrics
    }
}

public struct FileScanMetrics: Equatable, Sendable {
    public let fileURL: URL
    public let sessionID: String?
    public let threadName: String?
    public let workingDirectory: String?
    public let bytesRead: Int
    public let durationSeconds: Double
    public let tokenEvents: Int
    public let compactionEvents: Int
    public let maximumBufferedLineBytes: Int
    public let oversizedLines: Int
    public let cacheHit: Bool

    public init(
        fileURL: URL,
        sessionID: String? = nil,
        threadName: String? = nil,
        workingDirectory: String? = nil,
        bytesRead: Int,
        durationSeconds: Double,
        tokenEvents: Int,
        compactionEvents: Int,
        maximumBufferedLineBytes: Int,
        oversizedLines: Int,
        cacheHit: Bool = false
    ) {
        self.fileURL = fileURL
        self.sessionID = sessionID
        self.threadName = threadName
        self.workingDirectory = workingDirectory
        self.bytesRead = bytesRead
        self.durationSeconds = durationSeconds
        self.tokenEvents = tokenEvents
        self.compactionEvents = compactionEvents
        self.maximumBufferedLineBytes = maximumBufferedLineBytes
        self.oversizedLines = oversizedLines
        self.cacheHit = cacheHit
    }

    public func withThreadName(_ threadName: String?) -> FileScanMetrics {
        FileScanMetrics(
            fileURL: fileURL,
            sessionID: sessionID,
            threadName: threadName,
            workingDirectory: workingDirectory,
            bytesRead: bytesRead,
            durationSeconds: durationSeconds,
            tokenEvents: tokenEvents,
            compactionEvents: compactionEvents,
            maximumBufferedLineBytes: maximumBufferedLineBytes,
            oversizedLines: oversizedLines,
            cacheHit: cacheHit
        )
    }

    public func asCacheHit() -> FileScanMetrics {
        FileScanMetrics(
            fileURL: fileURL,
            sessionID: sessionID,
            threadName: threadName,
            workingDirectory: workingDirectory,
            bytesRead: 0,
            durationSeconds: 0,
            tokenEvents: tokenEvents,
            compactionEvents: compactionEvents,
            maximumBufferedLineBytes: maximumBufferedLineBytes,
            oversizedLines: oversizedLines,
            cacheHit: true
        )
    }
}
