import Foundation

/// Presentation stays outside the transport. The app supplies localized labels;
/// core-only clients get stable localization keys, never invented availability.
public struct CodexAccountReportFormatter: Sendable {
    public static let localizationKeys = [
        "account.title", "account.plan", "account.planLimits", "account.creditBalance", "account.unlimitedCredits",
        "account.allowed", "account.blocked", "account.unknown", "account.usageResets", "account.fullReset",
        "account.resetCredit", "account.noExpiry", "account.resetDetailsUnavailable", "account.partialResets",
        "account.spendReached", "account.spendAvailable", "account.quotaReached", "account.workspaceCreditsDepleted",
        "account.workspaceLimitReached", "account.limitReasonUnknown", "account.usageTitle", "account.lifetime",
        "account.peakDaily", "account.longestTurnSeconds", "account.currentStreakDays", "account.longestStreakDays",
        "account.usageSource", "account.dailyTokens", "account.observationTime", "account.spendUsed", "account.spendLimit",
        "account.weeklyLimit", "account.fiveHourLimit", "account.quotaWindow", "account.remainingPercent", "account.resetDate",
        "overview.contextUnavailable",
    ] + ["pro", "plus", "free", "go", "business", "enterprise", "edu"].map { "account.plan.\($0)" }

    private let labels: [String: String]
    public init(labels: [String: String] = [:]) { self.labels = labels }
    private func text(_ key: String) -> String { labels[key] ?? key }
    private var unavailable: String { text("overview.contextUnavailable") }
    private func date(_ value: Int?) -> String {
        value.map { Date(timeIntervalSince1970: Double($0)).ISO8601Format() } ?? unavailable
    }

    public func lines(limits: CodexAccountLimits?, usage: CodexAccountUsage?, observedAt: Date?) -> [String] {
        var lines: [String] = []
        func add(_ key: String, _ value: String?) { lines.append("\(text(key)): \(value ?? unavailable)") }
        add("account.title", text(limits?.ordinaryUsageAllowed.map { $0 ? "account.allowed" : "account.blocked" } ?? "account.unknown"))
        if let limits {
            let plan = limits.generalBucket?.planType.map { "account.plan.\($0)" }
            add("account.plan", plan.flatMap { Self.localizationKeys.contains($0) ? text($0) : nil })
            var buckets = limits.rateLimitsByLimitId ?? [:]
            if let general = limits.generalBucket { buckets["codex"] = general }
            for id in buckets.keys.sorted(by: { ($0 == "codex" ? 0 : 1, $0) < ($1 == "codex" ? 0 : 1, $1) }) {
                guard let bucket = buckets[id] else { continue }
                lines.append(id == "codex" ? text("account.planLimits") : bucket.limitName ?? id)
                for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                    let key = window.windowDurationMins == 10_080 ? "account.weeklyLimit"
                        : window.windowDurationMins == 300 ? "account.fiveHourLimit" : "account.quotaWindow"
                    lines.append("  \(text(key)): \(text("account.remainingPercent")) \(window.value.leftPercent); \(text("account.resetDate")) \(date(window.resetsAt))")
                }
                if let reason = bucket.reachedReasonKey { lines.append(text(reason)) }
                if let reached = bucket.spendControlReached { lines.append(text(reached ? "account.spendReached" : "account.spendAvailable")) }
                if let spend = bucket.individualLimit {
                    add("account.spendUsed", spend.used)
                    add("account.spendLimit", spend.limit)
                }
                add("account.creditBalance", bucket.credits?.unlimited == true ? text("account.unlimitedCredits") : bucket.credits?.balance)
            }
            add("account.usageResets", limits.rateLimitResetCredits?.availableCount.map(String.init))
            if let credits = limits.rateLimitResetCredits?.availableDetails {
                for credit in credits {
                    let title = text(credit.resetType == "codexRateLimits" ? "account.fullReset" : "account.resetCredit")
                    lines.append("\(title): \(credit.expiresAt == nil ? text("account.noExpiry") : date(credit.expiresAt))")
                }
                if credits.count < (limits.rateLimitResetCredits?.availableCount ?? 0) { lines.append(text("account.partialResets")) }
            } else { lines.append(text("account.resetDetailsUnavailable")) }
        }
        lines.append(text("account.usageTitle"))
        add("account.observationTime", observedAt?.ISO8601Format())
        let summary = usage?.summary
        for (key, value) in [("account.lifetime", summary?.lifetimeTokens), ("account.peakDaily", summary?.peakDailyTokens),
                             ("account.longestTurnSeconds", summary?.longestRunningTurnSec),
                             ("account.currentStreakDays", summary?.currentStreakDays), ("account.longestStreakDays", summary?.longestStreakDays)] {
            add(key, value.map(String.init))
        }
        add("account.dailyTokens", usage?.dailyUsageBuckets == nil ? nil : "")
        for day in usage?.recentDays ?? [] { lines.append("  \(day.startDate): \(day.tokens)") }
        lines.append(text("account.usageSource"))
        return lines
    }
}
