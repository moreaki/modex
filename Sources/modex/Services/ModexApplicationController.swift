import Darwin
import Foundation
import ModexCore

@MainActor
final class ModexApplicationController: ObservableObject {
    let model: ModexMenuModel

    private let settingsStore: ModexSettingsStore
    private let intelligenceConnectionStore: ModexIntelligenceConnectionStore
    private let monitor: ModexMonitor
    private let historyStore: ModexHistoryStore?
    private let signalEngine = ModexSignalEngine()
    private let agentEvidenceBuilder = ModexAgentInsightEvidenceBuilder()
    private var settings: ModexAppSettings
    private var latestSummary: ModexSummary?
    private var latestSummaryConfiguration: ModexMonitorConfiguration?
    private var refreshTask: Task<Void, Never>?
    private var refreshRequestedAfterCurrent = false
    private var refreshLoopTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var intelligenceTestTask: Task<Void, Never>?
    private var intelligenceExecutableTask: Task<Void, Never>?
    private var intelligenceCapabilityTask: Task<Void, Never>?
    private var agentInsightTasks: [String: Task<Void, Never>] = [:]
    private var hasStarted = false

    init() {
        ModexStartupMigrationCatalog.run()
        let settingsStore = ModexSettingsStore()
        let settings = settingsStore.load()
        let intelligenceConnectionStore = ModexIntelligenceConnectionStore()
        let historyStore = try? ModexHistoryStore(databaseURL: ModexHistoryStore.defaultDatabaseURL())
        self.settingsStore = settingsStore
        self.intelligenceConnectionStore = intelligenceConnectionStore
        self.settings = settings
        monitor = ModexMonitor(configuration: settings.monitorConfiguration)
        self.historyStore = historyStore
        model = ModexMenuModel(
            settings: settings,
            intelligenceConnectionState: intelligenceConnectionStore.state(for: settings.intelligence)
        )
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
        intelligenceExecutableTask?.cancel()
        intelligenceCapabilityTask?.cancel()
        for task in agentInsightTasks.values {
            task.cancel()
        }
    }

    func start() {
        guard hasStarted == false else {
            return
        }
        hasStarted = true
        discoverIntelligenceExecutables()
        refresh()
        scheduleRefreshLoop()
    }

    func refresh() {
        guard refreshTask == nil else {
            return
        }

        let configuration = settings.monitorConfiguration
        model.isRefreshing = true
        refreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let result = await monitor.refresh { [weak self] summary in
                await self?.receiveRefreshProgress(summary, configuration: configuration)
            }
            finishRefresh(result, configuration: configuration)
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
            model.intelligenceConnectionState = intelligenceConnectionStore.state(
                for: settings.intelligence
            )
        }

        if oldSettings.intelligence.codexExecutablePath != settings.intelligence.codexExecutablePath {
            if model.intelligenceExecutables.contains(where: {
                $0.path == settings.intelligence.codexExecutablePath
            }) {
                discoverIntelligenceCapabilities(after: .milliseconds(150))
            } else {
                discoverIntelligenceExecutables(after: .milliseconds(350))
            }
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
                requestRefreshAfterCurrent()
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
            requestRefreshAfterCurrent()
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
            guard let self, self.settings.intelligence == intelligence else {
                return
            }
            intelligenceTestTask = nil
            updateIntelligenceConnection(result, for: intelligence)
        }
    }

    private func discoverIntelligenceExecutables(after delay: Duration = .zero) {
        intelligenceExecutableTask?.cancel()
        let configuredPath = settings.intelligence.codexExecutablePath
        model.isDiscoveringIntelligenceExecutables = true

        intelligenceExecutableTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else {
                return
            }
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }

            let discovery = await LocalCodexExecutableDiscoveryService(
                configuredPath: configuredPath
            ).discover()
            guard Task.isCancelled == false,
                  settings.intelligence.codexExecutablePath == configuredPath
            else {
                return
            }

            model.intelligenceExecutables = discovery.executables
            model.isDiscoveringIntelligenceExecutables = false
            intelligenceExecutableTask = nil

            if configuredPath.contains("/") == false,
               let resolvedPath = discovery.resolvedConfiguredPath,
               resolvedPath != configuredPath
            {
                let previousConnectionState = model.intelligenceConnectionState
                var updatedSettings = settings
                updatedSettings.intelligence.codexExecutablePath = resolvedPath
                apply(settings: updatedSettings)
                if case .connected(let verifiedAt) = previousConnectionState {
                    intelligenceConnectionStore.recordConnected(
                        at: verifiedAt,
                        for: settings.intelligence
                    )
                    model.intelligenceConnectionState = .connected(verifiedAt)
                }
            } else {
                discoverIntelligenceCapabilities()
            }
        }
    }

    private func discoverIntelligenceCapabilities(after delay: Duration = .zero) {
        intelligenceCapabilityTask?.cancel()
        let executablePath = settings.intelligence.codexExecutablePath
        model.isDiscoveringIntelligenceCapabilities = true
        model.intelligenceCapabilityError = nil

        intelligenceCapabilityTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else {
                return
            }
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }

            do {
                let capabilities = try await LocalCodexCapabilityDiscoveryService(
                    executablePath: executablePath
                ).discover()
                guard Task.isCancelled == false,
                      settings.intelligence.codexExecutablePath == executablePath
                else {
                    return
                }

                model.intelligenceCapabilities = capabilities
                model.isDiscoveringIntelligenceCapabilities = false
                model.intelligenceCapabilityError = nil
                intelligenceCapabilityTask = nil

                let normalized = settings.intelligence.normalized(using: capabilities)
                if normalized != settings.intelligence {
                    var updatedSettings = settings
                    updatedSettings.intelligence = normalized
                    apply(settings: updatedSettings)
                }
            } catch {
                guard Task.isCancelled == false,
                      settings.intelligence.codexExecutablePath == executablePath
                else {
                    return
                }
                let message = Self.intelligenceCapabilityErrorMessage(error)
                model.intelligenceCapabilities = nil
                model.isDiscoveringIntelligenceCapabilities = false
                model.intelligenceCapabilityError = message
                intelligenceCapabilityTask = nil
                if settings.intelligence.enabled {
                    model.intelligenceConnectionState = .limited(message)
                }
            }
        }
    }

    func requestAgentInsight(_ insight: ModexInsight) {
        guard settings.intelligence.enabled,
              settings.intelligence.provider != .off,
              let summary = latestSummary
        else {
            model.intelligenceConnectionState = intelligenceConnectionStore.state(
                for: settings.intelligence
            )
            return
        }

        let baseInsight = model.insights.first { $0.id == insight.id } ?? insight
        startAgentInsight(baseInsight, summary: summary, retryIfChanged: true)
    }

    private func startAgentInsight(
        _ baseInsight: ModexInsight,
        summary: ModexSummary,
        retryIfChanged: Bool
    ) {
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
                    guard let self else {
                        return
                    }
                    self.agentInsightTasks[baseInsight.id] = nil
                    self.model.agentInsightErrors[baseInsight.id] = nil
                    self.model.agentInsightResults[baseInsight.id] = result
                    if self.settings.intelligence == settings {
                        self.intelligenceConnectionStore.recordConnected(
                            at: result.generatedAt,
                            for: settings
                        )
                        self.model.intelligenceConnectionState = .connected(result.generatedAt)
                    }

                    if retryIfChanged,
                       let currentInsight = self.model.insights.first(where: { $0.id == baseInsight.id }),
                       currentInsight.agentFingerprint != result.sourceFingerprint,
                       let latestSummary = self.latestSummary
                    {
                        self.startAgentInsight(
                            currentInsight,
                            summary: latestSummary,
                            retryIfChanged: false
                        )
                        return
                    }

                    self.model.runningAgentInsightIDs.remove(baseInsight.id)
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
                    if let self, self.settings.intelligence == settings {
                        self.intelligenceConnectionStore.invalidate(for: settings)
                        self.model.intelligenceConnectionState = .failed(message)
                    }
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

    private func finishRefresh(
        _ result: ModexRefreshResult,
        configuration: ModexMonitorConfiguration
    ) {
        refreshTask = nil

        if configuration == settings.monitorConfiguration {
            switch result {
            case .success(let summary):
                latestSummary = summary
                latestSummaryConfiguration = configuration
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

        if refreshRequestedAfterCurrent {
            refreshRequestedAfterCurrent = false
            refresh()
        } else {
            model.isRefreshing = false
        }
    }

    private func receiveRefreshProgress(
        _ summary: ModexSummary,
        configuration: ModexMonitorConfiguration
    ) {
        guard configuration == settings.monitorConfiguration else {
            return
        }
        model.readFailureMessage = nil
        model.summary = mergedProgressSummary(summary, configuration: configuration)
    }

    private func mergedProgressSummary(
        _ progress: ModexSummary,
        configuration: ModexMonitorConfiguration
    ) -> ModexSummary {
        guard latestSummaryConfiguration == configuration,
              let latestSummary,
              let metrics = progress.scanMetrics,
              metrics.filesParsed < metrics.filesSelected
        else {
            return progress
        }

        var sessionsByPath = Dictionary(
            uniqueKeysWithValues: latestSummary.sessions.map { ($0.fileURL.path, $0) }
        )
        for session in progress.sessions {
            sessionsByPath[session.fileURL.path] = session
        }
        return ModexSummary(
            sessions: Array(sessionsByPath.values),
            scanMetrics: metrics
        )
    }

    private func requestRefreshAfterCurrent() {
        if refreshTask == nil {
            refresh()
        } else {
            refreshRequestedAfterCurrent = true
        }
    }

    private func updateIntelligenceConnection(
        _ state: ModexIntelligenceConnectionState,
        for settings: ModexIntelligenceSettings
    ) {
        switch state {
        case .connected(let date):
            intelligenceConnectionStore.recordConnected(at: date, for: settings)
        case .limited, .failed:
            intelligenceConnectionStore.invalidate(for: settings)
        case .off, .unknown, .testing:
            break
        }
        model.intelligenceConnectionState = state
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

    nonisolated private static func intelligenceCapabilityErrorMessage(_ error: Error) -> String {
        guard let error = error as? LocalCodexCapabilityDiscoveryError else {
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
        case .malformedResponse:
            return ModexStrings.text("config.intelligenceCapabilitiesMalformed")
        case .noModels:
            return ModexStrings.text("config.intelligenceCapabilitiesEmpty")
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
