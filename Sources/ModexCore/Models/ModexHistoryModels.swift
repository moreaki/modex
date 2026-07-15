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
    public let incrementalFiles: Int
    public let incrementalBytesSaved: Int
    public let processMemoryBytes: Int
    public let processPeakMemoryBytes: Int
    public let cpuTimeSeconds: Double
    public let physicalBytesRead: Int
    public let physicalBytesWritten: Int
    public let idleWakeups: Int
    public let interruptWakeups: Int
    public let voluntaryContextSwitches: Int
    public let involuntaryContextSwitches: Int

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
        maximumConcurrentParses: Int,
        incrementalFiles: Int = 0,
        incrementalBytesSaved: Int = 0,
        processMemoryBytes: Int = 0,
        processPeakMemoryBytes: Int = 0,
        cpuTimeSeconds: Double = 0,
        physicalBytesRead: Int = 0,
        physicalBytesWritten: Int = 0,
        idleWakeups: Int = 0,
        interruptWakeups: Int = 0,
        voluntaryContextSwitches: Int = 0,
        involuntaryContextSwitches: Int = 0
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
    }

    public var cacheHitPercent: Double? {
        guard filesSelected > 0 else {
            return nil
        }
        return min(max(Double(cacheHits) / Double(filesSelected) * 100, 0), 100)
    }
}

public struct ModexScanResourceTotals: Equatable, Sendable {
    public let scanCount: Int
    public let scanActiveSeconds: Double
    public let cpuTimeSeconds: Double
    public let logicalBytesRead: Int
    public let physicalBytesRead: Int
    public let physicalBytesWritten: Int
    public let idleWakeups: Int
    public let interruptWakeups: Int
    public let voluntaryContextSwitches: Int
    public let involuntaryContextSwitches: Int

    public init(
        scanCount: Int,
        scanActiveSeconds: Double,
        cpuTimeSeconds: Double,
        logicalBytesRead: Int,
        physicalBytesRead: Int,
        physicalBytesWritten: Int,
        idleWakeups: Int,
        interruptWakeups: Int,
        voluntaryContextSwitches: Int,
        involuntaryContextSwitches: Int
    ) {
        self.scanCount = scanCount
        self.scanActiveSeconds = scanActiveSeconds
        self.cpuTimeSeconds = cpuTimeSeconds
        self.logicalBytesRead = logicalBytesRead
        self.physicalBytesRead = physicalBytesRead
        self.physicalBytesWritten = physicalBytesWritten
        self.idleWakeups = idleWakeups
        self.interruptWakeups = interruptWakeups
        self.voluntaryContextSwitches = voluntaryContextSwitches
        self.involuntaryContextSwitches = involuntaryContextSwitches
    }
}

public struct ModexScanResourceAverages: Equatable, Sendable {
    public let scanCount: Int
    public let averageMemoryBytes: Int
    public let highestMemoryBytes: Int
    public let averageCPUTimeSeconds: Double
    public let averageCPUPercent: Double
    public let averagePhysicalBytesRead: Int
    public let averagePhysicalBytesWritten: Int
    public let averageIdleWakeups: Double
    public let averageInterruptWakeups: Double
    public let averageVoluntaryContextSwitches: Double
    public let averageInvoluntaryContextSwitches: Double

    public init(
        scanCount: Int,
        averageMemoryBytes: Int,
        highestMemoryBytes: Int,
        averageCPUTimeSeconds: Double,
        averageCPUPercent: Double,
        averagePhysicalBytesRead: Int,
        averagePhysicalBytesWritten: Int,
        averageIdleWakeups: Double,
        averageInterruptWakeups: Double,
        averageVoluntaryContextSwitches: Double,
        averageInvoluntaryContextSwitches: Double
    ) {
        self.scanCount = scanCount
        self.averageMemoryBytes = averageMemoryBytes
        self.highestMemoryBytes = highestMemoryBytes
        self.averageCPUTimeSeconds = averageCPUTimeSeconds
        self.averageCPUPercent = averageCPUPercent
        self.averagePhysicalBytesRead = averagePhysicalBytesRead
        self.averagePhysicalBytesWritten = averagePhysicalBytesWritten
        self.averageIdleWakeups = averageIdleWakeups
        self.averageInterruptWakeups = averageInterruptWakeups
        self.averageVoluntaryContextSwitches = averageVoluntaryContextSwitches
        self.averageInvoluntaryContextSwitches = averageInvoluntaryContextSwitches
    }
}

public extension ModexHistorySnapshot {
    func scanResourceTotals(over interval: TimeInterval = 60 * 60) -> ModexScanResourceTotals {
        let samples = measuredScanSamples(over: interval)
        return ModexScanResourceTotals(
            scanCount: samples.count,
            scanActiveSeconds: samples.reduce(0) { $0 + $1.durationSeconds },
            cpuTimeSeconds: samples.reduce(0) { $0 + $1.cpuTimeSeconds },
            logicalBytesRead: samples.reduce(0) { $0 + $1.bytesRead },
            physicalBytesRead: samples.reduce(0) { $0 + $1.physicalBytesRead },
            physicalBytesWritten: samples.reduce(0) { $0 + $1.physicalBytesWritten },
            idleWakeups: samples.reduce(0) { $0 + $1.idleWakeups },
            interruptWakeups: samples.reduce(0) { $0 + $1.interruptWakeups },
            voluntaryContextSwitches: samples.reduce(0) { $0 + $1.voluntaryContextSwitches },
            involuntaryContextSwitches: samples.reduce(0) { $0 + $1.involuntaryContextSwitches }
        )
    }

    func scanResourceAverages(over interval: TimeInterval = 60 * 60) -> ModexScanResourceAverages {
        let samples = measuredScanSamples(over: interval)
        let count = samples.count
        guard count > 0 else {
            return ModexScanResourceAverages(
                scanCount: 0,
                averageMemoryBytes: 0,
                highestMemoryBytes: 0,
                averageCPUTimeSeconds: 0,
                averageCPUPercent: 0,
                averagePhysicalBytesRead: 0,
                averagePhysicalBytesWritten: 0,
                averageIdleWakeups: 0,
                averageInterruptWakeups: 0,
                averageVoluntaryContextSwitches: 0,
                averageInvoluntaryContextSwitches: 0
            )
        }

        let countDouble = Double(count)
        let totalDuration = samples.reduce(0) { $0 + $1.durationSeconds }
        let totalCPUTime = samples.reduce(0) { $0 + $1.cpuTimeSeconds }
        return ModexScanResourceAverages(
            scanCount: count,
            averageMemoryBytes: averageInt(samples, keyPath: \.processMemoryBytes),
            highestMemoryBytes: samples.map(\.processMemoryBytes).max() ?? 0,
            averageCPUTimeSeconds: totalCPUTime / countDouble,
            averageCPUPercent: totalDuration > 0 ? totalCPUTime / totalDuration * 100 : 0,
            averagePhysicalBytesRead: averageInt(samples, keyPath: \.physicalBytesRead),
            averagePhysicalBytesWritten: averageInt(samples, keyPath: \.physicalBytesWritten),
            averageIdleWakeups: Double(samples.reduce(0) { $0 + $1.idleWakeups }) / countDouble,
            averageInterruptWakeups: Double(samples.reduce(0) { $0 + $1.interruptWakeups }) / countDouble,
            averageVoluntaryContextSwitches: Double(
                samples.reduce(0) { $0 + $1.voluntaryContextSwitches }
            ) / countDouble,
            averageInvoluntaryContextSwitches: Double(
                samples.reduce(0) { $0 + $1.involuntaryContextSwitches }
            ) / countDouble
        )
    }

    private func measuredScanSamples(over interval: TimeInterval) -> [ModexScanHistorySample] {
        let cutoff = generatedAt.addingTimeInterval(-max(0, interval))
        return scanSamples.filter {
            $0.sampledAt >= cutoff
                && $0.sampledAt <= generatedAt
                && $0.processMemoryBytes > 0
        }
    }

    private func averageInt(
        _ samples: [ModexScanHistorySample],
        keyPath: KeyPath<ModexScanHistorySample, Int>
    ) -> Int {
        let total = samples.reduce(Int64(0)) { partial, sample in
            partial + Int64(sample[keyPath: keyPath])
        }
        return Int((Double(total) / Double(samples.count)).rounded())
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
    case agentRunning
    case agentGenerated
    case agentFailed
    case stale
}

public struct ModexAgentInsightResult: Equatable, Codable, Sendable, Identifiable {
    public var id: String {
        "\(sourceInsightID)-\(sourceFingerprint)"
    }

    public let sourceInsightID: String
    public let sourceFingerprint: String
    public let generatedAt: Date
    public let provider: String
    public let title: String
    public let summary: String
    public let category: String
    public let severity: String
    public let confidence: Double
    public let suggestedAction: String
    public let evidenceIDs: [String]

    public init(
        sourceInsightID: String,
        sourceFingerprint: String,
        generatedAt: Date,
        provider: String,
        title: String,
        summary: String,
        category: String,
        severity: String,
        confidence: Double,
        suggestedAction: String,
        evidenceIDs: [String]
    ) {
        self.sourceInsightID = sourceInsightID
        self.sourceFingerprint = sourceFingerprint
        self.generatedAt = generatedAt
        self.provider = provider
        self.title = title
        self.summary = summary
        self.category = category
        self.severity = severity
        self.confidence = min(max(confidence, 0), 1)
        self.suggestedAction = suggestedAction
        self.evidenceIDs = evidenceIDs
    }
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
    public let agentResult: ModexAgentInsightResult?
    public let agentError: String?

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
        sourcePath: String? = nil,
        agentResult: ModexAgentInsightResult? = nil,
        agentError: String? = nil
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
        self.agentResult = agentResult
        self.agentError = agentError
    }

    public var agentFingerprint: String {
        ModexStableHash.hex(
            [
                id,
                kind.rawValue,
                severity.rawValue.description,
                sessionKey ?? "",
                sessionID ?? "",
                count.map(String.init) ?? "",
            ]
        )
    }

    public func applyingAgentState(
        result: ModexAgentInsightResult?,
        isRunning: Bool,
        error: String?
    ) -> ModexInsight {
        let nextStatus: ModexInsightStatus
        let nextResult: ModexAgentInsightResult?
        let nextError: String?

        if isRunning {
            nextStatus = .agentRunning
            nextResult = result
            nextError = nil
        } else if let error {
            nextStatus = .agentFailed
            nextResult = result
            nextError = error
        } else if let result {
            if result.sourceFingerprint == agentFingerprint {
                nextStatus = .agentGenerated
            } else {
                nextStatus = .stale
            }
            nextResult = result
            nextError = nil
        } else {
            nextStatus = status
            nextResult = nil
            nextError = nil
        }

        return ModexInsight(
            id: id,
            kind: kind,
            severity: severity,
            status: nextStatus,
            sessionKey: sessionKey,
            sessionID: sessionID,
            threadName: threadName,
            projectTitle: projectTitle,
            primaryValue: primaryValue,
            secondaryValue: secondaryValue,
            count: count,
            evidenceCount: evidenceCount,
            updatedAt: updatedAt,
            sourcePath: sourcePath,
            agentResult: nextResult,
            agentError: nextError
        )
    }

}

public enum ModexStableHash {
    public static func hex(_ parts: [String]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for part in parts {
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
            hash ^= 0xff
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}
