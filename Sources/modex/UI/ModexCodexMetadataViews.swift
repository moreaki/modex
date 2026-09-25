import ModexCore
import SwiftUI

struct CodexAccountMetadataView: View {
    let metadata: CodexMetadataSnapshot
    @State private var showingDetails = false
    @Environment(\.modexPalette) private var palette

    var body: some View {
        Button { showingDetails.toggle() } label: {
            HStack {
                Label(ModexStrings.text("account.title"), systemImage: "person.crop.circle")
                Text(availability)
                Spacer()
                if let count = metadata.limits?.rateLimitResetCredits?.availableCount {
                    Text(ModexStrings.format("account.resetCredits", count))
                }
                Image(systemName: "info.circle")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.secondaryText)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetails) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ModexStrings.text("account.title")).font(.headline)
                    Text(availability)
                    if let date = metadata.limitsObservedAt {
                        Text(ModexStrings.format("account.observed", date.formatted(date: .abbreviated, time: .shortened)))
                            .foregroundStyle(palette.secondaryText)
                    }
                    ForEach(buckets, id: \.0) { key, bucket in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(bucket.limitName ?? key).font(.subheadline.bold())
                            if let primary = bucket.primary { window(primary) }
                            if let secondary = bucket.secondary { window(secondary) }
                            if let reached = bucket.spendControlReached {
                                Text(ModexStrings.text(reached ? "account.spendReached" : "account.spendAvailable"))
                            }
                            if let spend = bucket.individualLimit,
                               let used = spend.used, let limit = spend.limit {
                                Text(ModexStrings.format("account.spend", used, limit))
                            }
                            if let credits = bucket.credits {
                                if credits.unlimited == true {
                                    Text(ModexStrings.text("account.unlimitedCredits"))
                                } else if let balance = credits.balance {
                                    Text(ModexStrings.format("account.credits", balance))
                                }
                            }
                        }
                    }
                    Text(ModexStrings.text("account.readOnly")).foregroundStyle(palette.secondaryText)
                }
                .font(.system(size: 12))
                .padding(20)
            }
            .frame(width: 390, height: 400)
            .background(palette.background)
            .foregroundStyle(palette.text)
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
            return buckets.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        guard let bucket = metadata.limits?.rateLimits else { return [] }
        return [(bucket.limitId ?? "Codex", bucket)]
    }
    private func window(_ window: CodexAccountLimits.Window) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ModexStrings.format("account.window", window.windowDurationMins.map(String.init) ?? "—",
                                     String(format: "%.1f", window.value.leftPercent)))
            if let date = window.value.resetsAt {
                Text(ModexStrings.format("account.resets", date.formatted(date: .abbreviated, time: .shortened)))
                    .foregroundStyle(palette.secondaryText)
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
