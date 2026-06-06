import Foundation

public struct ModexSignalEngine: Sendable {
    public init() {}

    public func insights(
        for summary: ModexSummary,
        history: ModexHistorySnapshot?,
        thresholds: ModexSignalThresholds
    ) -> [ModexInsight] {
        var insights: [ModexInsight] = []

        for session in summary.sessions {
            let sessionKey = ModexHistorySnapshot.sessionKey(for: session)
            let commonID = stableSessionID(session)
            let threadName = session.threadName
            let project = projectTitle(for: session)
            let updatedAt = session.updatedAt
            let sourcePath = session.fileURL.path

            if let percent = session.contextUsagePercent,
               percent >= thresholds.yellowPercent
            {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-high-context",
                        kind: .highContext,
                        severity: contextSeverity(percent, thresholds: thresholds),
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: percent,
                        secondaryValue: Double(session.contextUsedTokens ?? 0),
                        evidenceCount: evidenceCount(
                            session.contextUsedTokens,
                            session.contextWindow,
                            session.tokenEvents.count
                        ),
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }

            if let growth = contextGrowthPercent(for: session),
               growth >= 12
            {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-context-growth",
                        kind: .contextGrowth,
                        severity: growth >= 24 ? .warning : .notice,
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: growth,
                        secondaryValue: Double(session.latestContextGrowthTokens),
                        evidenceCount: max(2, session.tokenEvents.count),
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }

            if session.failedCommandEvents > 0 {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-failed-commands",
                        kind: .failedCommands,
                        severity: session.failedCommandEvents >= 10 ? .critical : (session.failedCommandEvents >= 3 ? .warning : .notice),
                        status: .agentUnavailable,
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: Double(session.failedCommandEvents),
                        secondaryValue: Double(session.commandEvents),
                        count: session.failedCommandEvents,
                        evidenceCount: max(1, session.failedCommandEvents),
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }

            if let lastDuration = session.lastTurnDurationMilliseconds,
               lastDuration >= slowTurnThresholdMilliseconds(session)
            {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-slow-turn",
                        kind: .slowTurn,
                        severity: lastDuration >= 20 * 60 * 1000 ? .warning : .notice,
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: Double(lastDuration),
                        secondaryValue: session.medianTurnDurationMilliseconds.map(Double.init),
                        evidenceCount: max(1, session.completedTurns),
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }

            if session.compactionEvents >= 2 {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-compactions",
                        kind: .repeatedCompactions,
                        severity: session.compactionEvents >= 5 ? .warning : .notice,
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: Double(session.compactionEvents),
                        count: session.compactionEvents,
                        evidenceCount: session.compactionEvents,
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }

            if let cached = session.cachedInputPercent,
               cached >= 75,
               session.totalTokens >= 1_000_000
            {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-cache-reuse",
                        kind: .highCacheReuse,
                        severity: .info,
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: cached,
                        secondaryValue: Double(session.totalTokens),
                        evidenceCount: max(1, session.tokenEvents.count),
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }

            if let history,
               let recentDelta = recentHistoricalContextDelta(for: session, history: history),
               recentDelta >= 15
            {
                insights.append(
                    ModexInsight(
                        id: "\(commonID)-history-context-delta",
                        kind: .contextGrowth,
                        severity: recentDelta >= 30 ? .warning : .notice,
                        sessionKey: sessionKey,
                        sessionID: session.sessionID,
                        threadName: threadName,
                        projectTitle: project,
                        primaryValue: recentDelta,
                        evidenceCount: history.samples(for: session).count,
                        updatedAt: updatedAt,
                        sourcePath: sourcePath
                    )
                )
            }
        }

        if let metrics = summary.scanMetrics {
            if metrics.durationSeconds >= 2 {
                insights.append(
                    ModexInsight(
                        id: "scan-slow-\(Int(metrics.durationSeconds.rounded()))",
                        kind: .scanSlow,
                        severity: metrics.durationSeconds >= 5 ? .warning : .notice,
                        primaryValue: metrics.durationSeconds,
                        secondaryValue: Double(metrics.bytesRead),
                        evidenceCount: metrics.fileMetrics.count,
                        updatedAt: Date()
                    )
                )
            }

            if metrics.cacheEnabled,
               metrics.filesSelected >= 5,
               metrics.cacheHits == 0
            {
                insights.append(
                    ModexInsight(
                        id: "cache-cold-\(metrics.filesSelected)-\(metrics.cacheMisses)",
                        kind: .cacheCold,
                        severity: .notice,
                        primaryValue: Double(metrics.cacheHits),
                        secondaryValue: Double(metrics.filesSelected),
                        evidenceCount: metrics.fileMetrics.count,
                        updatedAt: Date()
                    )
                )
            }
        }

        return Array(
            insights
                .sorted { lhs, rhs in
                    if lhs.severity.rawValue == rhs.severity.rawValue {
                        return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
                    }
                    return lhs.severity.rawValue > rhs.severity.rawValue
                }
                .prefix(40)
        )
    }

    private func stableSessionID(_ session: SessionSnapshot) -> String {
        session.sessionID ?? session.fileURL.lastPathComponent
    }

    private func projectTitle(for session: SessionSnapshot) -> String? {
        guard let workingDirectory = session.workingDirectory, workingDirectory.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    private func contextSeverity(
        _ percent: Double,
        thresholds: ModexSignalThresholds
    ) -> ModexInsightSeverity {
        if percent >= thresholds.redPercent {
            return .critical
        }
        if percent >= thresholds.orangePercent {
            return .warning
        }
        return .notice
    }

    private func evidenceCount(_ values: Any?...) -> Int {
        values.reduce(0) { count, value in
            value == nil ? count : count + 1
        }
    }

    private func contextGrowthPercent(for session: SessionSnapshot) -> Double? {
        let values = session.tokenEvents.compactMap { event -> Double? in
            guard let window = event.modelContextWindow, window > 0 else {
                return nil
            }
            return Double(event.lastUsage.inputTokens) / Double(window) * 100
        }
        guard values.count >= 2,
              let first = values.dropLast().last,
              let last = values.last
        else {
            return nil
        }
        return max(0, last - first)
    }

    private func recentHistoricalContextDelta(
        for session: SessionSnapshot,
        history: ModexHistorySnapshot
    ) -> Double? {
        let values = history.samples(for: session)
            .compactMap(\.contextPercent)
            .suffix(8)
        guard let first = values.first,
              let last = values.last,
              values.count >= 2
        else {
            return nil
        }
        return max(0, last - first)
    }

    private func slowTurnThresholdMilliseconds(_ session: SessionSnapshot) -> Int {
        guard session.completedTurns >= 3 else {
            return 5 * 60 * 1000
        }
        let baseline = session.medianTurnDurationMilliseconds ?? 0
        return max(5 * 60 * 1000, baseline * 2)
    }
}
