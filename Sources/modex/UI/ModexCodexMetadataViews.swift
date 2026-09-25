import ModexCore
import SwiftUI

struct CodexAccountMetadataView: View {
    let metadata: CodexMetadataSnapshot
    @State private var showingDetails = false
    @Environment(\.modexPalette) private var palette

    var body: some View {
        Button { showingDetails.toggle() } label: {
            HStack {
                Label(metadata.limits?.generalBucket?.planType == nil ? ModexStrings.text("account.title") : plan,
                      systemImage: "person.crop.circle")
                Text(availability)
                Spacer()
                if let balance = metadata.limits?.generalBucket?.credits?.balance {
                    Text(ModexStrings.format("account.credits", balance))
                }
                if let count = metadata.limits?.rateLimitResetCredits?.availableCount {
                    Text(ModexStrings.format("account.resetCredits", count))
                }
                Image(systemName: "info.circle")
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(palette.secondaryText)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetails) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(ModexStrings.text("account.title")).font(.headline)
                    HStack {
                        Text(ModexStrings.text("account.plan")).foregroundStyle(palette.secondaryText)
                        Spacer()
                        Text(plan).fontWeight(.semibold)
                    }
                    Text(availability).foregroundStyle(palette.secondaryText)
                    if let date = metadata.limitsObservedAt {
                        Text(ModexStrings.format("account.observed", ModexAccountPresentation.date(date)))
                            .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                    }
                    Divider()
                    ForEach(buckets, id: \.0) { key, bucket in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(key == "codex" ? ModexStrings.text("account.planLimits") : bucket.limitName ?? key)
                                .font(.subheadline.bold())
                            if let primary = bucket.primary { window(primary) }
                            if let secondary = bucket.secondary { window(secondary) }
                            if let reason = bucket.reachedReasonKey { Text(ModexStrings.text(reason)) }
                            if let reached = bucket.spendControlReached {
                                Text(ModexStrings.text(reached ? "account.spendReached" : "account.spendAvailable"))
                            }
                            if let spend = bucket.individualLimit,
                               let used = spend.used, let limit = spend.limit {
                                Text(ModexStrings.format("account.spend", used, limit))
                            }
                            if key != "codex", let credits = bucket.credits {
                                if credits.unlimited == true {
                                    Text(ModexStrings.text("account.unlimitedCredits"))
                                } else if let balance = credits.balance {
                                    Text(ModexStrings.format("account.credits", balance))
                                }
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Text(ModexStrings.text("account.creditBalance")).fontWeight(.semibold)
                        Spacer()
                        if metadata.limits?.generalBucket?.credits?.unlimited == true {
                            Text(ModexStrings.text("account.unlimitedCredits"))
                        } else {
                            Text(metadata.limits?.generalBucket?.credits?.balance ?? ModexStrings.text("overview.contextUnavailable"))
                                .monospacedDigit()
                        }
                    }
                    Divider()
                    resetCredits
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ModexStrings.text("account.readOnly"))
                        Text(ModexStrings.text("account.billingUnavailable"))
                    }
                    .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                }
                .font(.system(size: 12))
                .padding(20)
            }
            .frame(width: 420, height: 520)
            .background(palette.background)
            .foregroundStyle(palette.text)
        }
    }

    private var plan: String { ModexAccountPresentation.plan(metadata.limits?.generalBucket?.planType) }

    private var resetCredits: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ModexStrings.text("account.usageResets")).fontWeight(.semibold)
                Spacer()
                Text(metadata.limits?.rateLimitResetCredits?.availableCount.map {
                    ModexStrings.format("account.availableResets", $0)
                } ?? ModexStrings.text("overview.contextUnavailable"))
            }
            if let credits = metadata.limits?.rateLimitResetCredits?.availableDetails {
                ForEach(credits) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ModexAccountPresentation.resetTitle(credit))
                        Text(credit.expiresAt.map {
                            ModexStrings.format("account.expires", ModexAccountPresentation.date(Date(timeIntervalSince1970: Double($0))))
                        } ?? ModexStrings.text("account.noExpiry"))
                        .font(.system(size: 11)).foregroundStyle(palette.secondaryText)
                    }
                }
                if credits.count < (metadata.limits?.rateLimitResetCredits?.availableCount ?? 0) {
                    Text(ModexStrings.text("account.partialResets"))
                        .font(.system(size: 11)).foregroundStyle(palette.secondaryText)
                }
            } else if metadata.limits?.rateLimitResetCredits?.availableCount != 0 {
                Text(ModexStrings.text("account.resetDetailsUnavailable"))
                    .font(.system(size: 11)).foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var availability: String {
        if metadata.refreshFailed { return ModexStrings.text("account.stale") }
        switch metadata.limits?.ordinaryUsageAllowed {
        case true: return ModexStrings.text("account.allowed")
        case false: return ModexStrings.text("account.blocked")
        case nil: return ModexStrings.text("account.unknown")
        }
    }
    private var buckets: [(String, CodexAccountLimits.Bucket)] {
        if let buckets = metadata.limits?.rateLimitsByLimitId, !buckets.isEmpty {
            return buckets.sorted { ($0.key == "codex" ? 0 : 1, $0.key) < ($1.key == "codex" ? 0 : 1, $1.key) }.map { ($0.key, $0.value) }
        }
        guard let bucket = metadata.limits?.rateLimits else { return [] }
        return [(bucket.limitId ?? "Codex", bucket)]
    }
    private func window(_ window: CodexAccountLimits.Window) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ModexAccountPresentation.windowTitle(window.windowDurationMins))
                Spacer()
                Text(ModexStrings.format("account.remaining", ModexStrings.decimal(window.value.leftPercent, maximumFractionDigits: 1)))
                    .monospacedDigit()
            }
            ProgressView(value: window.value.leftPercent, total: 100).tint(palette.accent)
                .accessibilityLabel(Text(ModexAccountPresentation.windowTitle(window.windowDurationMins)))
            if let date = window.value.resetsAt {
                Text(ModexAccountPresentation.resetTime(date))
                    .font(.system(size: 11)).foregroundStyle(palette.secondaryText)
                    .help(ModexAccountPresentation.date(date))
            }
        }
    }
}

struct CodexAccountUsageView: View {
    let metadata: CodexMetadataSnapshot
    @Environment(\.modexPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(ModexStrings.text("account.usageTitle")).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let date = metadata.usageObservedAt {
                    Text(ModexStrings.format("account.observed", ModexAccountPresentation.date(date)))
                        .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                tokenMetric("account.lifetime", metadata.usage?.summary?.lifetimeTokens)
                tokenMetric("account.displayedTotal", metadata.usage?.displayedDaysTotal)
                tokenMetric("account.peakDaily", metadata.usage?.summary?.peakDailyTokens)
            }
            if metadata.usageRefreshFailed {
                Text(ModexStrings.text("account.usageStale"))
                    .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
            }
            if let days = metadata.usage?.displayedDays, let first = days.first, let last = days.last {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(ModexStrings.format("account.reportedDays", days.count)).fontWeight(.medium)
                        Spacer()
                        Text(ModexStrings.format("account.dateRange", first.startDate, last.startDate))
                    }
                    .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(day.startDate).foregroundStyle(palette.secondaryText)
                                    .font(.system(size: 10))
                                Text(exact(day.tokens)).monospacedDigit()
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text(ModexStrings.text("account.dailyCoverage"))
                        .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
            }
            DisclosureGroup(ModexStrings.text("account.moreStatistics")) {
                HStack(alignment: .top, spacing: 24) {
                    statistic("account.longestTurn", ModexAccountPresentation.turnDuration(metadata.usage?.summary?.longestRunningTurnSec))
                    statistic("account.currentStreakDays", exact(metadata.usage?.summary?.currentStreakDays))
                    statistic("account.longestStreakDays", exact(metadata.usage?.summary?.longestStreakDays))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }.font(.system(size: 11))
            Text(ModexStrings.text("account.usageSource"))
                .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func exact(_ value: Int?) -> String {
        value.map { $0.formatted(.number.locale(ModexStrings.localizationLocale)) }
            ?? ModexStrings.text("overview.contextUnavailable")
    }

    private func tokenMetric(_ key: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ModexStrings.text(key)).font(.system(size: 11)).foregroundStyle(palette.secondaryText)
            Text(ModexAccountPresentation.tokenMagnitude(value))
                .font(.system(size: 23, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .help(exact(value))
                .accessibilityLabel(Text(exact(value)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func statistic(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ModexStrings.text(key)).font(.system(size: 10)).foregroundStyle(palette.secondaryText)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodexRuntimeLabel: View {
    let session: SessionSnapshot
    var body: some View {
        if let key = session.runtimeStatus?.presentationKey {
            Text(ModexStrings.text(key))
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
    }
}

func codexMetadataDetails(for session: SessionSnapshot) -> [String] {
    var details: [String] = []
    if let value = session.originator { details.append(ModexStrings.format("metadata.originator", value)) }
    if let value = session.historyMode { details.append(ModexStrings.format("metadata.historyMode", value)) }
    if let value = session.projectID { details.append(ModexStrings.format("metadata.projectID", value)) }
    if session.isPinned { details.append(ModexStrings.text("metadata.pinned")) }
    return details
}

#Preview("Account availability") {
    CodexAccountMetadataView(metadata: CodexMetadataSnapshot()).padding()
}

#Preview("Account usage unavailable") {
    CodexAccountUsageView(metadata: CodexMetadataSnapshot())
}

#Preview("Account usage with gaps") {
    let fixture = #"{"summary":{"lifetimeTokens":25253809535,"peakDailyTokens":1631515240,"longestRunningTurnSec":17385,"currentStreakDays":3,"longestStreakDays":19},"dailyUsageBuckets":[{"startDate":"2026-09-21","tokens":2658340},{"startDate":"2026-09-23","tokens":2084105},{"startDate":"2026-09-24","tokens":22059557},{"startDate":"2026-09-25","tokens":129767909}]}"#
    var metadata = CodexMetadataSnapshot()
    metadata.usage = try? JSONDecoder().decode(CodexAccountUsage.self, from: Data(fixture.utf8))
    return CodexAccountUsageView(metadata: metadata).frame(width: 960)
}
