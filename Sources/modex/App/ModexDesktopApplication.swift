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
                contextUsagePercent: model.summary?.contextUsagePercent,
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
        }
        .onDisappear {
            hoverTask?.cancel()
        }
        .fixedSize()
    }

    private var palette: ModexPalette {
        ModexTheme.palette(for: model.settings.colorTheme, colorScheme: colorScheme)
    }

    private var title: String {
        if model.summary == nil, model.readFailureMessage != nil {
            return "!"
        }
        guard let summary = model.summary else {
            return ""
        }
        if let percent = summary.contextUsagePercent {
            return "\(Int(percent.rounded()))%"
        }
        if summary.totalTokens > 0 {
            return summary.totalTokens.formatted(.number.notation(.compactName))
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
        let context = summary.contextUsagePercent
            .map { ModexStrings.format("app.context", Int($0.rounded())) }
            ?? ModexStrings.text("app.unknownContext")
        let base = ModexStrings.format(
            "app.tooltip",
            context,
            summary.medianTurnTokens.formatted(),
            summary.compactionEvents
        )
        if let status = rateLimitSummary(summary.latestRateLimits) {
            return "\(base)\n\(status)"
        }
        return base
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

    private func rateLimitSummary(_ rateLimits: CodexRateLimits?) -> String? {
        guard let rateLimits,
              rateLimits.primary != nil || rateLimits.secondary != nil
        else {
            return nil
        }

        let values = [
            rateLimits.primary.map {
                "\(rateLimitShortLabel($0, fallbackKey: "column.primaryLimit.title")) \(percentLeft($0.leftPercent))"
            },
            rateLimits.secondary.map {
                "\(rateLimitShortLabel($0, fallbackKey: "column.secondaryLimit.title")) \(percentLeft($0.leftPercent))"
            },
        ]
        .compactMap(\.self)
        return values.joined(separator: "  ")
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
                    contextUsagePercent: model.summary?.contextUsagePercent,
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
                    valueRow(
                        ModexStrings.text("column.context.title"),
                        contextLeftValue(summary)
                    )
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

    private func contextLeftValue(_ summary: ModexSummary) -> String {
        guard let percent = summary.contextLeftPercent else {
            return ModexStrings.text("app.unknownContext")
        }

        if let usedTokens = summary.latestSession?.contextUsedTokens,
           let contextWindow = summary.latestSession?.contextWindow
        {
            return ModexStrings.format(
                "app.contextLeftDetailed",
                Int(percent.rounded()),
                usedTokens.formatted(),
                contextWindow.formatted()
            )
        }

        return ModexStrings.format("app.percentLeft", Int(percent.rounded()))
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
