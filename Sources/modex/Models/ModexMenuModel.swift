import Combine
import Foundation
import ModexCore

@MainActor
final class ModexMenuModel: ObservableObject {
    @Published var summary: ModexSummary?
    @Published var history: ModexHistorySnapshot?
    @Published var insights: [ModexInsight] = []
    @Published var agentInsightResults: [String: ModexAgentInsightResult] = [:]
    @Published var runningAgentInsightIDs: Set<String> = []
    @Published var agentInsightErrors: [String: String] = [:]
    @Published var settings: ModexAppSettings
    @Published var intelligenceConnectionState: ModexIntelligenceConnectionState
    @Published var intelligenceExecutables: [LocalCodexExecutable] = []
    @Published var isDiscoveringIntelligenceExecutables = false
    @Published var intelligenceCapabilities: LocalCodexCapabilities?
    @Published var isDiscoveringIntelligenceCapabilities = false
    @Published var intelligenceCapabilityError: String?
    @Published var isRefreshing = false
    @Published var readFailureMessage: String?

    init(
        settings: ModexAppSettings,
        intelligenceConnectionState: ModexIntelligenceConnectionState? = nil
    ) {
        let settings = settings.normalized()
        self.settings = settings
        self.intelligenceConnectionState = intelligenceConnectionState
            ?? (settings.intelligence.enabled ? .unknown : .off)
    }

    var latestMetrics: ScanMetrics? {
        summary?.scanMetrics
    }

    var displayedInsights: [ModexInsight] {
        insights.map { insight in
            insight.applyingAgentState(
                result: agentInsightResults[insight.id],
                isRunning: runningAgentInsightIDs.contains(insight.id),
                error: agentInsightErrors[insight.id]
            )
        }
    }

    var canRequestAgentInsights: Bool {
        settings.intelligence.enabled && settings.intelligence.provider != .off
    }

    var lastReadStatus: String {
        guard let metrics = summary?.scanMetrics else {
            return ""
        }
        if metrics.cacheEnabled, metrics.cacheHits > 0 {
            return ModexStrings.format(
                "overview.readStatusCached",
                ByteCountFormatter.string(fromByteCount: Int64(metrics.bytesRead), countStyle: .file),
                concurrencyValue(metrics),
                metrics.cacheHits
            )
        }
        return ModexStrings.format(
            "overview.readStatus",
            ByteCountFormatter.string(fromByteCount: Int64(metrics.bytesRead), countStyle: .file),
            concurrencyValue(metrics)
        )
    }

    private func concurrencyValue(_ metrics: ScanMetrics) -> String {
        ModexStrings.format(
            "instrumentation.concurrencyValue",
            metrics.maximumConcurrentParses,
            metrics.configuredMaximumConcurrentParses
        )
    }
}
