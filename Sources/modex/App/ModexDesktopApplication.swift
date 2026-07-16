import ModexCore
import SwiftUI

@MainActor
struct ModexDesktopApplication: App {
    @StateObject private var controller = ModexApplicationController()

    var body: some Scene {
        MenuBarExtra {
            ModexMenuView(
                model: controller.model,
                onRefresh: controller.refresh,
                onOpenCodexFolder: controller.openCodexFolder,
                onFlushScanCache: controller.flushScanCache,
                onTestIntelligenceConnection: controller.testIntelligenceConnection,
                onRequestAgentInsight: controller.requestAgentInsight,
                onFlushAgentInsightCache: controller.flushAgentInsightCache,
                onSettingsChange: controller.apply,
                onQuit: controller.quit
            )
            .onAppear {
                controller.refresh()
            }
            .background(ModexWindowRegistrationView(target: .dashboard))
        } label: {
            ModexMenuBarLabel(model: controller.model)
                .task {
                    controller.start()
                }
        }
        .menuBarExtraStyle(.window)

        Window(ModexStrings.text("detail.title"), id: ModexWindowID.threadDetail) {
            ModexThreadDetailWindow(
                model: controller.model,
                onRequestAgentInsight: controller.requestAgentInsight
            )
            .background(ModexWindowRegistrationView(target: .threadDetail))
        }
        .defaultSize(width: 1120, height: 720)
    }
}

enum ModexWindowID {
    static let threadDetail = "thread-detail"
}

private struct ModexMenuBarLabel: View {
    @ObservedObject var model: ModexMenuModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingHoverCard = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Label {
            if title.isEmpty == false {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .help(tooltip)
                    .accessibilityLabel(Text(tooltip))
            }
        } icon: {
            ModexStatusIcon(
                remainingPercent: weeklyWindow?.leftPercent,
                warningUsagePercent: weeklyWindow?.usedPercent,
                thresholds: model.settings.contextThresholds
            )
            .frame(width: 18, height: 18)
            .help(tooltip)
            .accessibilityLabel(Text(tooltip))
        }
        .labelStyle(.titleAndIcon)
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
        .onHover(perform: handleHover)
        .popover(isPresented: $isShowingHoverCard, arrowEdge: .top) {
            ModexMenuBarHoverCard(model: model)
                .environment(\.modexPalette, palette)
                .environment(\.colorScheme, effectiveColorScheme)
        }
        .onDisappear {
            hoverTask?.cancel()
        }
        .fixedSize()
    }

    private var palette: ModexPalette {
        ModexTheme.palette(for: model.settings.colorTheme, colorScheme: colorScheme)
    }

    private var effectiveColorScheme: ColorScheme {
        model.settings.colorTheme == .black ? .dark : colorScheme
    }

    private var title: String {
        if model.summary == nil, model.readFailureMessage != nil {
            return "!"
        }
        guard let summary = model.summary else {
            return ""
        }
        if let percent = summary.latestRateLimits?.sevenDayWindow?.leftPercent {
            return "\(Int(percent.rounded()))%"
        }
        return ""
    }

    private var tooltip: String {
        if let readFailureMessage = model.readFailureMessage {
            return ModexStrings.format("app.readFailure", readFailureMessage)
        }
        guard let summary = model.summary else {
            return ModexStrings.text("overview.noMetrics")
        }
        let weeklyLimit = summary.latestRateLimits?.sevenDayWindow
            .map {
                "\(ModexStrings.text("column.secondaryLimit.title")) \(percentLeft($0.leftPercent))"
            }
            ?? "\(ModexStrings.text("column.secondaryLimit.helpTitle")) \(ModexStrings.text("overview.contextUnavailable"))"
        return ModexStrings.format(
            "app.tooltip",
            weeklyLimit,
            summary.medianTurnTokens.formatted(),
            summary.compactionEvents
        )
    }

    private var weeklyWindow: CodexRateLimitWindow? {
        model.summary?.latestRateLimits?.sevenDayWindow
    }

    private func handleHover(_ isHovering: Bool) {
        hoverTask?.cancel()

        if isHovering {
            hoverTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 450_000_000)
                } catch {
                    return
                }

                guard Task.isCancelled == false else {
                    return
                }
                isShowingHoverCard = true
            }
        } else {
            isShowingHoverCard = false
        }
    }

    private func percentLeft(_ percent: Double?) -> String {
        percent.map { ModexStrings.format("app.percentLeft", Int($0.rounded())) }
            ?? ModexStrings.text("overview.contextUnavailable")
    }
}

private struct ModexMenuBarHoverCard: View {
    @ObservedObject var model: ModexMenuModel
    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ModexStatusIcon(
                    remainingPercent: model.summary?.latestRateLimits?.sevenDayWindow?.leftPercent,
                    warningUsagePercent: model.summary?.latestRateLimits?.sevenDayWindow?.usedPercent,
                    thresholds: model.settings.contextThresholds
                )
                .frame(width: 18, height: 18)

                Text(ModexStrings.text("overview.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
            }

            if let readFailureMessage = model.readFailureMessage {
                Text(ModexStrings.format("app.readFailure", readFailureMessage))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let summary = model.summary {
                VStack(alignment: .leading, spacing: 6) {
                    if let primary = summary.latestRateLimits?.primary {
                        valueRow(
                            rateLimitShortLabel(primary, fallbackKey: "column.primaryLimit.title"),
                            limitValue(primary)
                        )
                    }
                    if let secondary = summary.latestRateLimits?.secondary {
                        valueRow(
                            rateLimitShortLabel(secondary, fallbackKey: "column.secondaryLimit.title"),
                            limitValue(secondary)
                        )
                    }
                    valueRow(
                        ModexStrings.text("column.median.title"),
                        summary.medianTurnTokens.formatted()
                    )
                    valueRow(
                        ModexStrings.text("column.compact.helpTitle"),
                        "\(summary.compactionEvents)"
                    )
                    if let metrics = summary.scanMetrics {
                        valueRow(
                            ModexStrings.text("instrumentation.read"),
                            readValue(metrics)
                        )
                    }
                }
            } else {
                Text(ModexStrings.text("overview.noMetrics"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(12)
        .frame(width: 245, alignment: .leading)
        .background(palette.background)
    }

    private func limitValue(_ window: CodexRateLimitWindow?) -> String {
        guard let window else {
            return ModexStrings.text("overview.contextUnavailable")
        }

        if let resetsAt = window.resetsAt {
            return ModexStrings.format(
                "app.percentLeftWithReset",
                Int(window.leftPercent.rounded()),
                Self.resetFormatter.string(from: resetsAt)
            )
        }
        return ModexStrings.format("app.percentLeft", Int(window.leftPercent.rounded()))
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.mutedText)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
    }

    private func readValue(_ metrics: ScanMetrics) -> String {
        let base = "\(formatDuration(metrics.durationSeconds))  \(formatBytes(metrics.bytesRead))"
        guard metrics.cacheEnabled, metrics.cacheHits > 0 else {
            return base
        }
        return ModexStrings.format("instrumentation.readWithCache", base, metrics.cacheHits)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private func rateLimitShortLabel(_ window: CodexRateLimitWindow, fallbackKey: String) -> String {
    switch window.windowMinutes {
    case 300:
        return ModexStrings.text("column.primaryLimit.title")
    case 10_080:
        return ModexStrings.text("column.secondaryLimit.title")
    default:
        return ModexStrings.text(fallbackKey)
    }
}
