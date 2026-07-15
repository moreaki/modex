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
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let limitID: String?
    public let limitName: String?
    public let planType: String?
    public let reachedType: String?

    public init(
        primary: CodexRateLimitWindow? = nil,
        secondary: CodexRateLimitWindow? = nil,
        limitID: String? = nil,
        limitName: String? = nil,
        planType: String? = nil,
        reachedType: String? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.limitID = limitID
        self.limitName = limitName
        self.planType = planType
        self.reachedType = reachedType
    }

    public var mostConstrainedLeftPercent: Double? {
        [primary?.leftPercent, secondary?.leftPercent]
            .compactMap(\.self)
            .min()
    }

    public var sevenDayWindow: CodexRateLimitWindow? {
        [primary, secondary]
            .compactMap(\.self)
            .first { $0.windowMinutes == 10_080 }
    }

    public var isGeneralAccountLimit: Bool {
        if let normalizedID = Self.normalized(limitID) {
            return normalizedID == "codex"
        }

        guard let normalizedName = Self.normalized(limitName) else {
            return true
        }
        return normalizedName == "codex"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
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
    public var gitOriginURL: String?
    public var model: String?
    public var reasoningEffort: String?
    public var serviceTier: String?
    public var personality: String?
    public var collaborationMode: String?
    public var summaryMode: String?
    public var realtimeActive: Bool?
    public var source: String?
    public var cliVersion: String?
    public var modelProvider: String?
    public var agentNickname: String?
    public var agentRole: String?
    public var agentPath: String?
    public var parentThreadID: String?
    public var threadSource: String?
    public var threadScope: CodexThreadScope?
    public var isArchived: Bool
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
    public var patchEvents: Int
    public var failedPatchEvents: Int
    public var mcpToolCallEvents: Int
    public var webSearchEvents: Int
    public var subagentActivityEvents: Int
    public var abortedTurnEvents: Int

    public init(fileURL: URL) {
        self.fileURL = fileURL
        sessionID = nil
        threadName = nil
        workingDirectory = nil
        gitOriginURL = nil
        model = nil
        reasoningEffort = nil
        serviceTier = nil
        personality = nil
        collaborationMode = nil
        summaryMode = nil
        realtimeActive = nil
        source = nil
        cliVersion = nil
        modelProvider = nil
        agentNickname = nil
        agentRole = nil
        agentPath = nil
        parentThreadID = nil
        threadSource = nil
        threadScope = nil
        isArchived = false
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
        patchEvents = 0
        failedPatchEvents = 0
        mcpToolCallEvents = 0
        webSearchEvents = 0
        subagentActivityEvents = 0
        abortedTurnEvents = 0
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
        let values = contextGrowthTokensByEvent
        guard values.isEmpty == false else {
            return 0
        }
        return values.reduce(0, +) / values.count
    }

    public var latestContextGrowthTokens: Int {
        contextGrowthTokensByEvent.last ?? 0
    }

    public var contextGrowthTokensByEvent: [Int] {
        guard tokenEvents.count > 1 else {
            return []
        }

        return zip(tokenEvents, tokenEvents.dropFirst()).map { previous, current in
            max(current.lastUsage.inputTokens - previous.lastUsage.inputTokens, 0)
        }
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
    /// Highest current context pressure among scanned, non-archived sessions.
    public let contextUsagePercent: Double?
    public let contextLeftPercent: Double?
    /// Newest general Codex account limit, excluding named model-specific pools.
    public let latestRateLimits: CodexRateLimits?
    public let latestRateLimitsObservedAt: Date?
    public let latestSession: SessionSnapshot?
    public let contextSession: SessionSnapshot?

    public init(sessions: [SessionSnapshot], scanMetrics: ScanMetrics? = nil) {
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
        contextSession = Self.highestContextSession(in: self.sessions)
        contextUsagePercent = contextSession?.contextUsagePercent
        contextLeftPercent = contextSession?.contextLeftPercent

        let generalRateLimits = Self.latestGeneralRateLimits(in: self.sessions)
        latestRateLimits = generalRateLimits?.limits
        latestRateLimitsObservedAt = generalRateLimits?.observedAt
    }

    private static func median(_ values: [Int]) -> Int {
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private static func highestContextSession(in sessions: [SessionSnapshot]) -> SessionSnapshot? {
        sessions.reduce(nil) { selected, session in
            guard session.isArchived == false,
                  let percent = session.contextUsagePercent
            else {
                return selected
            }
            guard let selected,
                  let selectedPercent = selected.contextUsagePercent
            else {
                return session
            }
            return percent > selectedPercent ? session : selected
        }
    }

    private static func latestGeneralRateLimits(
        in sessions: [SessionSnapshot]
    ) -> (limits: CodexRateLimits, observedAt: Date?)? {
        var selected: (limits: CodexRateLimits, observedAt: Date?, orderingDate: Date)?

        for session in sessions {
            for event in session.tokenEvents {
                guard let limits = event.rateLimits,
                      limits.isGeneralAccountLimit
                else {
                    continue
                }

                let observedAt = event.timestamp ?? session.updatedAt
                let orderingDate = observedAt ?? .distantPast
                if let selected, orderingDate < selected.orderingDate {
                    continue
                }
                selected = (limits, observedAt, orderingDate)
            }
        }

        return selected.map { ($0.limits, $0.observedAt) }
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
    public let discoveryMode: String
    public let metadataHits: Int
    public let sessionIndexBytesRead: Int
    public let sidebarStateBytesRead: Int
    public let sidebarStateCacheHit: Bool
    public let cacheEnabled: Bool
    public let cacheHits: Int
    public let cacheMisses: Int
    public let cacheEntries: Int
    public let cacheBytesSaved: Int
    public let incrementalFiles: Int
    public let incrementalBytesSaved: Int
    public let processMemoryBytes: UInt64
    public let processPeakMemoryBytes: UInt64
    public let cpuTimeSeconds: Double
    public let physicalBytesRead: UInt64
    public let physicalBytesWritten: UInt64
    public let idleWakeups: UInt64
    public let interruptWakeups: UInt64
    public let voluntaryContextSwitches: Int64
    public let involuntaryContextSwitches: Int64
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
        discoveryMode: String = "filesystem",
        metadataHits: Int = 0,
        sessionIndexBytesRead: Int = 0,
        sidebarStateBytesRead: Int = 0,
        sidebarStateCacheHit: Bool = false,
        cacheEnabled: Bool = false,
        cacheHits: Int = 0,
        cacheMisses: Int = 0,
        cacheEntries: Int = 0,
        cacheBytesSaved: Int = 0,
        incrementalFiles: Int = 0,
        incrementalBytesSaved: Int = 0,
        processMemoryBytes: UInt64 = 0,
        processPeakMemoryBytes: UInt64 = 0,
        cpuTimeSeconds: Double = 0,
        physicalBytesRead: UInt64 = 0,
        physicalBytesWritten: UInt64 = 0,
        idleWakeups: UInt64 = 0,
        interruptWakeups: UInt64 = 0,
        voluntaryContextSwitches: Int64 = 0,
        involuntaryContextSwitches: Int64 = 0,
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
        self.discoveryMode = discoveryMode
        self.metadataHits = metadataHits
        self.sessionIndexBytesRead = sessionIndexBytesRead
        self.sidebarStateBytesRead = sidebarStateBytesRead
        self.sidebarStateCacheHit = sidebarStateCacheHit
        self.cacheEnabled = cacheEnabled
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.cacheEntries = cacheEntries
        self.cacheBytesSaved = cacheBytesSaved
        self.incrementalFiles = incrementalFiles
        self.incrementalBytesSaved = incrementalBytesSaved
        self.processMemoryBytes = processMemoryBytes
        self.processPeakMemoryBytes = processPeakMemoryBytes
        self.cpuTimeSeconds = cpuTimeSeconds
        self.physicalBytesRead = physicalBytesRead
        self.physicalBytesWritten = physicalBytesWritten
        self.idleWakeups = idleWakeups
        self.interruptWakeups = interruptWakeups
        self.voluntaryContextSwitches = voluntaryContextSwitches
        self.involuntaryContextSwitches = involuntaryContextSwitches
        self.fileMetrics = fileMetrics
    }

    public var averageCPUPercent: Double {
        guard durationSeconds > 0 else {
            return 0
        }
        return cpuTimeSeconds / durationSeconds * 100
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
    public let incrementalBytesSaved: Int

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
        cacheHit: Bool = false,
        incrementalBytesSaved: Int = 0
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
        self.incrementalBytesSaved = incrementalBytesSaved
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
            cacheHit: cacheHit,
            incrementalBytesSaved: incrementalBytesSaved
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
            cacheHit: true,
            incrementalBytesSaved: 0
        )
    }
}
