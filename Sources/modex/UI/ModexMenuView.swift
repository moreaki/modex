import ModexCore
import SwiftUI

struct ModexMenuView: View {
    @ObservedObject var model: ModexMenuModel
    let onRefresh: () -> Void
    let onOpenCodexFolder: () -> Void
    let onFlushScanCache: () -> Void
    let onSettingsChange: (ModexAppSettings) -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingInstrumentation = false
    @State private var showingConfiguration = false
    @State private var footerHint: String?

    var body: some View {
        VStack(spacing: 10) {
            header
            if let latestRateLimits = model.summary?.latestRateLimits {
                CodexRateLimitOverview(rateLimits: latestRateLimits)
            }
            sessionTable
            footer
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(width: 900, height: 430)
        .background(palette.background)
        .foregroundStyle(palette.text)
        .environment(\.modexPalette, palette)
    }

    private var palette: ModexPalette {
        ModexTheme.palette(for: model.settings.colorTheme, colorScheme: colorScheme)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ModexStrings.text("overview.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(summaryText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(statusText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
    }

    private var sessionTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(OverviewColumn.allCases) { column in
                    ColumnHeader(column: column)
                        .frame(width: column.width, alignment: column.alignment)
                }
            }
            .frame(height: 32)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.surface)
                    .frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessionGroups) { group in
                        ProjectGroupHeader(title: group.title)
                        ForEach(group.sessions) { indexedSession in
                            SessionRow(
                                session: indexedSession.session,
                                index: indexedSession.index,
                                thresholds: model.settings.contextThresholds,
                                sessionDetailHoverDelayMilliseconds: model.settings.sessionDetailHoverDelayMilliseconds
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .background(palette.sidebar.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sessionGroups: [SessionGroup] {
        groupedSessions(model.summary?.sessions ?? [])
    }

    private var footer: some View {
        HStack(spacing: 8) {
            IconButton(
                symbol: "arrow.clockwise",
                label: ModexStrings.text("overview.refresh"),
                onHoverLabel: setFooterHint,
                action: onRefresh
            )

            IconButton(
                symbol: "stopwatch",
                label: ModexStrings.text("overview.showLastReadTimings"),
                isEnabled: model.latestMetrics != nil,
                onHoverLabel: setFooterHint
            ) {
                showingInstrumentation.toggle()
            }
            .popover(isPresented: $showingInstrumentation, arrowEdge: .bottom) {
                InstrumentationView(metrics: model.latestMetrics)
            }

            IconButton(
                symbol: "gearshape",
                label: ModexStrings.text("overview.configuration"),
                onHoverLabel: setFooterHint
            ) {
                showingConfiguration.toggle()
            }
            .popover(isPresented: $showingConfiguration, arrowEdge: .bottom) {
                ConfigurationView(
                    settings: Binding(
                        get: { model.settings },
                        set: { onSettingsChange($0) }
                    ),
                    onOpenCodexFolder: onOpenCodexFolder,
                    onFlushScanCache: onFlushScanCache
                )
            }

            Text(footerHint ?? "")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
                .animation(.easeInOut(duration: 0.12), value: footerHint)

            Spacer()

            IconButton(
                symbol: "power",
                label: ModexStrings.text("overview.quit"),
                onHoverLabel: setFooterHint,
                action: onQuit
            )
        }
    }

    private func setFooterHint(_ label: String?) {
        footerHint = label
    }

    private var summaryText: String {
        guard let summary = model.summary else {
            return ModexStrings.text("overview.noMetrics")
        }

        var parts = [
            ModexStrings.format("overview.sessions", summary.sessionsScanned),
            ModexStrings.format("overview.tokens", compact(summary.totalTokens)),
            ModexStrings.format("overview.compactions", summary.compactionEvents),
        ]
        if let metrics = summary.scanMetrics {
            parts.append(ModexStrings.format("overview.scanDuration", formatDuration(metrics.durationSeconds)))
        }
        return parts.joined(separator: "  ")
    }

    private var statusText: String {
        if model.isRefreshing {
            let lastReadStatus = model.lastReadStatus
            return lastReadStatus.isEmpty
                ? ModexStrings.text("overview.refreshing")
                : ModexStrings.format("overview.refreshingWithStatus", lastReadStatus)
        }

        return model.lastReadStatus
    }

}

private struct CodexRateLimitOverview: View {
    let rateLimits: CodexRateLimits
    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(spacing: 6) {
            CodexRateLimitRow(
                label: ModexStrings.text("overview.primaryLimitTitle"),
                window: rateLimits.primary
            )
            CodexRateLimitRow(
                label: ModexStrings.text("overview.secondaryLimitTitle"),
                window: rateLimits.secondary
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(palette.sidebar.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CodexRateLimitRow: View {
    let label: String
    let window: CodexRateLimitWindow?
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 80, alignment: .leading)

            CodexRateLimitBar(percentLeft: window?.leftPercent)
                .frame(height: 14)

            Text(statusText)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .frame(width: 210, alignment: .leading)
                .lineLimit(1)
        }
        .accessibilityLabel(Text("\(label) \(statusText)"))
    }

    private var statusText: String {
        guard let window else {
            return ModexStrings.text("overview.contextUnavailable")
        }

        let percent = Int(window.leftPercent.rounded())
        if let resetsAt = window.resetsAt {
            return ModexStrings.format(
                "overview.limitLeftResetCompact",
                percent,
                Self.resetText(for: resetsAt)
            )
        }
        return ModexStrings.format("overview.limitLeft", percent)
    }

    private static func resetText(for date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.autoupdatingCurrent.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        }
        return formatter.string(from: date)
    }
}

private struct CodexRateLimitBar: View {
    let percentLeft: Double?
    @Environment(\.modexPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let clampedPercent = min(max(percentLeft ?? 0, 0), 100)
            let fillWidth = proxy.size.width * clampedPercent / 100
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.surface.opacity(0.48))

                Rectangle()
                    .fill(palette.text.opacity(percentLeft == nil ? 0.16 : 0.9))
                    .frame(width: max(percentLeft == nil ? 0 : 2, fillWidth))

                CodexRateLimitRemainderPattern()
                    .fill(palette.text.opacity(0.55))
                    .frame(width: max(0, proxy.size.width - fillWidth))
                    .offset(x: fillWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

private struct CodexRateLimitRemainderPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 5
        let dotSize: CGFloat = 2.1
        var x = rect.minX + 1
        while x < rect.maxX {
            var y = rect.minY + 1
            while y < rect.maxY {
                path.addEllipse(in: CGRect(x: x, y: y, width: dotSize, height: dotSize))
                y += step
            }
            x += step
        }
        return path
    }
}

private enum OverviewColumn: String, CaseIterable, Identifiable {
    case session
    case mode
    case context
    case total
    case median
    case average
    case compact
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session:
            return ModexStrings.text("column.session.title")
        case .mode:
            return ModexStrings.text("column.mode.title")
        case .context:
            return ModexStrings.text("column.context.title")
        case .total:
            return ModexStrings.text("column.total.title")
        case .median:
            return ModexStrings.text("column.median.title")
        case .average:
            return ModexStrings.text("column.average.title")
        case .compact:
            return ModexStrings.text("column.compact.title")
        case .updated:
            return ModexStrings.text("column.updated.title")
        }
    }

    var width: CGFloat {
        switch self {
        case .session:
            return 260
        case .mode:
            return 124
        case .context:
            return 104
        case .total:
            return 70
        case .median:
            return 76
        case .average:
            return 66
        case .compact:
            return 62
        case .updated:
            return 76
        }
    }

    var alignment: Alignment {
        switch self {
        case .session, .mode:
            return .leading
        default:
            return .trailing
        }
    }

    var help: ColumnHelp {
        switch self {
        case .session:
            return ColumnHelp(
                icon: "rectangle.stack",
                title: ModexStrings.text("column.session.title"),
                body: ModexStrings.text("column.session.body"),
                detail: ModexStrings.text("column.session.detail")
            )
        case .mode:
            return ColumnHelp(
                icon: "speedometer",
                title: ModexStrings.text("column.mode.title"),
                body: ModexStrings.text("column.mode.body"),
                detail: ModexStrings.text("column.mode.detail")
            )
        case .context:
            return ColumnHelp(
                icon: "gauge.medium",
                title: ModexStrings.text("column.context.title"),
                body: ModexStrings.text("column.context.body"),
                detail: ModexStrings.text("column.context.detail")
            )
        case .total:
            return ColumnHelp(
                icon: "sum",
                title: ModexStrings.text("column.total.title"),
                body: ModexStrings.text("column.total.body"),
                detail: ModexStrings.text("column.total.detail")
            )
        case .median:
            return ColumnHelp(
                icon: "chart.bar.xaxis",
                title: ModexStrings.text("column.median.title"),
                body: ModexStrings.text("column.median.body"),
                detail: ModexStrings.text("column.median.detail")
            )
        case .average:
            return ColumnHelp(
                icon: "chart.xyaxis.line",
                title: ModexStrings.text("column.average.title"),
                body: ModexStrings.text("column.average.body"),
                detail: ModexStrings.text("column.average.detail")
            )
        case .compact:
            return ColumnHelp(
                icon: "arrow.down.forward.and.arrow.up.backward",
                title: ModexStrings.text("column.compact.helpTitle"),
                body: ModexStrings.text("column.compact.body"),
                detail: ModexStrings.text("column.compact.detail")
            )
        case .updated:
            return ColumnHelp(
                icon: "clock",
                title: ModexStrings.text("column.updated.title"),
                body: ModexStrings.text("column.updated.body"),
                detail: ModexStrings.text("column.updated.detail")
            )
        }
    }
}

private struct ColumnHelp {
    let icon: String
    let title: String
    let body: String
    let detail: String
}

private struct IndexedSession: Identifiable {
    let index: Int
    let session: SessionSnapshot

    var id: URL {
        session.fileURL
    }
}

private struct SessionGroup: Identifiable {
    let id: String
    let title: String
    let sessions: [IndexedSession]
}

private struct SessionGroupBuilder {
    let id: String
    let title: String
    var sessions: [IndexedSession]
}

private struct ProjectGroupHeader: View {
    let title: String
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(palette.sidebar.opacity(0.92))
    }
}

private struct ColumnHeader: View {
    let column: OverviewColumn
    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Text(column.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isHovered ? palette.accent : palette.secondaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: column.alignment)
            .padding(.horizontal, 6)
            .background(isHovered ? palette.surfaceHighlight : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(isPresented: $isHovered, arrowEdge: .top) {
                ColumnHelpCard(help: column.help)
            }
    }
}

private struct ColumnHelpCard: View {
    let help: ColumnHelp
    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: help.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 20)
                Text(help.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
            }

            Text(help.body)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(help.detail)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(palette.sidebar)
    }
}

private struct SessionRow: View {
    let session: SessionSnapshot
    let index: Int
    let thresholds: ModexContextThresholds
    let sessionDetailHoverDelayMilliseconds: Int
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            sessionCell
                .frame(width: OverviewColumn.session.width, alignment: .leading)
            ModeCell(session: session)
                .frame(width: OverviewColumn.mode.width, alignment: .leading)
            ContextMeter(
                percent: session.contextUsagePercent,
                thresholds: thresholds,
                accessibilityLabel: contextStatusText
            )
                .frame(width: OverviewColumn.context.width, alignment: .trailing)
            numberCell(
                compact(session.totalTokens),
                exactValue: exactTotalTokensValue,
                accessibilityLabel: exactTotalTokensText
            )
                .frame(width: OverviewColumn.total.width, alignment: .trailing)
            numberCell(
                compact(session.medianTurnTokens),
                exactValue: exactMedianTurnTokensValue,
                accessibilityLabel: exactMedianTurnTokensText
            )
                .frame(width: OverviewColumn.median.width, alignment: .trailing)
            numberCell(
                compact(session.averageTurnTokens),
                exactValue: exactAverageTurnTokensValue,
                accessibilityLabel: exactAverageTurnTokensText
            )
                .frame(width: OverviewColumn.average.width, alignment: .trailing)
            numberCell("\(session.compactionEvents)")
                .frame(width: OverviewColumn.compact.width, alignment: .trailing)
            UpdatedCell(updatedAt: session.updatedAt)
                .frame(width: OverviewColumn.updated.width, alignment: .trailing)
        }
        .frame(height: 40)
        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.035) : Color.white.opacity(0.015))
    }

    private var sessionCell: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(sessionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Text(sessionSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .sessionDetailTip(
            sessionTooltip,
            delayMilliseconds: sessionDetailHoverDelayMilliseconds
        )
        .accessibilityLabel(Text(sessionTooltip))
    }

    @ViewBuilder
    private func numberCell(_ value: String, exactValue: String? = nil, accessibilityLabel: String? = nil) -> some View {
        if let exactValue {
            ExactNumberCell(
                value: value,
                exactValue: exactValue,
                accessibilityLabel: accessibilityLabel ?? exactValue
            )
        } else {
            numberText(value)
        }
    }

    private func numberText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 6)
    }

    private var exactTotalTokensText: String {
        "\(ModexStrings.text("column.total.title")): \(session.totalTokens.formatted())"
    }

    private var exactTotalTokensValue: String {
        session.totalTokens.formatted()
    }

    private var exactMedianTurnTokensText: String {
        "\(ModexStrings.text("column.median.title")): \(session.medianTurnTokens.formatted())"
    }

    private var exactMedianTurnTokensValue: String {
        session.medianTurnTokens.formatted()
    }

    private var exactAverageTurnTokensText: String {
        "\(ModexStrings.text("column.average.title")): \(session.averageTurnTokens.formatted())"
    }

    private var exactAverageTurnTokensValue: String {
        session.averageTurnTokens.formatted()
    }

    private var sessionTitle: String {
        if let threadName = session.threadName, threadName.isEmpty == false {
            return threadName
        }
        return projectTitle(for: session)
    }

    private var sessionSubtitle: String {
        if let sessionID = session.sessionID {
            return ModexStrings.format("overview.sessionLabel", String(sessionID.prefix(8)))
        }

        let fileName = session.fileURL.deletingPathExtension().lastPathComponent
        if fileName.hasPrefix("rollout-") {
            return String(fileName.dropFirst("rollout-".count))
        }
        return fileName.isEmpty ? ModexStrings.text("overview.unknownSession") : fileName
    }

    private var sessionTooltip: String {
        var rows: [String] = []
        if let threadName = session.threadName, threadName.isEmpty == false {
            rows.append(ModexStrings.format("overview.threadLabel", threadName))
        }
        if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
            rows.append(ModexStrings.format("overview.projectLabel", workingDirectory))
        }
        if let sessionID = session.sessionID {
            rows.append(ModexStrings.format("overview.sessionTooltipLabel", sessionID))
        }
        rows.append(ModexStrings.format("overview.modelLabel", modeValue(session.model)))
        rows.append(ModexStrings.format("overview.reasoningLabel", modeValue(session.reasoningEffort)))
        rows.append(ModexStrings.format("overview.speedLabel", speedText(for: session.realtimeActive)))
        rows.append(ModexStrings.format("overview.summaryModeLabel", modeValue(session.summaryMode)))
        rows.append(contextStatusText)
        rows.append(ModexStrings.format("overview.medianLabel", compact(session.medianTurnTokens)))
        rows.append(ModexStrings.format("overview.averageLabel", compact(session.averageTurnTokens)))
        rows.append(ModexStrings.format("overview.fileLabel", session.fileURL.path))
        return rows.joined(separator: "\n")
    }

    private var contextStatusText: String {
        guard let percent = session.contextUsagePercent,
              let usedTokens = session.contextUsedTokens,
              let contextWindow = session.contextWindow
        else {
            return ModexStrings.text("app.unknownContext")
        }

        return ModexStrings.format(
            "overview.contextUsageDetail",
            Int(percent.rounded()),
            usedTokens.formatted(),
            contextWindow.formatted()
        )
    }
}

private struct ModeCell: View {
    let session: SessionSnapshot

    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(modeValue(session.model))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(session.model == nil ? palette.mutedText : palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(detailText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel(Text(tooltip))
    }

    private var detailText: String {
        "\(modeValue(session.reasoningEffort)) · \(speedText(for: session.realtimeActive))"
    }

    private var tooltip: String {
        [
            ModexStrings.format("overview.modelLabel", modeValue(session.model)),
            ModexStrings.format("overview.reasoningLabel", modeValue(session.reasoningEffort)),
            ModexStrings.format("overview.speedLabel", speedText(for: session.realtimeActive)),
            ModexStrings.format("overview.summaryModeLabel", modeValue(session.summaryMode)),
        ]
        .joined(separator: "\n")
    }
}

private func modeValue(_ value: String?) -> String {
    guard let value, value.isEmpty == false else {
        return ModexStrings.text("overview.contextUnavailable")
    }
    return value
}

private func speedText(for realtimeActive: Bool?) -> String {
    guard let realtimeActive else {
        return ModexStrings.text("overview.contextUnavailable")
    }
    return realtimeActive
        ? ModexStrings.text("overview.speedRealtime")
        : ModexStrings.text("overview.speedStandard")
}

private struct ExactNumberCell: View {
    let value: String
    let exactValue: String
    let accessibilityLabel: String

    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(isHovered ? 0 : 1)
                .scaleEffect(isHovered ? 0.96 : 1, anchor: .trailing)

            Text(exactValue)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.96, anchor: .trailing)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .zIndex(isHovered ? 2 : 0)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct UpdatedCell: View {
    let updatedAt: Date?

    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let yearDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d y")
        return formatter
    }()

    private static let exactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(displayText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .opacity(isHovered && updatedAt != nil ? 0 : 1)

            if isHovered, let updatedAt {
                Text(Self.exactText(for: updatedAt))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(palette.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.surface.opacity(0.85), lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .trailing)))
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(Text(accessibilityText))
    }

    private var displayText: String {
        guard let updatedAt else {
            return ""
        }

        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        if calendar.isDateInToday(updatedAt) {
            return Self.timeFormatter.string(from: updatedAt)
        }

        let age = now.timeIntervalSince(updatedAt)
        if age >= 0, age < 7 * 24 * 60 * 60 {
            return Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: now)
        }

        if calendar.component(.year, from: updatedAt) == calendar.component(.year, from: now) {
            return Self.shortDateFormatter.string(from: updatedAt)
        }
        return Self.yearDateFormatter.string(from: updatedAt)
    }

    private var accessibilityText: String {
        guard let updatedAt else {
            return ModexStrings.text("column.updated.title")
        }
        return ModexStrings.format("overview.updated", Self.exactText(for: updatedAt))
    }

    private static func exactText(for date: Date) -> String {
        exactFormatter.string(from: date)
    }
}

private struct ContextMeter: View {
    let percent: Double?
    let thresholds: ModexContextThresholds
    let accessibilityLabel: String
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.surface.opacity(0.32))
                    if let percent {
                        Capsule()
                            .fill(ModexTheme.contextColor(for: percent, thresholds: thresholds).opacity(0.90))
                            .frame(width: max(3, proxy.size.width * min(max(percent, 0), 100) / 100))
                    }
                }
            }
            .frame(width: 36, height: 6)

            Text(percent.map { "\(Int($0.rounded()))%" } ?? ModexStrings.text("overview.contextUnavailable"))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct InstrumentationView: View {
    let metrics: ScanMetrics?
    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let metrics {
                metricGrid(metrics)
                parserDetails(metrics)
                slowestFilesTable(metrics)
            } else {
                emptyState
            }
        }
        .padding(16)
        .frame(width: 480, alignment: .leading)
        .background(palette.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .background(palette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(ModexStrings.text("instrumentation.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)
        }
    }

    private var headerSubtitle: String {
        guard let metrics else {
            return ModexStrings.text("instrumentation.noCompletedRead")
        }
        return "\(metrics.parserMode)  \(metrics.filesParsed)/\(metrics.filesSelected)"
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.mutedText)
            Text(ModexStrings.text("instrumentation.noCompletedRead"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sidebar.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.surface.opacity(0.58), lineWidth: 0.6)
        }
    }

    private func metricGrid(_ metrics: ScanMetrics) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            alignment: .leading,
            spacing: 8
        ) {
            metricTile(
                symbol: "clock",
                title: ModexStrings.text("instrumentation.duration"),
                value: formatDuration(metrics.durationSeconds),
                tint: palette.accent
            )
            metricTile(
                symbol: "arrow.down.doc",
                title: ModexStrings.text("instrumentation.read"),
                value: formatBytes(metrics.bytesRead),
                tint: .mint
            )
            metricTile(
                symbol: "doc.text",
                title: ModexStrings.text("instrumentation.files"),
                value: "\(metrics.filesParsed)/\(metrics.filesSelected)",
                tint: .blue
            )
            metricTile(
                symbol: "cpu",
                title: ModexStrings.text("instrumentation.concurrency"),
                value: concurrencyValue(metrics),
                tint: .orange
            )
            metricTile(
                symbol: "externaldrive.badge.checkmark",
                title: ModexStrings.text("instrumentation.cache"),
                value: cacheValue(metrics),
                tint: .cyan
            )
        }
    }

    private func metricTile(symbol: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(palette.sidebar.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.surface.opacity(0.5), lineWidth: 0.6)
        }
    }

    private func parserDetails(_ metrics: ScanMetrics) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(
                symbol: "slider.horizontal.3",
                title: ModexStrings.text("instrumentation.parser")
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(detailRows(metrics)) { detail in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.mutedText)
                            .lineLimit(1)
                        Text(detail.value)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(palette.sidebar.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func slowestFilesTable(_ metrics: ScanMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(
                symbol: "list.bullet.rectangle",
                title: ModexStrings.text("instrumentation.slowestFiles")
            )

            VStack(spacing: 0) {
                slowestFilesHeader

                let slowestFiles = slowestFiles(metrics)
                if slowestFiles.isEmpty {
                    Text(ModexStrings.text("instrumentation.none"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                } else {
                    ForEach(slowestFiles, id: \.fileURL) { file in
                        slowestFileRow(file)
                    }
                }
            }
        }
        .padding(10)
        .background(palette.sidebar.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var slowestFilesHeader: some View {
        HStack(spacing: 0) {
            Text(ModexStrings.text("column.session.title"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ModexStrings.text("instrumentation.duration"))
                .frame(width: 72, alignment: .trailing)
            Text(ModexStrings.text("instrumentation.read"))
                .frame(width: 78, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(palette.mutedText)
        .textCase(.uppercase)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.surface.opacity(0.58))
                .frame(height: 1)
        }
    }

    private func slowestFileRow(_ file: FileScanMetrics) -> some View {
        HStack(spacing: 0) {
            Text(slowestFileTitle(file))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatDuration(file.durationSeconds))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
            Text(formatBytes(file.bytesRead))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .help(slowestFileHelp(file))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.surface.opacity(0.28))
                .frame(height: 1)
        }
    }

    private func slowestFileTitle(_ file: FileScanMetrics) -> String {
        if let threadName = file.threadName, threadName.isEmpty == false {
            return threadName
        }

        if let sessionID = file.sessionID, sessionID.isEmpty == false {
            return ModexStrings.format("overview.sessionLabel", String(sessionID.prefix(8)))
        }

        return fileName(file.fileURL)
    }

    private func slowestFileHelp(_ file: FileScanMetrics) -> String {
        var rows: [String] = []
        if let threadName = file.threadName, threadName.isEmpty == false {
            rows.append(ModexStrings.format("overview.threadLabel", threadName))
        }
        if let workingDirectory = file.workingDirectory, workingDirectory.isEmpty == false {
            rows.append(ModexStrings.format("overview.projectLabel", workingDirectory))
        }
        if let sessionID = file.sessionID, sessionID.isEmpty == false {
            rows.append(ModexStrings.format("overview.sessionTooltipLabel", sessionID))
        }
        rows.append(ModexStrings.format("overview.fileLabel", file.fileURL.path))
        return rows.joined(separator: "\n")
    }

    private func sectionTitle(symbol: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private func detailRows(_ metrics: ScanMetrics) -> [InstrumentationDetail] {
        let oversizedLines = metrics.fileMetrics.reduce(0) { $0 + $1.oversizedLines }
        let maxBufferedLine = metrics.fileMetrics.map(\.maximumBufferedLineBytes).max() ?? 0
        var rows = [
            InstrumentationDetail(
                id: "parser",
                label: ModexStrings.text("instrumentation.parser"),
                value: metrics.parserMode
            ),
            InstrumentationDetail(
                id: "chunk",
                label: ModexStrings.text("instrumentation.chunk"),
                value: formatBytes(metrics.chunkSizeBytes)
            ),
            InstrumentationDetail(
                id: "line-cap",
                label: ModexStrings.text("instrumentation.lineCap"),
                value: formatBytes(metrics.maximumLineBufferBytes)
            ),
            InstrumentationDetail(
                id: "index-line-cap",
                label: ModexStrings.text("config.indexLineBuffer"),
                value: formatBytes(metrics.sessionIndexMaximumLineBufferBytes)
            ),
            InstrumentationDetail(
                id: "peak-line",
                label: ModexStrings.text("instrumentation.peakLine"),
                value: formatBytes(maxBufferedLine)
            ),
            InstrumentationDetail(
                id: "oversized",
                label: ModexStrings.text("instrumentation.oversized"),
                value: "\(oversizedLines)"
            ),
        ]
        if metrics.cacheEnabled {
            rows.append(
                InstrumentationDetail(
                    id: "cache-saved",
                    label: ModexStrings.text("instrumentation.cacheSaved"),
                    value: formatBytes(metrics.cacheBytesSaved)
                )
            )
            rows.append(
                InstrumentationDetail(
                    id: "cache-entries",
                    label: ModexStrings.text("instrumentation.cacheEntries"),
                    value: "\(metrics.cacheEntries)"
                )
            )
        }
        return rows
    }

    private func slowestFiles(_ metrics: ScanMetrics) -> [FileScanMetrics] {
        Array(
            metrics.fileMetrics
                .filter { $0.cacheHit == false }
                .sorted { $0.durationSeconds > $1.durationSeconds }
                .prefix(5)
        )
    }

    private func cacheValue(_ metrics: ScanMetrics) -> String {
        guard metrics.cacheEnabled else {
            return ModexStrings.text("instrumentation.cacheOff")
        }
        return "\(metrics.cacheHits)/\(metrics.filesSelected)"
    }

    private func concurrencyValue(_ metrics: ScanMetrics) -> String {
        if metrics.maximumConcurrentParses == metrics.configuredMaximumConcurrentParses {
            return "\(metrics.maximumConcurrentParses)x"
        }
        return "\(metrics.maximumConcurrentParses)x / \(metrics.configuredMaximumConcurrentParses)x"
    }
}

private struct InstrumentationDetail: Identifiable {
    let id: String
    let label: String
    let value: String
}

private struct ConfigurationView: View {
    @Binding var settings: ModexAppSettings
    let onOpenCodexFolder: () -> Void
    let onFlushScanCache: () -> Void
    @Environment(\.modexPalette) private var palette
    @State private var selectedSection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.indigo)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ModexStrings.text("config.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(ModexStrings.text("config.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()
            }

            PaletteSegmentedControl(
                options: [
                    PaletteSegmentedOption(value: 0, title: ModexStrings.text("config.general")),
                    PaletteSegmentedOption(value: 1, title: ModexStrings.text("config.appearance")),
                    PaletteSegmentedOption(value: 2, title: ModexStrings.text("config.context")),
                    PaletteSegmentedOption(value: 3, title: ModexStrings.text("config.expert")),
                ],
                selection: $selectedSection
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedSection {
                    case 0:
                        generalSettings
                    case 1:
                        appearanceSettings
                    case 2:
                        contextSettings
                    default:
                        expertSettings
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)

            HStack {
                Spacer()
                IconButton(symbol: "arrow.counterclockwise", label: ModexStrings.text("config.reset")) {
                    settings = .default
                }
            }
        }
        .padding(18)
        .frame(width: 480, height: 430, alignment: .top)
        .background(palette.background)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(
                title: ModexStrings.text("config.monitoringSection"),
                symbol: "waveform.path.ecg.rectangle",
                tint: .blue
            ) {
                stepperRow(
                    icon: "doc.text.magnifyingglass",
                    tint: .blue,
                    title: ModexStrings.text("config.scanLimit"),
                    detail: ModexStrings.text("config.scanLimitHelp"),
                    value: Binding(
                        get: { settings.scanLimit },
                        set: { settings = updatedSettings(scanLimit: $0) }
                    ),
                    range: 1...100,
                    suffix: ""
                )

                stepperRow(
                    icon: "clock.arrow.circlepath",
                    tint: .blue,
                    title: ModexStrings.text("config.refresh"),
                    detail: ModexStrings.text("config.refreshHelp"),
                    value: Binding(
                        get: { Int(settings.refreshIntervalSeconds) },
                        set: { settings = updatedSettings(refreshIntervalSeconds: TimeInterval($0)) }
                    ),
                    range: 10...300,
                    step: 5,
                    suffix: "s"
                )

                settingsRow(
                    icon: "archivebox",
                    tint: .blue,
                    title: ModexStrings.text("config.includeArchived"),
                    detail: ModexStrings.text("config.includeArchivedHelp")
                ) {
                    PaletteToggle(
                        isOn: Binding(
                            get: { settings.includeArchivedSessions },
                            set: { settings = updatedSettings(includeArchivedSessions: $0) }
                        ),
                        label: ModexStrings.text("config.includeArchived")
                    )
                }

                settingsRow(
                    icon: "externaldrive.badge.checkmark",
                    tint: .blue,
                    title: ModexStrings.text("config.scanCache"),
                    detail: ModexStrings.text("config.scanCacheHelp")
                ) {
                    PaletteToggle(
                        isOn: Binding(
                            get: { settings.scanCacheEnabled },
                            set: { settings = updatedSettings(scanCacheEnabled: $0) }
                        ),
                        label: ModexStrings.text("config.scanCache")
                    )
                }

                settingsRow(
                    icon: "trash",
                    tint: .blue,
                    title: ModexStrings.text("config.flushCache"),
                    detail: ModexStrings.text("config.flushCacheHelp")
                ) {
                    IconButton(
                        symbol: "trash",
                        label: ModexStrings.text("config.flushCache"),
                        action: onFlushScanCache
                    )
                }
            }

            settingsSection(
                title: ModexStrings.text("config.locationsSection"),
                symbol: "folder.badge.gearshape",
                tint: .teal
            ) {
                settingsRow(
                    icon: "folder",
                    tint: .teal,
                    title: ModexStrings.text("config.codexFolder"),
                    detail: ModexStrings.text("config.codexFolderHelp")
                ) {
                    IconButton(
                        symbol: "arrow.up.forward.app",
                        label: ModexStrings.text("overview.openCodexFolder"),
                        action: onOpenCodexFolder
                    )
                }
            }
        }
    }

    private var appearanceSettings: some View {
        settingsSection(
            title: ModexStrings.text("config.appearanceSection"),
            symbol: "paintpalette",
            tint: .green
        ) {
            settingsRow(
                icon: "circle.lefthalf.filled",
                tint: .green,
                title: ModexStrings.text("config.theme"),
                detail: ModexStrings.text("config.themeHelp")
            ) {
                PaletteSegmentedControl(
                    options: ModexColorTheme.allCases.map {
                        PaletteSegmentedOption(value: $0, title: $0.title)
                    },
                    selection: Binding(
                        get: { settings.colorTheme },
                        set: { settings = updatedSettings(colorTheme: $0) }
                    )
                )
                .frame(width: 200)
            }

            settingsRow(
                icon: "globe",
                tint: .green,
                title: ModexStrings.text("config.language"),
                detail: ModexStrings.text("config.languageHelp")
            ) {
                LanguageChipPicker(
                    selection: Binding(
                        get: { settings.language },
                        set: { settings = updatedSettings(language: $0) }
                    )
                )
            }

            stepperRow(
                icon: "cursorarrow.rays",
                tint: .green,
                title: ModexStrings.text("config.sessionHoverDelay"),
                detail: ModexStrings.text("config.sessionHoverDelayHelp"),
                value: Binding(
                    get: { settings.sessionDetailHoverDelayMilliseconds },
                    set: { settings = updatedSettings(sessionDetailHoverDelayMilliseconds: $0) }
                ),
                range: 0...1500,
                step: 50,
                suffix: " ms"
            )
        }
    }

    private var contextSettings: some View {
        settingsSection(
            title: ModexStrings.text("config.contextSection"),
            symbol: "gauge.medium",
            tint: .orange
        ) {
            thresholdSlider(
                color: ModexTheme.noticeContextColor,
                title: ModexStrings.text("config.yellow"),
                detail: ModexStrings.text("config.yellowHelp"),
                value: Binding(
                    get: { settings.contextThresholds.yellowPercent },
                    set: { settings = updatedSettings(yellowPercent: $0) }
                )
            )
            thresholdSlider(
                color: ModexTheme.warningContextColor,
                title: ModexStrings.text("config.orange"),
                detail: ModexStrings.text("config.orangeHelp"),
                value: Binding(
                    get: { settings.contextThresholds.orangePercent },
                    set: { settings = updatedSettings(orangePercent: $0) }
                )
            )
            thresholdSlider(
                color: ModexTheme.criticalContextColor,
                title: ModexStrings.text("config.red"),
                detail: ModexStrings.text("config.redHelp"),
                value: Binding(
                    get: { settings.contextThresholds.redPercent },
                    set: { settings = updatedSettings(redPercent: $0) }
                )
            )
        }
    }

    private var expertSettings: some View {
        settingsSection(
            title: ModexStrings.text("config.parserSection"),
            symbol: "speedometer",
            tint: .purple
        ) {
            stepperRow(
                icon: "square.stack.3d.up",
                tint: .purple,
                title: ModexStrings.text("config.readConcurrency"),
                detail: ModexStrings.text("config.readConcurrencyHelp"),
                value: Binding(
                    get: { settings.parserTuning.maximumConcurrentParses },
                    set: { settings = updatedSettings(maximumConcurrentParses: $0) }
                ),
                range: 1...ModexParserTuningSettings.maximumAllowedConcurrentParses,
                suffix: "x"
            )

            stepperRow(
                icon: "arrow.down.doc",
                tint: .purple,
                title: ModexStrings.text("config.chunkSize"),
                detail: ModexStrings.text("config.chunkSizeHelp"),
                value: Binding(
                    get: { settings.parserTuning.chunkSizeKB },
                    set: { settings = updatedSettings(chunkSizeKB: $0) }
                ),
                range: ModexParserTuningSettings.chunkSizeRangeKB,
                step: 64,
                suffix: " KB"
            )

            stepperRow(
                icon: "text.alignleft",
                tint: .purple,
                title: ModexStrings.text("config.lineBuffer"),
                detail: ModexStrings.text("config.lineBufferHelp"),
                value: Binding(
                    get: { settings.parserTuning.lineBufferKB },
                    set: { settings = updatedSettings(lineBufferKB: $0) }
                ),
                range: ModexParserTuningSettings.lineBufferRangeKB,
                step: 64,
                suffix: " KB"
            )

            stepperRow(
                icon: "list.bullet.rectangle",
                tint: .purple,
                title: ModexStrings.text("config.indexLineBuffer"),
                detail: ModexStrings.text("config.indexLineBufferHelp"),
                value: Binding(
                    get: { settings.parserTuning.sessionIndexLineBufferKB },
                    set: { settings = updatedSettings(sessionIndexLineBufferKB: $0) }
                ),
                range: ModexParserTuningSettings.sessionIndexLineBufferRangeKB,
                step: 32,
                suffix: " KB"
            )
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
        }
    }

    private func stepperRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String
    ) -> some View {
        settingsRow(icon: icon, tint: tint, title: title, detail: detail) {
            PaletteNumberControl(value: value, range: range, step: step, suffix: suffix, fill: tint)
        }
    }

    private func thresholdSlider(color: Color, title: String, detail: String, value: Binding<Double>) -> some View {
        settingsRow(icon: "circle.fill", tint: color, title: title, detail: detail) {
            HStack(spacing: 8) {
                PaletteInlineSlider(
                    value: value,
                    range: 1...100,
                    step: 1,
                    fill: color
                )
                .frame(width: 150, height: 28)
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func settingsRow<Control: View>(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            control()
                .padding(.top, 1)
        }
    }

    private func updatedSettings(
        scanLimit: Int? = nil,
        refreshIntervalSeconds: TimeInterval? = nil,
        includeArchivedSessions: Bool? = nil,
        scanCacheEnabled: Bool? = nil,
        yellowPercent: Double? = nil,
        orangePercent: Double? = nil,
        redPercent: Double? = nil,
        colorTheme: ModexColorTheme? = nil,
        language: ModexLanguage? = nil,
        sessionDetailHoverDelayMilliseconds: Int? = nil,
        maximumConcurrentParses: Int? = nil,
        chunkSizeKB: Int? = nil,
        lineBufferKB: Int? = nil,
        sessionIndexLineBufferKB: Int? = nil
    ) -> ModexAppSettings {
        var next = settings
        if let scanLimit {
            next.scanLimit = scanLimit
        }
        if let refreshIntervalSeconds {
            next.refreshIntervalSeconds = refreshIntervalSeconds
        }
        if let includeArchivedSessions {
            next.includeArchivedSessions = includeArchivedSessions
        }
        if let scanCacheEnabled {
            next.scanCacheEnabled = scanCacheEnabled
        }
        if let yellowPercent {
            next.contextThresholds.yellowPercent = yellowPercent
        }
        if let orangePercent {
            next.contextThresholds.orangePercent = orangePercent
        }
        if let redPercent {
            next.contextThresholds.redPercent = redPercent
        }
        if let colorTheme {
            next.colorTheme = colorTheme
        }
        if let language {
            next.language = language
        }
        if let sessionDetailHoverDelayMilliseconds {
            next.sessionDetailHoverDelayMilliseconds = sessionDetailHoverDelayMilliseconds
        }
        if let maximumConcurrentParses {
            next.parserTuning.maximumConcurrentParses = maximumConcurrentParses
        }
        if let chunkSizeKB {
            next.parserTuning.chunkSizeKB = chunkSizeKB
        }
        if let lineBufferKB {
            next.parserTuning.lineBufferKB = lineBufferKB
        }
        if let sessionIndexLineBufferKB {
            next.parserTuning.sessionIndexLineBufferKB = sessionIndexLineBufferKB
        }
        return next.normalized()
    }
}

private struct PaletteSegmentedOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

private struct LanguageChipPicker: View {
    @Binding var selection: ModexLanguage

    @Environment(\.modexPalette) private var palette
    @State private var hoveredLanguage: ModexLanguage?

    private let columns = [
        GridItem(.fixed(72), spacing: 6),
        GridItem(.fixed(54), spacing: 6),
        GridItem(.fixed(54), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .trailing, spacing: 6) {
            ForEach(ModexLanguage.allCases) { language in
                Button {
                    selection = language
                } label: {
                    HStack(spacing: 5) {
                        Text(language.marker)
                            .font(.system(size: 12))
                        Text(language.shortTitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(language == selection ? Color.white : palette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(chipBackground(for: language))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredLanguage = isHovered ? language : nil
                }
                .help(language.title)
                .accessibilityLabel(Text(language.title))
            }
        }
        .padding(4)
        .background(palette.sidebar.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.surface.opacity(0.55), lineWidth: 0.7)
        }
        .animation(.easeInOut(duration: 0.12), value: selection)
    }

    @ViewBuilder
    private func chipBackground(for language: ModexLanguage) -> some View {
        if language == selection {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.accent)
        } else if language == hoveredLanguage {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.surfaceHighlight)
        } else {
            Color.clear
        }
    }
}

private struct PaletteSegmentedControl<Value: Hashable>: View {
    let options: [PaletteSegmentedOption<Value>]
    @Binding var selection: Value

    @Environment(\.modexPalette) private var palette
    @State private var hoveredValue: Value?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(option.value == selection ? Color.white : palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(segmentBackground(for: option.value))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredValue = isHovered ? option.value : nil
                }
                .accessibilityLabel(Text(option.title))
            }
        }
        .padding(3)
        .background(palette.sidebar.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.surface.opacity(0.55), lineWidth: 0.7)
        }
        .animation(.easeInOut(duration: 0.12), value: selection)
    }

    @ViewBuilder
    private func segmentBackground(for value: Value) -> some View {
        if value == selection {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.accent)
        } else if value == hoveredValue {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.surfaceHighlight)
        } else {
            Color.clear
        }
    }
}

private struct PaletteNumberControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String
    let fill: Color

    @Environment(\.modexPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isTextFieldFocused: Bool
    @State private var draft = ""
    @State private var isEditing = false
    @State private var showsEditingChrome = false
    @State private var isValueHovered = false
    @State private var editingChromeTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            PaletteInlineSlider(
                value: Binding(
                    get: { Double(value) },
                    set: { newValue in
                        value = clamped(Int(newValue.rounded()))
                        draft = "\(value)"
                    }
                ),
                range: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(max(1, step)),
                fill: fill
            )
            .frame(width: 150, height: 28)

            HStack(spacing: 2) {
                if isEditing {
                    TextField("", text: draftBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            finishEditing()
                        }
                        .onAppear {
                            isTextFieldFocused = true
                        }
                } else {
                    Text("\(value)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if suffix.isEmpty == false {
                    Text(suffix.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.mutedText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 72, height: 28, alignment: .trailing)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(showsValueChrome ? palette.surfaceHighlight : Color.clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(showsValueChrome ? fill.opacity(0.75) : Color.clear, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onTapGesture {
                beginEditing()
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.10)) {
                    isValueHovered = hovering
                }
                if hovering == false, isEditing {
                    finishEditing()
                }
            }
        }
        .onAppear {
            draft = "\(value)"
        }
        .onChange(of: value) { _, newValue in
            guard isEditing == false else {
                return
            }
            draft = "\(newValue)"
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draft = "\(value)"
                revealEditingChromeBriefly()
            } else {
                commitDraft()
                hideEditingChrome()
            }
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if focused == false, isEditing {
                finishEditing()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isEditing {
                finishEditing()
            }
        }
        .onDisappear {
            editingChromeTask?.cancel()
            finishEditing()
        }
        .accessibilityLabel(Text(displayValue))
    }

    private var displayValue: String {
        "\(value)\(suffix)"
    }

    private var showsValueChrome: Bool {
        isValueHovered || isEditing || showsEditingChrome
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: {
                isEditing ? draft : "\(value)"
            },
            set: { newValue in
                draft = newValue.filter(\.isNumber)
                if isEditing {
                    revealEditingChromeBriefly()
                }
            }
        )
    }

    private func commitDraft() {
        let parsed = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? value
        value = clamped(parsed)
        draft = "\(value)"
    }

    private func beginEditing() {
        guard isEditing == false else {
            return
        }
        draft = "\(value)"
        isEditing = true
        revealEditingChromeBriefly()
    }

    private func finishEditing() {
        guard isEditing else {
            return
        }
        commitDraft()
        isEditing = false
        isTextFieldFocused = false
    }

    private func revealEditingChromeBriefly() {
        editingChromeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.10)) {
            showsEditingChrome = true
        }
        guard isEditing == false else {
            return
        }
        editingChromeTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }
            withAnimation(.easeOut(duration: 0.14)) {
                showsEditingChrome = false
            }
        }
    }

    private func hideEditingChrome() {
        editingChromeTask?.cancel()
        withAnimation(.easeOut(duration: 0.10)) {
            showsEditingChrome = false
        }
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

private struct PaletteInlineSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let fill: Color

    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            let knobSize: CGFloat = isHovered ? 20 : 18
            let trackHeight: CGFloat = 6
            let trackWidth = max(1, proxy.size.width - knobSize)
            let knobX = trackWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.surface.opacity(0.54))
                    .frame(width: trackWidth, height: trackHeight)
                    .offset(x: knobSize / 2)

                Capsule()
                    .fill(fill.opacity(0.92))
                    .frame(width: max(trackHeight, trackWidth * progress), height: trackHeight)
                    .offset(x: knobSize / 2)

                Circle()
                    .fill(palette.sidebar)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Circle()
                            .stroke(palette.surface.opacity(0.62), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(isHovered ? 0.16 : 0.10), radius: 4, y: 1.5)
                    .offset(x: knobX)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        updateValue(locationX: drag.location.x, width: proxy.size.width, knobSize: knobSize)
                    }
            )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = clamped(value + max(1, step))
            case .decrement:
                value = clamped(value - max(1, step))
            @unknown default:
                break
            }
        }
    }

    private var progress: CGFloat {
        let span = max(1, range.upperBound - range.lowerBound)
        return CGFloat((value - range.lowerBound) / span)
    }

    private func updateValue(locationX: CGFloat, width: CGFloat, knobSize: CGFloat) {
        let trackWidth = max(1, width - knobSize)
        let fraction = min(max((locationX - knobSize / 2) / trackWidth, 0), 1)
        let span = range.upperBound - range.lowerBound
        let raw = range.lowerBound + Double(fraction) * span
        let step = max(1, step)
        let steps = ((raw - range.lowerBound) / step).rounded()
        value = clamped(range.lowerBound + steps * step)
    }

    private func clamped(_ candidate: Double) -> Double {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

private struct PaletteToggle: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? palette.accent.opacity(0.92) : palette.surfaceHighlight)

                Circle()
                    .fill(isOn ? Color.white : palette.secondaryText.opacity(0.72))
                    .frame(width: 16, height: 16)
                    .padding(3)
                    .shadow(color: .black.opacity(isHovered ? 0.18 : 0.08), radius: 3, y: 1)
            }
            .frame(width: 42, height: 22)
            .overlay {
                Capsule()
                    .stroke(palette.surface.opacity(isHovered ? 0.9 : 0.55), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isOn ? ModexStrings.text("config.on") : ModexStrings.text("config.off")))
    }
}

private extension View {
    func sessionDetailTip(_ text: String, delayMilliseconds: Int) -> some View {
        modifier(SessionDetailTipModifier(text: text, delayMilliseconds: delayMilliseconds))
    }
}

private struct SessionDetailTipModifier: ViewModifier {
    let text: String
    let delayMilliseconds: Int
    @Environment(\.modexPalette) private var palette
    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                updateHover(hovering)
            }
            .popover(isPresented: $isPresented, arrowEdge: .leading) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .padding(10)
                    .frame(width: 360, alignment: .leading)
                    .background(palette.sidebar)
            }
            .onDisappear {
                hoverTask?.cancel()
                isPresented = false
            }
    }

    private func updateHover(_ hovering: Bool) {
        hoverTask?.cancel()
        guard hovering else {
            withAnimation(.easeInOut(duration: 0.10)) {
                isPresented = false
            }
            return
        }

        let delayNanoseconds = UInt64(max(0, delayMilliseconds)) * 1_000_000
        hoverTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }

            guard Task.isCancelled == false else {
                return
            }
            withAnimation(.easeInOut(duration: 0.10)) {
                isPresented = true
            }
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    var isEnabled = true
    var onHoverLabel: ((String?) -> Void)?
    let action: () -> Void

    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 20, height: 20)
            .foregroundStyle(isEnabled ? (isHovered ? palette.accent : palette.secondaryText) : palette.mutedText)
            .frame(width: 28, height: 24)
            .background(isHovered && isEnabled ? palette.surfaceHighlight : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(label))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
            onHoverLabel?(hovering && isEnabled ? label : nil)
        }
        .onDisappear {
            onHoverLabel?(nil)
        }
    }
}

func compact(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName))
}

private func groupedSessions(_ sessions: [SessionSnapshot]) -> [SessionGroup] {
    var order: [String] = []
    var groups: [String: SessionGroupBuilder] = [:]

    for (index, session) in sessions.enumerated() {
        let id = session.workingDirectory.flatMap { $0.isEmpty ? nil : $0 } ?? "__codex__"
        if groups[id] == nil {
            order.append(id)
            groups[id] = SessionGroupBuilder(
                id: id,
                title: projectTitle(for: session),
                sessions: []
            )
        }
        groups[id]?.sessions.append(IndexedSession(index: index, session: session))
    }

    return order.compactMap { id in
        guard let group = groups[id] else {
            return nil
        }
        return SessionGroup(id: group.id, title: group.title, sessions: group.sessions)
    }
}

private func projectTitle(for session: SessionSnapshot) -> String {
    guard let workingDirectory = session.workingDirectory, workingDirectory.isEmpty == false else {
        return ModexStrings.text("overview.codexSession")
    }

    let title = URL(fileURLWithPath: workingDirectory).lastPathComponent
    return title.isEmpty ? workingDirectory : title
}

func formatDuration(_ seconds: Double) -> String {
    if seconds < 1 {
        return "\(Int((seconds * 1_000).rounded()))ms"
    }
    return String(format: "%.2fs", seconds)
}

func formatBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

func fileName(_ url: URL) -> String {
    let name = url.deletingPathExtension().lastPathComponent
    if name.hasPrefix("rollout-") {
        return String(name.dropFirst("rollout-".count))
    }
    return name.isEmpty ? ModexStrings.text("instrumentation.sessionFallback") : name
}
