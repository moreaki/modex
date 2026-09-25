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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ModexStrings.text("account.usageTitle")).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let date = metadata.usageObservedAt {
                    Text(ModexStrings.format("account.observed", date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
                }
            }
            HStack(spacing: 24) {
                metric("account.lifetime", metadata.usage?.summary?.lifetimeTokens)
                metric("account.peakDaily", metadata.usage?.summary?.peakDailyTokens)
            }
            DisclosureGroup(ModexStrings.text("account.moreStatistics")) {
                VStack(alignment: .leading, spacing: 8) {
                    metric("account.longestTurnSeconds", metadata.usage?.summary?.longestRunningTurnSec)
                    metric("account.currentStreakDays", metadata.usage?.summary?.currentStreakDays)
                    metric("account.longestStreakDays", metadata.usage?.summary?.longestStreakDays)
                }.padding(.vertical, 6)
            }.font(.system(size: 11))
            if metadata.usageRefreshFailed {
                Text(ModexStrings.text("account.usageStale"))
                    .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
            }
            // A dated, exact table is more useful here than an unlabeled micro-chart.
            if let days = metadata.usage?.recentDays, !days.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(days.suffix(7).enumerated()), id: \.offset) { _, day in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.startDate).foregroundStyle(palette.secondaryText)
                            Text(day.tokens.formatted()).monospacedDigit()
                        }
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text(ModexStrings.text("account.usageSource"))
                .font(.system(size: 10)).foregroundStyle(palette.secondaryText)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
    private func metric(_ key: String, _ value: Int?) -> some View {
        HStack(spacing: 8) {
            Text(ModexStrings.text(key)).foregroundStyle(palette.secondaryText)
            Text(value?.formatted() ?? ModexStrings.text("overview.contextUnavailable")).monospacedDigit()
        }.font(.system(size: 12))
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
