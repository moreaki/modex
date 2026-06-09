import Darwin
import Foundation
import ModexCore

@MainActor
final class ModexApplicationController: ObservableObject {
    let model: ModexMenuModel

    private let settingsStore: ModexSettingsStore
    private let monitor: ModexMonitor
    private let historyStore: ModexHistoryStore?
    private let signalEngine = ModexSignalEngine()
    private let agentEvidenceBuilder = ModexAgentInsightEvidenceBuilder()
    private var settings: ModexAppSettings
    private var latestSummary: ModexSummary?
    private var refreshTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var intelligenceTestTask: Task<Void, Never>?
    private var agentInsightTasks: [String: Task<Void, Never>] = [:]
    private var hasStarted = false

    init() {
        let settingsStore = ModexSettingsStore()
        let settings = settingsStore.load()
        let historyStore = try? ModexHistoryStore(databaseURL: ModexHistoryStore.defaultDatabaseURL())
        self.settingsStore = settingsStore
        self.settings = settings
        monitor = ModexMonitor(configuration: settings.monitorConfiguration)
        self.historyStore = historyStore
        model = ModexMenuModel(settings: settings)
        if let results = try? historyStore?.agentInsightResults() {
            model.agentInsightResults = Dictionary(
                uniqueKeysWithValues: results.map { ($0.sourceInsightID, $0) }
            )
        }
    }

    deinit {
        refreshTask?.cancel()
        refreshLoopTask?.cancel()
        historyTask?.cancel()
        intelligenceTestTask?.cancel()
        for task in agentInsightTasks.values {
            task.cancel()
        }
    }

    func start() {
        guard hasStarted == false else {
            return
        }
        hasStarted = true
        refresh()
        scheduleRefreshLoop()
    }

    func refresh() {
        guard refreshTask == nil else {
            return
        }

        model.isRefreshing = true
        refreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let result = await monitor.refresh()
            finishRefresh(result)
        }
    }

    func apply(settings newSettings: ModexAppSettings) {
        let oldSettings = settings
        settings = newSettings.normalized()
        settingsStore.save(settings)
        model.settings = settings
        if settings.intelligence.enabled == false || settings.intelligence.provider == .off {
            intelligenceTestTask?.cancel()
            intelligenceTestTask = nil
            for task in agentInsightTasks.values {
                task.cancel()
            }
            agentInsightTasks.removeAll()
            model.intelligenceConnectionState = .off
            model.runningAgentInsightIDs.removeAll()
        } else if oldSettings.intelligence != settings.intelligence {
            intelligenceTestTask?.cancel()
            intelligenceTestTask = nil
            model.intelligenceConnectionState = .unknown
        }

        if oldSettings.refreshIntervalSeconds != settings.refreshIntervalSeconds {
            scheduleRefreshLoop()
        }

        if oldSettings.monitorConfiguration != settings.monitorConfiguration {
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await monitor.update(configuration: settings.monitorConfiguration)
                refresh()
            }
        }
    }

    func openCodexFolder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [settings.monitorConfiguration.codexHome.path]
        try? process.run()
    }

    func flushScanCache() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await monitor.flushCache()
            refresh()
        }
    }

    func testIntelligenceConnection() {
        guard settings.intelligence.enabled,
              settings.intelligence.provider != .off
        else {
            model.intelligenceConnectionState = .off
            return
        }

        model.intelligenceConnectionState = .testing
        let intelligence = settings.intelligence
        intelligenceTestTask?.cancel()
        intelligenceTestTask = Task(priority: .utility) { [weak self] in
            let result = await Self.runIntelligenceConnectionTest(settings: intelligence)
            guard Task.isCancelled == false else {
                return
            }
            self?.intelligenceTestTask = nil
            self?.model.intelligenceConnectionState = result
        }
    }

    func requestAgentInsight(_ insight: ModexInsight) {
        guard settings.intelligence.enabled,
              settings.intelligence.provider != .off,
              let summary = latestSummary
        else {
            model.intelligenceConnectionState = settings.intelligence.enabled ? .unknown : .off
            return
        }

        let baseInsight = model.insights.first { $0.id == insight.id } ?? insight
        let request = agentEvidenceBuilder.request(
            for: baseInsight,
            summary: summary,
            history: model.history,
            includeCommandNames: true
        )

        agentInsightTasks[baseInsight.id]?.cancel()
        model.agentInsightErrors[baseInsight.id] = nil
        model.runningAgentInsightIDs.insert(baseInsight.id)

        let settings = settings.intelligence
        let historyStore = historyStore
        agentInsightTasks[baseInsight.id] = Task.detached(priority: .utility) { [weak self] in
            do {
                let result = try await Self.runAgentInsight(request: request, settings: settings)
                guard Task.isCancelled == false else {
                    return
                }
                try? historyStore?.save(agentInsight: result)
                await MainActor.run {
                    self?.agentInsightTasks[baseInsight.id] = nil
                    self?.model.runningAgentInsightIDs.remove(baseInsight.id)
                    self?.model.agentInsightErrors[baseInsight.id] = nil
                    self?.model.agentInsightResults[baseInsight.id] = result
                    self?.model.intelligenceConnectionState = .connected(result.generatedAt)
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self?.agentInsightTasks[baseInsight.id] = nil
                    self?.model.runningAgentInsightIDs.remove(baseInsight.id)
                    let message = Self.intelligenceErrorMessage(error)
                    self?.model.agentInsightErrors[baseInsight.id] = message
                    self?.model.intelligenceConnectionState = .failed(message)
                }
            }
        }
    }

    func flushAgentInsightCache() {
        try? historyStore?.deleteAgentInsightResults()
        model.agentInsightResults.removeAll()
        model.agentInsightErrors.removeAll()
    }

    func quit() {
        refreshTask?.cancel()
        refreshLoopTask?.cancel()
        Darwin.exit(0)
    }

    private func scheduleRefreshLoop() {
        refreshLoopTask?.cancel()

        let interval = settings.refreshIntervalSeconds
        refreshLoopTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(for: interval))
                } catch {
                    return
                }

                guard Task.isCancelled == false else {
                    return
                }
                self?.refresh()
            }
        }
    }

    private func finishRefresh(_ result: ModexRefreshResult) {
        refreshTask = nil
        model.isRefreshing = false

        switch result {
        case .success(let summary):
            latestSummary = summary
            model.readFailureMessage = nil
            model.summary = summary
            model.insights = signalEngine.insights(
                for: summary,
                history: model.history,
                thresholds: settings.signalThresholds
            )
            updateHistory(for: summary)
        case .failure(let message):
            model.readFailureMessage = message
            if latestSummary == nil {
                model.summary = nil
            }
        }
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(1, interval) * 1_000_000_000)
    }

    nonisolated private static func runIntelligenceConnectionTest(
        settings: ModexIntelligenceSettings
    ) async -> ModexIntelligenceConnectionState {
        switch settings.provider {
        case .off:
            return .off
        case .localCodex:
            do {
                let service = LocalCodexAgentInsightService(
                    configuration: settings.localCodexConfiguration
                )
                let result = try await service.testConnection()
                return .connected(result.generatedAt)
            } catch {
                return .failed(intelligenceErrorMessage(error))
            }
        }
    }

    nonisolated private static func runAgentInsight(
        request: ModexAgentInsightRequest,
        settings: ModexIntelligenceSettings
    ) async throws -> ModexAgentInsightResult {
        switch settings.provider {
        case .off:
            throw ModexAgentInsightServiceError.codexUnavailable("off")
        case .localCodex:
            let service = LocalCodexAgentInsightService(
                configuration: settings.localCodexConfiguration
            )
            return try await service.analyze(request: request)
        }
    }

    nonisolated private static func intelligenceErrorMessage(_ error: Error) -> String {
        guard let error = error as? ModexAgentInsightServiceError else {
            return String(describing: error)
        }

        switch error {
        case .codexUnavailable(let path):
            return ModexStrings.format("config.intelligenceErrorUnavailable", path)
        case .timedOut(let seconds):
            return ModexStrings.format("config.intelligenceErrorTimedOut", seconds)
        case .processFailed(let status, let detail):
            if detail.isEmpty {
                return ModexStrings.format("config.intelligenceErrorProcess", status)
            }
            return ModexStrings.format("config.intelligenceErrorProcessDetail", status, detail)
        case .missingOutput:
            return ModexStrings.text("config.intelligenceErrorMissingOutput")
        case .invalidOutput(let detail):
            return ModexStrings.format("config.intelligenceErrorInvalidOutput", detail)
        }
    }

    private func updateHistory(for summary: ModexSummary) {
        historyTask?.cancel()
        guard let historyStore else {
            return
        }

        let thresholds = settings.signalThresholds
        historyTask = Task.detached(priority: .utility) { [historyStore] in
            do {
                try historyStore.record(summary: summary)
                let history = try historyStore.snapshot()
                let insights = ModexSignalEngine().insights(
                    for: summary,
                    history: history,
                    thresholds: thresholds
                )
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.model.history = history
                    self.model.insights = insights
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await MainActor.run {
                    self.model.insights = self.signalEngine.insights(
                        for: summary,
                        history: self.model.history,
                        thresholds: thresholds
                    )
                }
            }
        }
    }
}

private extension ModexAppSettings {
    var signalThresholds: ModexSignalThresholds {
        ModexSignalThresholds(
            yellowPercent: contextThresholds.yellowPercent,
            orangePercent: contextThresholds.orangePercent,
            redPercent: contextThresholds.redPercent
        )
    }
}
