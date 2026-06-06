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
    private var settings: ModexAppSettings
    private var latestSummary: ModexSummary?
    private var refreshTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var hasStarted = false

    init() {
        let settingsStore = ModexSettingsStore()
        let settings = settingsStore.load()
        self.settingsStore = settingsStore
        self.settings = settings
        monitor = ModexMonitor(configuration: settings.monitorConfiguration)
        historyStore = try? ModexHistoryStore(databaseURL: ModexHistoryStore.defaultDatabaseURL())
        model = ModexMenuModel(settings: settings)
    }

    deinit {
        refreshTask?.cancel()
        refreshLoopTask?.cancel()
        historyTask?.cancel()
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
            model.intelligenceConnectionState = .off
        } else if oldSettings.intelligence != settings.intelligence {
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
        let provider = settings.intelligence.provider
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.runIntelligenceConnectionTest(provider: provider)
            await MainActor.run {
                self?.model.intelligenceConnectionState = result
            }
        }
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
        provider: ModexIntelligenceProvider
    ) -> ModexIntelligenceConnectionState {
        switch provider {
        case .off:
            return .off
        case .localCodex:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return .limited("Codex CLI found, but no structured insight bridge is configured yet.")
                }
                return .failed("Codex CLI test failed.")
            } catch {
                return .failed("Codex CLI was not found on the app launch PATH.")
            }
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
                await MainActor.run {
                    self.model.history = history
                    self.model.insights = insights
                }
            } catch {
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
