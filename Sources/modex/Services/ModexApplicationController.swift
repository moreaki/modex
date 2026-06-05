import Darwin
import Foundation
import ModexCore

@MainActor
final class ModexApplicationController: ObservableObject {
    let model: ModexMenuModel

    private let settingsStore: ModexSettingsStore
    private let monitor: ModexMonitor
    private var settings: ModexAppSettings
    private var latestSummary: ModexSummary?
    private var refreshTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?
    private var hasStarted = false

    init() {
        let settingsStore = ModexSettingsStore()
        let settings = settingsStore.load()
        self.settingsStore = settingsStore
        self.settings = settings
        monitor = ModexMonitor(configuration: settings.monitorConfiguration)
        model = ModexMenuModel(settings: settings)
    }

    deinit {
        refreshTask?.cancel()
        refreshLoopTask?.cancel()
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
}
