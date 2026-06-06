import Combine
import Foundation
import ModexCore

@MainActor
final class ModexMenuModel: ObservableObject {
    @Published var summary: ModexSummary?
    @Published var history: ModexHistorySnapshot?
    @Published var insights: [ModexInsight] = []
    @Published var settings: ModexAppSettings
    @Published var intelligenceConnectionState: ModexIntelligenceConnectionState
    @Published var isRefreshing = false
    @Published var readFailureMessage: String?

    init(settings: ModexAppSettings) {
        let settings = settings.normalized()
        self.settings = settings
        intelligenceConnectionState = settings.intelligence.enabled ? .unknown : .off
    }

    var latestMetrics: ScanMetrics? {
        summary?.scanMetrics
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
        if metrics.maximumConcurrentParses == metrics.configuredMaximumConcurrentParses {
            return "\(metrics.maximumConcurrentParses)x"
        }
        return "\(metrics.maximumConcurrentParses)x / \(metrics.configuredMaximumConcurrentParses)x"
    }
}
