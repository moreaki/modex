import ModexCore
import SwiftUI

struct ModexMenuView: View {
    @ObservedObject var model: ModexMenuModel
    let onRefresh: () -> Void
    let onOpenCodexFolder: () -> Void
    let onFlushScanCache: () -> Void
    let onTestIntelligenceConnection: () -> Void
    let onRequestAgentInsight: (ModexInsight) -> Void
    let onFlushAgentInsightCache: () -> Void
    let onSettingsChange: (ModexAppSettings) -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @State private var showingInstrumentation = false
    @State private var showingConfiguration = false
    @State private var footerHint: String?

    var body: some View {
        VStack(spacing: 14) {
            dashboardHeader
            dashboardContent
            DashboardTopThreadsPanel(
                sessions: topDashboardSessions,
                thresholds: model.settings.contextThresholds,
                sessionDetailHoverDelayMilliseconds: model.settings.sessionDetailHoverDelayMilliseconds
            )
            footer
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 980, height: 720)
        .background(palette.background)
        .foregroundStyle(palette.text)
        .environment(\.modexPalette, palette)
    }

    private var palette: ModexPalette {
        ModexTheme.palette(for: model.settings.colorTheme, colorScheme: colorScheme)
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ModexStrings.text("dashboard.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(summaryText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 18)

            Text(statusText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            Button {
                openWindow(id: ModexWindowID.threadDetail)
            } label: {
                Label(ModexStrings.text("dashboard.openDetail"), systemImage: "rectangle.grid.1x2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: 12) {
            DashboardMetricGrid(summary: model.summary)
            if let latestRateLimits = model.summary?.latestRateLimits {
                CodexRateLimitOverview(rateLimits: latestRateLimits)
            }
            DashboardHistoryPanel(
                summary: model.summary,
                history: model.history,
                thresholds: model.settings.contextThresholds
            )
            DashboardInsightStrip(summary: model.summary, metrics: model.latestMetrics)
        }
    }

    fileprivate var sessionTable: some View {
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
                                history: model.history,
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

    private var topDashboardSessions: [IndexedSession] {
        Array(
            (model.summary?.sessions ?? [])
                .enumerated()
                .map { IndexedSession(index: $0.offset, session: $0.element) }
                .sorted { lhs, rhs in
                    dashboardAttentionScore(lhs.session) > dashboardAttentionScore(rhs.session)
                }
                .prefix(5)
        )
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
                    intelligenceConnectionState: model.intelligenceConnectionState,
                    onOpenCodexFolder: onOpenCodexFolder,
                    onFlushScanCache: onFlushScanCache,
                    onTestIntelligenceConnection: onTestIntelligenceConnection,
                    onFlushAgentInsightCache: onFlushAgentInsightCache
                )
            }

            IconButton(
                symbol: "rectangle.grid.1x2",
                label: ModexStrings.text("dashboard.openDetail"),
                onHoverLabel: setFooterHint
            ) {
                openWindow(id: ModexWindowID.threadDetail)
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
        .frame(height: 30)
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

struct ModexThreadDetailWindow: View {
    @ObservedObject var model: ModexMenuModel
    let onRequestAgentInsight: (ModexInsight) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: ThreadDetailTab = .overview
    @State private var searchText = ""
    @State private var selectedProject = ThreadProjectFilter.all
    @State private var warningsOnly = false
    @State private var failuresOnly = false

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            filterBar
            tabBar
            Divider()
                .overlay(palette.surface.opacity(0.6))
            selectedTabContent
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(palette.background)
        .foregroundStyle(palette.text)
        .environment(\.modexPalette, palette)
    }

    private var palette: ModexPalette {
        ModexTheme.palette(for: model.settings.colorTheme, colorScheme: colorScheme)
    }

    private var sessions: [SessionSnapshot] {
        model.summary?.sessions ?? []
    }

    private var filteredSessions: [SessionSnapshot] {
        sessions.filter { session in
            if warningsOnly, (session.contextUsagePercent ?? 0) < model.settings.contextThresholds.yellowPercent {
                return false
            }
            if failuresOnly, session.failedCommandEvents == 0 {
                return false
            }
            if selectedProject.id != ThreadProjectFilter.all.id,
               projectTitle(for: session) != selectedProject.title
            {
                return false
            }
            guard searchText.isEmpty == false else {
                return true
            }
            let haystack = [
                session.threadName,
                session.sessionID,
                session.workingDirectory,
                session.model,
                session.reasoningEffort,
            ]
            .compactMap(\.self)
            .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var projectFilters: [ThreadProjectFilter] {
        let titles = Set(sessions.map(projectTitle(for:)))
        return [.all] + titles.sorted().map { ThreadProjectFilter(id: $0, title: $0) }
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ModexStrings.text("detail.title"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detailSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(model.lastReadStatus)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var detailSubtitle: String {
        guard let summary = model.summary else {
            return ModexStrings.text("overview.noMetrics")
        }
        return [
            ModexStrings.format("overview.sessions", summary.sessionsScanned),
            ModexStrings.format("overview.tokens", compact(summary.totalTokens)),
            ModexStrings.format("overview.compactions", summary.compactionEvents),
            summary.scanMetrics.map { ModexStrings.format("overview.scanDuration", formatDuration($0.durationSeconds)) },
        ]
        .compactMap(\.self)
        .joined(separator: "  ")
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField(ModexStrings.text("detail.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(width: 260, height: 32)
                .background(palette.sidebar.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.surface.opacity(0.55), lineWidth: 0.7)
                }

            Picker("", selection: $selectedProject) {
                ForEach(projectFilters) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            filterToggle(
                title: ModexStrings.text("detail.warnings"),
                symbol: "exclamationmark.triangle",
                isOn: $warningsOnly
            )
            filterToggle(
                title: ModexStrings.text("detail.failures"),
                symbol: "xmark.octagon",
                isOn: $failuresOnly
            )

            Spacer()

            Text(ModexStrings.format("detail.filteredCount", filteredSessions.count, sessions.count))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedText)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private func filterToggle(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.white : palette.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(isOn.wrappedValue ? palette.accent : palette.sidebar.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.surface.opacity(isOn.wrappedValue ? 0 : 0.55), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(ThreadDetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tab == selectedTab ? palette.accent : palette.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(tab == selectedTab ? palette.surfaceHighlight : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .overview:
            ThreadOverviewTab(
                sessions: filteredSessions,
                history: model.history,
                thresholds: model.settings.contextThresholds,
                sessionDetailHoverDelayMilliseconds: model.settings.sessionDetailHoverDelayMilliseconds
            )
        case .tokens:
            ThreadMetricCardsTab(
                sessions: filteredSessions,
                cards: tokenCards,
                leaders: tokenLeaders
            )
        case .performance:
            ThreadMetricCardsTab(
                sessions: filteredSessions,
                cards: performanceCards,
                leaders: performanceLeaders
            )
        case .activity:
            ThreadMetricCardsTab(
                sessions: filteredSessions,
                cards: activityCards,
                leaders: activityLeaders
            )
        case .insights:
            ThreadInsightsTab(
                insights: filteredInsights,
                canRequestAgentInsights: model.canRequestAgentInsights,
                onRequestAgentInsight: onRequestAgentInsight
            )
        case .diagnostics:
            ThreadDiagnosticsTab(metrics: model.latestMetrics)
        }
    }

    private var filteredInsights: [ModexInsight] {
        let keys = Set(filteredSessions.map(ModexHistorySnapshot.sessionKey(for:)))
        return model.displayedInsights.filter { insight in
            guard let sessionKey = insight.sessionKey else {
                return true
            }
            return keys.contains(sessionKey)
        }
    }

    private var tokenCards: [ThreadMetricCard] {
        [
            ThreadMetricCard(title: ModexStrings.text("dashboard.cachedInput"), value: percentText(average(filteredSessions.compactMap(\.cachedInputPercent))), detail: ModexStrings.text("detail.tokensCachedDetail")),
            ThreadMetricCard(title: ModexStrings.text("detail.reasoningShare"), value: percentText(average(filteredSessions.compactMap(\.reasoningOutputPercent))), detail: ModexStrings.text("detail.reasoningShareDetail")),
            ThreadMetricCard(title: ModexStrings.text("dashboard.fastestGrowth"), value: "+\(compact(filteredSessions.map(\.latestContextGrowthTokens).max() ?? 0))", detail: ModexStrings.text("detail.contextGrowthDetail")),
            ThreadMetricCard(title: ModexStrings.text("column.compact.helpTitle"), value: "\(filteredSessions.reduce(0) { $0 + $1.compactionEvents })", detail: ModexStrings.text("column.compact.body")),
        ]
    }

    private var performanceCards: [ThreadMetricCard] {
        [
            ThreadMetricCard(title: ModexStrings.text("detail.completedTurns"), value: "\(filteredSessions.reduce(0) { $0 + $1.completedTurns })", detail: ModexStrings.text("detail.completedTurnsDetail")),
            ThreadMetricCard(title: ModexStrings.text("detail.medianDuration"), value: millisecondsText(median(filteredSessions.compactMap(\.medianTurnDurationMilliseconds))), detail: ModexStrings.text("detail.medianDurationDetail")),
            ThreadMetricCard(title: ModexStrings.text("detail.medianTTFT"), value: millisecondsText(median(filteredSessions.compactMap(\.medianTimeToFirstTokenMilliseconds))), detail: ModexStrings.text("detail.medianTTFTDetail")),
            ThreadMetricCard(title: ModexStrings.text("dashboard.slowestTurn"), value: millisecondsText(filteredSessions.compactMap(\.lastTurnDurationMilliseconds).max()), detail: ModexStrings.text("detail.slowestTurnDetail")),
        ]
    }

    private var activityCards: [ThreadMetricCard] {
        [
            ThreadMetricCard(title: ModexStrings.text("detail.commands"), value: "\(filteredSessions.reduce(0) { $0 + $1.commandEvents })", detail: ModexStrings.text("detail.commandsDetail")),
            ThreadMetricCard(title: ModexStrings.text("dashboard.failures"), value: "\(filteredSessions.reduce(0) { $0 + $1.failedCommandEvents })", detail: ModexStrings.text("detail.failuresDetail")),
            ThreadMetricCard(title: ModexStrings.text("dashboard.filesChanged"), value: "\(filteredSessions.reduce(0) { $0 + $1.changedFileEvents })", detail: ModexStrings.text("detail.filesChangedDetail")),
            ThreadMetricCard(title: ModexStrings.text("detail.toolCalls"), value: "\(filteredSessions.reduce(0) { $0 + $1.toolCallEvents })", detail: ModexStrings.text("detail.toolCallsDetail")),
        ]
    }

    private var tokenLeaders: [ThreadLeaderRow] {
        filteredSessions
            .sorted { $0.latestContextGrowthTokens > $1.latestContextGrowthTokens }
            .prefix(8)
            .map {
                ThreadLeaderRow(
                    session: $0,
                    value: "+\(compact($0.latestContextGrowthTokens))",
                    trendValues: totalTrendValues(for: $0, history: model.history)
                )
            }
    }

    private var performanceLeaders: [ThreadLeaderRow] {
        filteredSessions
            .sorted { ($0.lastTurnDurationMilliseconds ?? 0) > ($1.lastTurnDurationMilliseconds ?? 0) }
            .prefix(8)
            .map {
                ThreadLeaderRow(
                    session: $0,
                    value: millisecondsText($0.lastTurnDurationMilliseconds),
                    trendValues: durationTrendValues(for: $0, history: model.history)
                )
            }
    }

    private var activityLeaders: [ThreadLeaderRow] {
        filteredSessions
            .sorted { lhs, rhs in
                if lhs.failedCommandEvents == rhs.failedCommandEvents {
                    return lhs.commandEvents > rhs.commandEvents
                }
                return lhs.failedCommandEvents > rhs.failedCommandEvents
            }
            .prefix(8)
            .map {
                ThreadLeaderRow(
                    session: $0,
                    value: ModexStrings.format("detail.activityValue", $0.commandEvents, $0.failedCommandEvents),
                    trendValues: failedCommandTrendValues(for: $0, history: model.history)
                )
            }
    }
}

private enum ThreadDetailTab: String, CaseIterable, Identifiable {
    case overview
    case tokens
    case performance
    case activity
    case insights
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return ModexStrings.text("detail.overview")
        case .tokens:
            return ModexStrings.text("detail.tokens")
        case .performance:
            return ModexStrings.text("detail.performance")
        case .activity:
            return ModexStrings.text("detail.activity")
        case .insights:
            return ModexStrings.text("detail.insights")
        case .diagnostics:
            return ModexStrings.text("detail.diagnostics")
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            return "tablecells"
        case .tokens:
            return "sum"
        case .performance:
            return "speedometer"
        case .activity:
            return "terminal"
        case .insights:
            return "sparkles"
        case .diagnostics:
            return "stethoscope"
        }
    }
}

private struct ThreadProjectFilter: Hashable, Identifiable {
    static let all = ThreadProjectFilter(id: "__all__", title: ModexStrings.text("detail.allProjects"))

    let id: String
    let title: String
}

private struct ThreadOverviewTab: View {
    let sessions: [SessionSnapshot]
    let history: ModexHistorySnapshot?
    let thresholds: ModexContextThresholds
    let sessionDetailHoverDelayMilliseconds: Int

    @Environment(\.modexPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                tableHeader
                ForEach(groupedSessions(sessions)) { group in
                    ProjectGroupHeader(title: group.title)
                    ForEach(group.sessions) { indexedSession in
                        SessionRow(
                            session: indexedSession.session,
                            index: indexedSession.index,
                            history: history,
                            thresholds: thresholds,
                            sessionDetailHoverDelayMilliseconds: sessionDetailHoverDelayMilliseconds
                        )
                    }
                }
            }
            .padding(18)
        }
        .background(palette.background)
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            ForEach(OverviewColumn.allCases) { column in
                ColumnHeader(column: column)
                    .frame(width: column.width, alignment: column.alignment)
            }
        }
        .frame(height: 32)
        .background(palette.sidebar.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ThreadMetricCardsTab: View {
    let sessions: [SessionSnapshot]
    let cards: [ThreadMetricCard]
    let leaders: [ThreadLeaderRow]

    @Environment(\.modexPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(cards) { card in
                        ThreadMetricCardView(card: card)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(ModexStrings.text("detail.leaders"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)

                    VStack(spacing: 0) {
                        ForEach(leaders) { row in
                            ThreadLeaderRowView(row: row)
                        }
                    }
                    .background(palette.sidebar.opacity(0.66))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.surface.opacity(0.45), lineWidth: 0.7)
                    }
                }
            }
            .padding(22)
        }
    }
}

private struct ThreadMetricCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

private struct ThreadMetricCardView: View {
    let card: ThreadMetricCard
    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            Text(card.value)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(card.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.mutedText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(palette.sidebar.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.surface.opacity(0.45), lineWidth: 0.7)
        }
    }
}

private struct ThreadLeaderRow: Identifiable {
    let id = UUID()
    let session: SessionSnapshot
    let value: String
    var trendValues: [Double] = []
}

private struct ThreadLeaderRowView: View {
    let row: ThreadLeaderRow
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.session.threadName ?? projectTitle(for: row.session))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text("\(projectTitle(for: row.session)) · \(modeValue(row.session.model)) · \(modeValue(row.session.reasoningEffort))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
            }
            Spacer()
            if row.trendValues.count > 1 {
                MiniSparkline(values: row.trendValues, color: palette.accent.opacity(0.76), fill: false)
                    .frame(width: 52, height: 18)
            }
            Text(row.value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.surface.opacity(0.25))
                .frame(height: 1)
        }
    }
}

private struct ThreadInsightsTab: View {
    let insights: [ModexInsight]
    let canRequestAgentInsights: Bool
    let onRequestAgentInsight: (ModexInsight) -> Void
    @Environment(\.modexPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ThreadMetricCardView(
                        card: ThreadMetricCard(
                            title: ModexStrings.text("insights.total"),
                            value: "\(insights.count)",
                            detail: ModexStrings.text("insights.totalDetail")
                        )
                    )
                    ThreadMetricCardView(
                        card: ThreadMetricCard(
                            title: ModexStrings.text("insights.critical"),
                            value: "\(insights.filter { $0.severity == .critical }.count)",
                            detail: ModexStrings.text("insights.criticalDetail")
                        )
                    )
                    ThreadMetricCardView(
                        card: ThreadMetricCard(
                            title: ModexStrings.text("insights.agentGated"),
                            value: "\(insights.filter { $0.status == .agentUnavailable || $0.status == .agentFailed }.count)",
                            detail: ModexStrings.text("insights.agentGatedDetail")
                        )
                    )
                    ThreadMetricCardView(
                        card: ThreadMetricCard(
                            title: ModexStrings.text("insights.evidence"),
                            value: "\(insights.reduce(0) { $0 + $1.evidenceCount })",
                            detail: ModexStrings.text("insights.evidenceDetail")
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(ModexStrings.text("detail.insights"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)

                    VStack(spacing: 0) {
                        insightsHeader
                        if insights.isEmpty {
                            Text(ModexStrings.text("insights.empty"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.mutedText)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            ForEach(insights) { insight in
                                InsightRowView(
                                    insight: insight,
                                    canRequestAgentInsights: canRequestAgentInsights,
                                    onRequestAgentInsight: onRequestAgentInsight
                                )
                            }
                        }
                    }
                    .background(palette.sidebar.opacity(0.66))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.surface.opacity(0.45), lineWidth: 0.7)
                    }
                }
            }
            .padding(22)
        }
    }

    private var insightsHeader: some View {
        HStack(spacing: 12) {
            Text(ModexStrings.text("insights.signal"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ModexStrings.text("insights.status"))
                .frame(width: 98, alignment: .leading)
            Text(ModexStrings.text("insights.evidence"))
                .frame(width: 84, alignment: .trailing)
            Text(ModexStrings.text("insights.updated"))
                .frame(width: 90, alignment: .trailing)
            Text("")
                .frame(width: 76, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(palette.mutedText)
        .textCase(.uppercase)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.surface.opacity(0.32))
                .frame(height: 1)
        }
    }
}

private struct InsightRowView: View {
    let insight: ModexInsight
    let canRequestAgentInsights: Bool
    let onRequestAgentInsight: (ModexInsight) -> Void
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(severityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.mutedText)
                        .lineLimit(2)
                    tertiaryLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(statusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(width: 98, alignment: .leading)

            Text("\(insight.evidenceCount)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 84, alignment: .trailing)

            UpdatedCell(updatedAt: insight.updatedAt)
                .frame(width: 90, alignment: .trailing)

            insightAction
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: insight.agentResult == nil ? 62 : 70)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.surface.opacity(0.24))
                .frame(height: 1)
        }
        .help(helpText)
    }

    private var title: String {
        if let agentResult = insight.agentResult {
            return agentResult.title
        }
        switch insight.kind {
        case .highContext:
            return ModexStrings.text("insights.highContext")
        case .contextGrowth:
            return ModexStrings.text("insights.contextGrowth")
        case .failedCommands:
            return ModexStrings.text("insights.failedCommands")
        case .slowTurn:
            return ModexStrings.text("insights.slowTurn")
        case .repeatedCompactions:
            return ModexStrings.text("insights.repeatedCompactions")
        case .highCacheReuse:
            return ModexStrings.text("insights.highCacheReuse")
        case .scanSlow:
            return ModexStrings.text("insights.scanSlow")
        case .cacheCold:
            return ModexStrings.text("insights.cacheCold")
        }
    }

    private var detail: String {
        if let error = insight.agentError {
            return error
        }
        if let agentResult = insight.agentResult {
            return agentResult.summary
        }
        let thread = insight.threadName ?? insight.projectTitle ?? ModexStrings.text("overview.codexSession")
        switch insight.kind {
        case .highContext:
            return ModexStrings.format("insights.highContextDetail", percentText(insight.primaryValue), thread)
        case .contextGrowth:
            return ModexStrings.format("insights.contextGrowthDetail", percentText(insight.primaryValue), thread)
        case .failedCommands:
            return ModexStrings.format("insights.failedCommandsDetail", insight.count ?? 0, thread)
        case .slowTurn:
            return ModexStrings.format("insights.slowTurnDetail", millisecondsText(insight.primaryValue.map(Int.init)), thread)
        case .repeatedCompactions:
            return ModexStrings.format("insights.repeatedCompactionsDetail", insight.count ?? Int(insight.primaryValue ?? 0), thread)
        case .highCacheReuse:
            return ModexStrings.format("insights.highCacheReuseDetail", percentText(insight.primaryValue), thread)
        case .scanSlow:
            return ModexStrings.format("insights.scanSlowDetail", formatDuration(insight.primaryValue ?? 0))
        case .cacheCold:
            return ModexStrings.text("insights.cacheColdDetail")
        }
    }

    private var source: String {
        if let agentResult = insight.agentResult {
            return agentResult.suggestedAction
        }
        if let projectTitle = insight.projectTitle {
            return projectTitle
        }
        if let sourcePath = insight.sourcePath {
            return sourcePath
        }
        return ModexStrings.text("insights.global")
    }

    @ViewBuilder
    private var tertiaryLine: some View {
        if insight.agentResult != nil {
            Text(nextActionText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(source)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedText.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var helpText: String {
        [
            title,
            detail,
            source,
            statusText,
        ]
        .joined(separator: "\n")
    }

    private var severityColor: Color {
        switch insight.severity {
        case .info:
            return .teal
        case .notice:
            return ModexTheme.noticeContextColor
        case .warning:
            return ModexTheme.warningContextColor
        case .critical:
            return ModexTheme.criticalContextColor
        }
    }

    private var statusColor: Color {
        switch insight.status {
        case .deterministic:
            return .teal
        case .agentUnavailable:
            return ModexTheme.noticeContextColor
        case .agentRunning:
            return palette.accent
        case .agentGenerated:
            return .teal
        case .agentFailed:
            return ModexTheme.criticalContextColor
        case .stale:
            return palette.mutedText
        }
    }

    private var statusText: String {
        switch insight.status {
        case .deterministic:
            return ModexStrings.text("insights.statusLocal")
        case .agentUnavailable:
            return ModexStrings.text("insights.statusAgent")
        case .agentRunning:
            return ModexStrings.text("insights.statusRunning")
        case .agentGenerated:
            return ModexStrings.text("insights.statusCodex")
        case .agentFailed:
            return ModexStrings.text("insights.statusFailed")
        case .stale:
            return ModexStrings.text("insights.statusStale")
        }
    }

    @ViewBuilder
    private var insightAction: some View {
        if insight.status == .agentRunning {
            ProgressView()
                .controlSize(.small)
        } else {
            Button {
                onRequestAgentInsight(insight)
            } label: {
                Label(actionTitle, systemImage: "sparkles")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canRequestAgentInsights ? palette.accent : palette.mutedText)
                    .frame(width: 28, height: 28)
                    .background(canRequestAgentInsights ? palette.surfaceHighlight : palette.surface.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canRequestAgentInsights)
            .help(actionHelp)
        }
    }

    private var actionTitle: String {
        insight.agentResult == nil
            ? ModexStrings.text("insights.analyze")
            : ModexStrings.text("insights.rerun")
    }

    private var actionHelp: String {
        canRequestAgentInsights
            ? actionTitle
            : ModexStrings.text("insights.connectFirst")
    }

    private var nextActionText: String {
        guard let agentResult = insight.agentResult else {
            return source
        }
        return ModexStrings.format("insights.nextAction", agentResult.suggestedAction)
    }
}

private struct ThreadDiagnosticsTab: View {
    let metrics: ScanMetrics?
    @Environment(\.modexPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let metrics {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ThreadMetricCardView(card: ThreadMetricCard(title: ModexStrings.text("instrumentation.duration"), value: formatDuration(metrics.durationSeconds), detail: metrics.parserMode))
                        ThreadMetricCardView(card: ThreadMetricCard(title: ModexStrings.text("instrumentation.read"), value: formatBytes(metrics.bytesRead), detail: "\(metrics.filesParsed)/\(metrics.filesSelected)"))
                        ThreadMetricCardView(card: ThreadMetricCard(title: ModexStrings.text("instrumentation.cache"), value: cacheValue(metrics), detail: ModexStrings.format("detail.cacheSaved", formatBytes(metrics.cacheBytesSaved))))
                        ThreadMetricCardView(card: ThreadMetricCard(title: ModexStrings.text("instrumentation.concurrency"), value: concurrencyValue(metrics), detail: ModexStrings.format("detail.chunkLine", formatBytes(metrics.chunkSizeBytes), formatBytes(metrics.maximumLineBufferBytes))))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(ModexStrings.text("instrumentation.slowestFiles"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)

                        VStack(spacing: 0) {
                            ForEach(slowestFiles(metrics), id: \.fileURL) { file in
                                HStack(spacing: 12) {
                                    Text(file.threadName ?? fileName(file.fileURL))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(formatDuration(file.durationSeconds))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.text)
                                    Text(formatBytes(file.bytesRead))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.secondaryText)
                                        .frame(width: 88, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .help(file.fileURL.path)
                            }
                        }
                        .background(palette.sidebar.opacity(0.66))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    Text(ModexStrings.text("instrumentation.noCompletedRead"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .padding(20)
                }
            }
            .padding(22)
        }
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

    private func slowestFiles(_ metrics: ScanMetrics) -> [FileScanMetrics] {
        Array(
            metrics.fileMetrics
                .filter { $0.cacheHit == false }
                .sorted { $0.durationSeconds > $1.durationSeconds }
                .prefix(8)
        )
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.sidebar.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DashboardMetricGrid: View {
    let summary: ModexSummary?
    @Environment(\.modexPalette) private var palette

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            DashboardMetricTile(
                symbol: "rectangle.stack",
                title: ModexStrings.text("dashboard.activeThreads"),
                value: summary.map { "\($0.sessionsScanned)" } ?? "0",
                detail: ModexStrings.text("dashboard.scanned")
            )
            DashboardMetricTile(
                symbol: "gauge.medium",
                title: ModexStrings.text("dashboard.highestContext"),
                value: percentText(highestContext),
                detail: ModexStrings.text("dashboard.watch")
            )
            DashboardMetricTile(
                symbol: "sum",
                title: ModexStrings.text("column.total.title"),
                value: summary.map { compact($0.totalTokens) } ?? "0",
                detail: exactTotalText
            )
            DashboardMetricTile(
                symbol: "xmark.octagon",
                title: ModexStrings.text("dashboard.failures"),
                value: "\(failedCommands)",
                detail: ModexStrings.text("dashboard.commandExits")
            )
        }
    }

    private var sessions: [SessionSnapshot] {
        summary?.sessions ?? []
    }

    private var highestContext: Double? {
        sessions.compactMap(\.contextUsagePercent).max()
    }

    private var failedCommands: Int {
        sessions.reduce(0) { $0 + $1.failedCommandEvents }
    }

    private var exactTotalText: String {
        guard let totalTokens = summary?.totalTokens, totalTokens > 0 else {
            return ModexStrings.text("overview.noMetrics")
        }
        return totalTokens.formatted()
    }
}

private struct DashboardMetricTile: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String

    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 24, height: 24)
                .background(palette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(height: 60)
        .background(palette.sidebar.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.surface.opacity(0.45), lineWidth: 0.7)
        }
    }
}

private struct DashboardInsightStrip: View {
    let summary: ModexSummary?
    let metrics: ScanMetrics?
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(insights) { insight in
                HStack(spacing: 5) {
                    Text(insight.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.mutedText)
                    Text(insight.value)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(palette.sidebar.opacity(0.58))
                .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var sessions: [SessionSnapshot] {
        summary?.sessions ?? []
    }

    private var insights: [DashboardInsight] {
        [
            DashboardInsight(
                id: "growth",
                title: ModexStrings.text("dashboard.fastestGrowth"),
                value: fastestGrowth == 0 ? ModexStrings.text("overview.contextUnavailable") : "+\(compact(fastestGrowth))"
            ),
            DashboardInsight(
                id: "slowest",
                title: ModexStrings.text("dashboard.slowestTurn"),
                value: slowestTurn.map(millisecondsText) ?? ModexStrings.text("overview.contextUnavailable")
            ),
            DashboardInsight(
                id: "cached",
                title: ModexStrings.text("dashboard.cachedInput"),
                value: percentText(averageCachedInput)
            ),
            DashboardInsight(
                id: "files",
                title: ModexStrings.text("dashboard.filesChanged"),
                value: "\(changedFiles)"
            ),
            DashboardInsight(
                id: "cache",
                title: ModexStrings.text("instrumentation.cache"),
                value: cacheText
            ),
        ]
    }

    private var fastestGrowth: Int {
        sessions.map(\.latestContextGrowthTokens).max() ?? 0
    }

    private var slowestTurn: Int? {
        sessions.compactMap(\.lastTurnDurationMilliseconds).max()
    }

    private var averageCachedInput: Double? {
        let values = sessions.compactMap(\.cachedInputPercent)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private var changedFiles: Int {
        sessions.reduce(0) { $0 + $1.changedFileEvents }
    }

    private var cacheText: String {
        guard let metrics, metrics.cacheEnabled, metrics.filesSelected > 0 else {
            return ModexStrings.text("instrumentation.cacheOff")
        }
        return "\(Int((Double(metrics.cacheHits) / Double(metrics.filesSelected) * 100).rounded()))%"
    }
}

private struct DashboardInsight: Identifiable {
    let id: String
    let title: String
    let value: String
}

private struct DashboardHistoryPanel: View {
    let summary: ModexSummary?
    let history: ModexHistorySnapshot?
    let thresholds: ModexContextThresholds

    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            TrendMiniCard(
                title: ModexStrings.text("history.contextPressure"),
                value: percentText(highestContextSession?.contextUsagePercent),
                detail: highestContextSession.map { $0.threadName ?? projectTitle(for: $0) }
                    ?? ModexStrings.text("overview.noMetrics"),
                values: highestContextSession.map { contextTrendValues(for: $0, history: history) } ?? [],
                color: contextColor
            )

            TrendMiniCard(
                title: ModexStrings.text("history.tokenGrowth"),
                value: topTokenSession.map { compact($0.totalTokens) } ?? "0",
                detail: topTokenSession.map { $0.threadName ?? projectTitle(for: $0) }
                    ?? ModexStrings.text("overview.noMetrics"),
                values: topTokenSession.map { totalTrendValues(for: $0, history: history) } ?? [],
                color: palette.accent
            )

            TrendMiniCard(
                title: ModexStrings.text("history.scanHealth"),
                value: scanDurationText,
                detail: cacheDetail,
                values: history?.scanSamples.map(\.durationSeconds) ?? [],
                color: palette.secondaryText
            )
        }
    }

    private var sessions: [SessionSnapshot] {
        summary?.sessions ?? []
    }

    private var highestContextSession: SessionSnapshot? {
        sessions.max { ($0.contextUsagePercent ?? -1) < ($1.contextUsagePercent ?? -1) }
    }

    private var topTokenSession: SessionSnapshot? {
        sessions.max { $0.totalTokens < $1.totalTokens }
    }

    private var contextColor: Color {
        ModexTheme.contextColor(
            for: highestContextSession?.contextUsagePercent ?? 0,
            thresholds: thresholds
        )
    }

    private var scanDurationText: String {
        guard let seconds = summary?.scanMetrics?.durationSeconds else {
            return ModexStrings.text("overview.contextUnavailable")
        }
        return formatDuration(seconds)
    }

    private var cacheDetail: String {
        guard let metrics = summary?.scanMetrics, metrics.cacheEnabled, metrics.filesSelected > 0 else {
            return ModexStrings.text("instrumentation.cacheOff")
        }
        let hitRate = Int((Double(metrics.cacheHits) / Double(metrics.filesSelected) * 100).rounded())
        return ModexStrings.format("history.cacheHitRate", hitRate)
    }
}

private struct TrendMiniCard: View {
    let title: String
    let value: String
    let detail: String
    let values: [Double]
    let color: Color

    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            MiniSparkline(values: values, color: color, fill: true)
                .frame(width: 86, height: 34)
                .opacity(values.count > 1 ? 1 : 0.22)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .background(palette.sidebar.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.surface.opacity(0.42), lineWidth: 0.7)
        }
    }
}

private struct DashboardTopThreadsPanel: View {
    let sessions: [IndexedSession]
    let thresholds: ModexContextThresholds
    let sessionDetailHoverDelayMilliseconds: Int

    @Environment(\.modexPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ModexStrings.text("dashboard.topThreads"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(ModexStrings.text("dashboard.rankHint"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.mutedText)
            }

            VStack(spacing: 0) {
                if sessions.isEmpty {
                    Text(ModexStrings.text("overview.noMetrics"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    ForEach(sessions) { indexedSession in
                        DashboardThreadRow(
                            session: indexedSession.session,
                            index: indexedSession.index,
                            thresholds: thresholds,
                            sessionDetailHoverDelayMilliseconds: sessionDetailHoverDelayMilliseconds
                        )
                    }
                }
            }
            .background(palette.sidebar.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surface.opacity(0.45), lineWidth: 0.7)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct DashboardThreadRow: View {
    let session: SessionSnapshot
    let index: Int
    let thresholds: ModexContextThresholds
    let sessionDetailHoverDelayMilliseconds: Int

    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sessionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sessionDetailTip(sessionTooltip, delayMilliseconds: sessionDetailHoverDelayMilliseconds)

            ContextMeter(
                percent: session.contextUsagePercent,
                thresholds: thresholds,
                accessibilityLabel: contextStatusText
            )
            .frame(width: 106, alignment: .trailing)

            dashboardValue(compact(session.totalTokens), label: ModexStrings.text("column.total.title"))
                .frame(width: 82, alignment: .trailing)
            dashboardValue(cachedText, label: ModexStrings.text("dashboard.cachedInput"))
                .frame(width: 78, alignment: .trailing)
            dashboardValue(activityText, label: ModexStrings.text("dashboard.activity"))
                .frame(width: 96, alignment: .trailing)
            UpdatedCell(updatedAt: session.updatedAt)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.035) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.surface.opacity(0.26))
                .frame(height: 1)
        }
    }

    private func dashboardValue(_ value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
        }
    }

    private var sessionTitle: String {
        if let threadName = session.threadName, threadName.isEmpty == false {
            return threadName
        }
        return projectTitle(for: session)
    }

    private var subtitle: String {
        [
            projectTitle(for: session),
            modeValue(session.model),
            modeValue(session.reasoningEffort),
            speedText(for: session.realtimeActive),
        ]
        .filter { $0 != ModexStrings.text("overview.contextUnavailable") }
        .joined(separator: " · ")
    }

    private var cachedText: String {
        percentText(session.cachedInputPercent)
    }

    private var activityText: String {
        if session.failedCommandEvents > 0 {
            return ModexStrings.format("dashboard.failedShort", session.failedCommandEvents)
        }
        if session.changedFileEvents > 0 {
            return ModexStrings.format("dashboard.filesShort", session.changedFileEvents)
        }
        if session.commandEvents > 0 {
            return ModexStrings.format("dashboard.commandsShort", session.commandEvents)
        }
        return ModexStrings.text("dashboard.clean")
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
        rows.append(contextStatusText)
        rows.append(ModexStrings.format("dashboard.cachedInputDetail", cachedText))
        rows.append(ModexStrings.format("dashboard.turnsDetail", session.completedTurns))
        rows.append(ModexStrings.format("dashboard.commandsDetail", session.commandEvents, session.failedCommandEvents))
        rows.append(ModexStrings.format("dashboard.filesDetail", session.changedFileEvents))
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
            return 92
        case .median:
            return 94
        case .average:
            return 90
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
    let history: ModexHistorySnapshot?
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
                trendValues: contextTrendValues(for: session, history: history),
                accessibilityLabel: contextStatusText
            )
                .frame(width: OverviewColumn.context.width, alignment: .trailing)
            numberCell(
                compact(session.totalTokens),
                exactValue: exactTotalTokensValue,
                accessibilityLabel: exactTotalTokensText,
                trendValues: totalTrendValues(for: session, history: history)
            )
                .frame(width: OverviewColumn.total.width, alignment: .trailing)
            numberCell(
                compact(session.medianTurnTokens),
                exactValue: exactMedianTurnTokensValue,
                accessibilityLabel: exactMedianTurnTokensText,
                trendValues: medianTurnTrendValues(for: session, history: history)
            )
                .frame(width: OverviewColumn.median.width, alignment: .trailing)
            numberCell(
                compact(session.averageTurnTokens),
                exactValue: exactAverageTurnTokensValue,
                accessibilityLabel: exactAverageTurnTokensText,
                trendValues: averageTurnTrendValues(for: session, history: history)
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
    private func numberCell(
        _ value: String,
        exactValue: String? = nil,
        accessibilityLabel: String? = nil,
        trendValues: [Double] = []
    ) -> some View {
        if let exactValue {
            ExactNumberCell(
                value: value,
                exactValue: exactValue,
                accessibilityLabel: accessibilityLabel ?? exactValue,
                trendValues: trendValues
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
    let trendValues: [Double]

    @Environment(\.modexPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            if trendValues.count > 1 {
                MiniSparkline(values: trendValues, color: palette.accent.opacity(0.78), fill: false)
                    .frame(width: 28, height: 14)
                    .opacity(isHovered ? 0.35 : 0.78)
            }

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
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(isHovered ? 1 : 0)
                    .scaleEffect(isHovered ? 1 : 0.96, anchor: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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

    fileprivate static func exactText(for date: Date) -> String {
        exactFormatter.string(from: date)
    }
}

private struct ContextMeter: View {
    let percent: Double?
    let thresholds: ModexContextThresholds
    var trendValues: [Double] = []
    let accessibilityLabel: String
    @Environment(\.modexPalette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            if trendValues.count > 1 {
                MiniSparkline(
                    values: trendValues,
                    color: contextColor.opacity(0.82),
                    fill: false
                )
                .frame(width: 28, height: 14)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.surface.opacity(0.32))
                    if let percent {
                        Capsule()
                            .fill(contextColor.opacity(0.90))
                            .frame(width: max(3, proxy.size.width * min(max(percent, 0), 100) / 100))
                    }
                }
            }
            .frame(width: trendValues.count > 1 ? 24 : 36, height: 6)

            Text(percent.map { "\(Int($0.rounded()))%" } ?? ModexStrings.text("overview.contextUnavailable"))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var contextColor: Color {
        ModexTheme.contextColor(for: percent ?? 0, thresholds: thresholds)
    }
}

private struct MiniSparkline: View {
    let values: [Double]
    let color: Color
    var fill = false

    @Environment(\.modexPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                if fill, points.count > 1 {
                    filledPath(points: points, size: proxy.size)
                        .fill(color.opacity(0.13))
                }

                sparkPath(points: points)
                    .stroke(
                        values.count > 1 ? color : palette.surface.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let cleanValues = values.filter { $0.isFinite }
        guard cleanValues.count > 1 else {
            return [
                CGPoint(x: 0, y: size.height / 2),
                CGPoint(x: size.width, y: size.height / 2),
            ]
        }

        let minValue = cleanValues.min() ?? 0
        let maxValue = cleanValues.max() ?? minValue
        let span = max(maxValue - minValue, 0.0001)
        let step = size.width / CGFloat(max(cleanValues.count - 1, 1))

        return cleanValues.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let normalized = (value - minValue) / span
            let y = size.height - CGFloat(normalized) * (size.height - 4) - 2
            return CGPoint(x: x, y: y)
        }
    }

    private func sparkPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func filledPath(points: [CGPoint], size: CGSize) -> Path {
        var path = sparkPath(points: points)
        if let last = points.last, let first = points.first {
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.addLine(to: CGPoint(x: first.x, y: size.height))
            path.closeSubpath()
        }
        return path
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
    let intelligenceConnectionState: ModexIntelligenceConnectionState
    let onOpenCodexFolder: () -> Void
    let onFlushScanCache: () -> Void
    let onTestIntelligenceConnection: () -> Void
    let onFlushAgentInsightCache: () -> Void
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
                    PaletteSegmentedOption(value: 3, title: ModexStrings.text("config.intelligence")),
                    PaletteSegmentedOption(value: 4, title: ModexStrings.text("config.expert")),
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
                    case 3:
                        intelligenceSettings
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
        .frame(width: 560, height: 460, alignment: .top)
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

    private var intelligenceSettings: some View {
        settingsSection(
            title: ModexStrings.text("config.intelligenceSection"),
            symbol: "sparkles",
            tint: .cyan
        ) {
            settingsRow(
                icon: "sparkles",
                tint: .cyan,
                title: ModexStrings.text("config.intelligenceEnabled"),
                detail: ModexStrings.text("config.intelligenceEnabledHelp")
            ) {
                PaletteToggle(
                    isOn: Binding(
                        get: { settings.intelligence.enabled },
                        set: { settings = updatedSettings(intelligenceEnabled: $0) }
                    ),
                    label: ModexStrings.text("config.intelligenceEnabled")
                )
            }

            settingsRow(
                icon: "point.3.connected.trianglepath.dotted",
                tint: .cyan,
                title: ModexStrings.text("config.intelligenceProvider"),
                detail: ModexStrings.text("config.intelligenceProviderHelp")
            ) {
                PaletteSegmentedControl(
                    options: ModexIntelligenceProvider.allCases.map {
                        PaletteSegmentedOption(value: $0, title: $0.title)
                    },
                    selection: Binding(
                        get: { settings.intelligence.provider },
                        set: { settings = updatedSettings(intelligenceProvider: $0) }
                    )
                )
                .frame(width: 220)
            }

            settingsRow(
                icon: "terminal",
                tint: .cyan,
                title: ModexStrings.text("config.intelligenceExecutable"),
                detail: ModexStrings.text("config.intelligenceExecutableHelp")
            ) {
                TextField(
                    ModexStrings.text("config.intelligenceExecutable"),
                    text: Binding(
                        get: { settings.intelligence.codexExecutablePath },
                        set: { settings = updatedSettings(intelligenceCodexExecutablePath: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 9)
                .frame(width: 220, height: 30)
                .background(palette.sidebar.opacity(0.66))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.surface.opacity(0.45), lineWidth: 0.7)
                }
            }

            stepperRow(
                icon: "timer",
                tint: .cyan,
                title: ModexStrings.text("config.intelligenceTimeout"),
                detail: ModexStrings.text("config.intelligenceTimeoutHelp"),
                value: Binding(
                    get: { settings.intelligence.timeoutSeconds },
                    set: { settings = updatedSettings(intelligenceTimeoutSeconds: $0) }
                ),
                range: 5...180,
                step: 5,
                suffix: " s"
            )

            settingsRow(
                icon: intelligenceStatusIcon,
                tint: intelligenceStatusColor,
                title: ModexStrings.text("config.intelligenceStatus"),
                detail: intelligenceStatusDetail
            ) {
                HStack(spacing: 8) {
                    Text(intelligenceStatusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(intelligenceStatusColor)
                        .lineLimit(1)
                        .frame(width: 92, alignment: .trailing)

                    Button {
                        onTestIntelligenceConnection()
                    } label: {
                        Text(ModexStrings.text("config.testConnection"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(canTestIntelligence ? Color.white : palette.mutedText)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(canTestIntelligence ? palette.accent : palette.surface.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTestIntelligence)
                }
            }

            settingsRow(
                icon: "trash",
                tint: .cyan,
                title: ModexStrings.text("config.flushInsightCache"),
                detail: ModexStrings.text("config.flushInsightCacheHelp")
            ) {
                IconButton(
                    symbol: "trash",
                    label: ModexStrings.text("config.flushInsightCache"),
                    action: onFlushAgentInsightCache
                )
            }
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
        intelligenceEnabled: Bool? = nil,
        intelligenceProvider: ModexIntelligenceProvider? = nil,
        intelligenceCodexExecutablePath: String? = nil,
        intelligenceTimeoutSeconds: Int? = nil,
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
        if let intelligenceEnabled {
            next.intelligence.enabled = intelligenceEnabled
            if intelligenceEnabled, next.intelligence.provider == .off {
                next.intelligence.provider = .localCodex
            }
            if intelligenceEnabled == false {
                next.intelligence.provider = .off
            }
        }
        if let intelligenceProvider {
            next.intelligence.provider = intelligenceProvider
            next.intelligence.enabled = intelligenceProvider != .off
        }
        if let intelligenceCodexExecutablePath {
            next.intelligence.codexExecutablePath = intelligenceCodexExecutablePath
        }
        if let intelligenceTimeoutSeconds {
            next.intelligence.timeoutSeconds = intelligenceTimeoutSeconds
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

    private var canTestIntelligence: Bool {
        settings.intelligence.enabled && settings.intelligence.provider != .off
    }

    private var intelligenceStatusIcon: String {
        switch intelligenceConnectionState {
        case .off:
            return "power"
        case .unknown:
            return "questionmark.circle"
        case .testing:
            return "hourglass"
        case .connected:
            return "checkmark.seal"
        case .limited:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.octagon"
        }
    }

    private var intelligenceStatusColor: Color {
        switch intelligenceConnectionState {
        case .off, .unknown:
            return palette.mutedText
        case .testing:
            return ModexTheme.noticeContextColor
        case .connected:
            return .teal
        case .limited:
            return ModexTheme.noticeContextColor
        case .failed:
            return ModexTheme.criticalContextColor
        }
    }

    private var intelligenceStatusTitle: String {
        switch intelligenceConnectionState {
        case .off:
            return ModexStrings.text("config.intelligenceStatusOff")
        case .unknown:
            return ModexStrings.text("config.intelligenceStatusUnknown")
        case .testing:
            return ModexStrings.text("config.intelligenceStatusTesting")
        case .connected:
            return ModexStrings.text("config.intelligenceStatusConnected")
        case .limited:
            return ModexStrings.text("config.intelligenceStatusLimited")
        case .failed:
            return ModexStrings.text("config.intelligenceStatusFailed")
        }
    }

    private var intelligenceStatusDetail: String {
        switch intelligenceConnectionState {
        case .off:
            return ModexStrings.text("config.intelligenceStatusOffHelp")
        case .unknown:
            return ModexStrings.text("config.intelligenceStatusUnknownHelp")
        case .testing:
            return ModexStrings.text("config.intelligenceStatusTestingHelp")
        case .connected(let date):
            return ModexStrings.format("config.intelligenceStatusConnectedHelp", UpdatedCell.exactText(for: date))
        case .limited(let message):
            return message.isEmpty ? ModexStrings.text("config.intelligenceStatusLimitedHelp") : message
        case .failed(let message):
            return message.isEmpty ? ModexStrings.text("config.intelligenceStatusFailedHelp") : message
        }
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

func percentText(_ value: Double?) -> String {
    guard let value else {
        return ModexStrings.text("overview.contextUnavailable")
    }
    return "\(Int(value.rounded()))%"
}

func millisecondsText(_ milliseconds: Int?) -> String {
    guard let milliseconds else {
        return ModexStrings.text("overview.contextUnavailable")
    }
    if milliseconds < 1_000 {
        return "\(milliseconds)ms"
    }
    if milliseconds < 60_000 {
        return String(format: "%.1fs", Double(milliseconds) / 1_000)
    }
    let minutes = milliseconds / 60_000
    let seconds = (milliseconds % 60_000) / 1_000
    return "\(minutes)m \(seconds)s"
}

func average(_ values: [Double]) -> Double? {
    guard values.isEmpty == false else {
        return nil
    }
    return values.reduce(0, +) / Double(values.count)
}

func median(_ values: [Int]) -> Int? {
    guard values.isEmpty == false else {
        return nil
    }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func contextTrendValues(
    for session: SessionSnapshot,
    history: ModexHistorySnapshot?,
    limit: Int = 14
) -> [Double] {
    let historyValues = history?.samples(for: session)
        .compactMap(\.contextPercent) ?? []
    if historyValues.count > 1 {
        return Array(historyValues.suffix(limit))
    }

    let values = session.tokenEvents.compactMap { event -> Double? in
        guard let window = event.modelContextWindow, window > 0 else {
            return nil
        }
        return Double(event.lastUsage.inputTokens) / Double(window) * 100
    }
    return Array(values.suffix(limit))
}

func totalTrendValues(
    for session: SessionSnapshot,
    history: ModexHistorySnapshot?,
    limit: Int = 14
) -> [Double] {
    let historyValues = history?.samples(for: session)
        .map { Double($0.totalTokens) } ?? []
    if historyValues.count > 1 {
        return Array(historyValues.suffix(limit))
    }

    let values = session.tokenEvents
        .map { Double($0.totalUsage.totalTokens) }
        .filter { $0 > 0 }
    return Array(values.suffix(limit))
}

func medianTurnTrendValues(
    for session: SessionSnapshot,
    history: ModexHistorySnapshot?,
    limit: Int = 14
) -> [Double] {
    let values = history?.samples(for: session)
        .map { Double($0.medianTurnTokens) }
        .filter { $0 > 0 } ?? []
    return Array(values.suffix(limit))
}

func averageTurnTrendValues(
    for session: SessionSnapshot,
    history: ModexHistorySnapshot?,
    limit: Int = 14
) -> [Double] {
    let values = history?.samples(for: session)
        .map { Double($0.averageTurnTokens) }
        .filter { $0 > 0 } ?? []
    return Array(values.suffix(limit))
}

func durationTrendValues(
    for session: SessionSnapshot,
    history: ModexHistorySnapshot?,
    limit: Int = 14
) -> [Double] {
    let historyValues = history?.samples(for: session)
        .compactMap(\.lastTurnDurationMilliseconds)
        .map(Double.init) ?? []
    if historyValues.count > 1 {
        return Array(historyValues.suffix(limit))
    }
    return Array(session.turnDurationsMilliseconds.map(Double.init).suffix(limit))
}

func failedCommandTrendValues(
    for session: SessionSnapshot,
    history: ModexHistorySnapshot?,
    limit: Int = 14
) -> [Double] {
    let values = history?.samples(for: session)
        .map { Double($0.failedCommandEvents) } ?? []
    if values.count > 1 {
        return Array(values.suffix(limit))
    }
    return session.failedCommandEvents > 0 ? [0, Double(session.failedCommandEvents)] : []
}

func dashboardAttentionScore(_ session: SessionSnapshot) -> Double {
    var score = 0.0
    score += (session.contextUsagePercent ?? 0) * 2.4
    score += min(Double(session.latestContextGrowthTokens) / 1_000, 60)
    score += Double(session.failedCommandEvents) * 26
    score += Double(session.changedFileEvents) * 2
    score += min(Double(session.totalTokens) / 1_000_000, 30)

    if let lastTurnDuration = session.lastTurnDurationMilliseconds {
        score += min(Double(lastTurnDuration) / 10_000, 24)
    }

    if let updatedAt = session.updatedAt {
        let age = max(0, Date().timeIntervalSince(updatedAt))
        if age < 60 * 60 {
            score += 34
        } else if age < 24 * 60 * 60 {
            score += 20
        } else if age < 7 * 24 * 60 * 60 {
            score += 8
        }
    }

    return score
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
