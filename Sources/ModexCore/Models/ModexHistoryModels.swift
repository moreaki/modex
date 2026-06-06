import Foundation

public struct ModexHistorySnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let scanSamples: [ModexScanHistorySample]
    public let threadSamplesByKey: [String: [ModexThreadHistorySample]]

    public init(
        generatedAt: Date = Date(),
        scanSamples: [ModexScanHistorySample] = [],
        threadSamplesByKey: [String: [ModexThreadHistorySample]] = [:]
    ) {
        self.generatedAt = generatedAt
        self.scanSamples = scanSamples
        self.threadSamplesByKey = threadSamplesByKey
    }

    public func samples(for session: SessionSnapshot) -> [ModexThreadHistorySample] {
        threadSamplesByKey[Self.sessionKey(for: session)] ?? []
    }

    public static func sessionKey(for session: SessionSnapshot) -> String {
        if let sessionID = session.sessionID, sessionID.isEmpty == false {
            return sessionID
        }
        return session.fileURL.path
    }
}

public struct ModexScanHistorySample: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let sampledAt: Date
    public let durationSeconds: Double
    public let bytesRead: Int
    public let filesSelected: Int
    public let filesParsed: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let cacheEntries: Int
    public let cacheBytesSaved: Int
    public let maximumConcurrentParses: Int

    public init(
        id: Int64,
        sampledAt: Date,
        durationSeconds: Double,
        bytesRead: Int,
        filesSelected: Int,
        filesParsed: Int,
        cacheHits: Int,
        cacheMisses: Int,
        cacheEntries: Int,
        cacheBytesSaved: Int,
        maximumConcurrentParses: Int
    ) {
        self.id = id
        self.sampledAt = sampledAt
        self.durationSeconds = durationSeconds
        self.bytesRead = bytesRead
        self.filesSelected = filesSelected
        self.filesParsed = filesParsed
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.cacheEntries = cacheEntries
        self.cacheBytesSaved = cacheBytesSaved
        self.maximumConcurrentParses = maximumConcurrentParses
    }

    public var cacheHitPercent: Double? {
        guard filesSelected > 0 else {
            return nil
        }
        return min(max(Double(cacheHits) / Double(filesSelected) * 100, 0), 100)
    }
}

public struct ModexThreadHistorySample: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let sampledAt: Date
    public let sessionKey: String
    public let sessionID: String?
    public let threadName: String?
    public let projectTitle: String?
    public let sourcePath: String?
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
    public let toolCallEvents: Int
    public let changedFileEvents: Int
    public let cachedInputPercent: Double?
    public let reasoningOutputPercent: Double?
    public let lastTurnDurationMilliseconds: Int?
    public let medianTurnDurationMilliseconds: Int?
    public let latestTimeToFirstTokenMilliseconds: Int?

    public init(
        id: Int64,
        sampledAt: Date,
        sessionKey: String,
        sessionID: String?,
        threadName: String?,
        projectTitle: String?,
        sourcePath: String?,
        updatedAt: Date?,
        contextPercent: Double?,
        contextUsedTokens: Int?,
        contextWindow: Int?,
        totalTokens: Int,
        medianTurnTokens: Int,
        averageTurnTokens: Int,
        compactions: Int,
        commandEvents: Int,
        failedCommandEvents: Int,
        toolCallEvents: Int,
        changedFileEvents: Int,
        cachedInputPercent: Double?,
        reasoningOutputPercent: Double?,
        lastTurnDurationMilliseconds: Int?,
        medianTurnDurationMilliseconds: Int?,
        latestTimeToFirstTokenMilliseconds: Int?
    ) {
        self.id = id
        self.sampledAt = sampledAt
        self.sessionKey = sessionKey
        self.sessionID = sessionID
        self.threadName = threadName
        self.projectTitle = projectTitle
        self.sourcePath = sourcePath
        self.updatedAt = updatedAt
        self.contextPercent = contextPercent
        self.contextUsedTokens = contextUsedTokens
        self.contextWindow = contextWindow
        self.totalTokens = totalTokens
        self.medianTurnTokens = medianTurnTokens
        self.averageTurnTokens = averageTurnTokens
        self.compactions = compactions
        self.commandEvents = commandEvents
        self.failedCommandEvents = failedCommandEvents
        self.toolCallEvents = toolCallEvents
        self.changedFileEvents = changedFileEvents
        self.cachedInputPercent = cachedInputPercent
        self.reasoningOutputPercent = reasoningOutputPercent
        self.lastTurnDurationMilliseconds = lastTurnDurationMilliseconds
        self.medianTurnDurationMilliseconds = medianTurnDurationMilliseconds
        self.latestTimeToFirstTokenMilliseconds = latestTimeToFirstTokenMilliseconds
    }
}

public enum ModexInsightKind: String, CaseIterable, Sendable {
    case highContext
    case contextGrowth
    case failedCommands
    case slowTurn
    case repeatedCompactions
    case highCacheReuse
    case scanSlow
    case cacheCold
}

public enum ModexInsightSeverity: Int, CaseIterable, Sendable {
    case info = 0
    case notice = 1
    case warning = 2
    case critical = 3
}

public enum ModexInsightStatus: String, CaseIterable, Sendable {
    case deterministic
    case agentUnavailable
    case stale
}

public struct ModexSignalThresholds: Equatable, Sendable {
    public let yellowPercent: Double
    public let orangePercent: Double
    public let redPercent: Double

    public init(yellowPercent: Double, orangePercent: Double, redPercent: Double) {
        self.yellowPercent = yellowPercent
        self.orangePercent = orangePercent
        self.redPercent = redPercent
    }
}

public struct ModexInsight: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: ModexInsightKind
    public let severity: ModexInsightSeverity
    public let status: ModexInsightStatus
    public let sessionKey: String?
    public let sessionID: String?
    public let threadName: String?
    public let projectTitle: String?
    public let primaryValue: Double?
    public let secondaryValue: Double?
    public let count: Int?
    public let evidenceCount: Int
    public let updatedAt: Date?
    public let sourcePath: String?

    public init(
        id: String,
        kind: ModexInsightKind,
        severity: ModexInsightSeverity,
        status: ModexInsightStatus = .deterministic,
        sessionKey: String? = nil,
        sessionID: String? = nil,
        threadName: String? = nil,
        projectTitle: String? = nil,
        primaryValue: Double? = nil,
        secondaryValue: Double? = nil,
        count: Int? = nil,
        evidenceCount: Int,
        updatedAt: Date? = nil,
        sourcePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.status = status
        self.sessionKey = sessionKey
        self.sessionID = sessionID
        self.threadName = threadName
        self.projectTitle = projectTitle
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.count = count
        self.evidenceCount = evidenceCount
        self.updatedAt = updatedAt
        self.sourcePath = sourcePath
    }
}
