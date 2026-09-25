import Foundation

public struct CodexAccountLimits: Decodable, Equatable, Sendable {
    public var accountId: String?
    public var ordinaryUsageAllowed: Bool?
    public var rateLimits: Bucket?
    public var rateLimitsByLimitId: [String: Bucket]?
    public var rateLimitResetCredits: ResetCredits?

    public struct ResetCredits: Decodable, Equatable, Sendable {
        public let availableCount: Int?
        public let credits: [ResetCredit]?
        public var availableDetails: [ResetCredit]? {
            credits?.filter { $0.status == "available" }.sorted {
                ($0.expiresAt ?? .max, $0.id) < ($1.expiresAt ?? .max, $1.id)
            }
        }

        fileprivate func merging(_ update: Self) -> Self {
            // A count-only notification must not erase details, unless the count
            // changed and those rows can no longer be considered current.
            Self(availableCount: update.availableCount ?? availableCount,
                 credits: update.credits ?? ((update.availableCount == nil || update.availableCount == availableCount) ? credits : nil))
        }
    }
    public struct ResetCredit: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let resetType: String
        public let status: String
        public let grantedAt: Int?
        public let expiresAt: Int?
        public let title: String?
        public let description: String?
    }
    public var generalBucket: Bucket? {
        if let bucket = rateLimitsByLimitId?["codex"] { return bucket }
        guard let bucket = rateLimits, bucket.value.isGeneralAccountLimit else { return nil }
        return bucket
    }
    public struct Credits: Decodable, Equatable, Sendable {
        public let balance: String?
        public let hasCredits: Bool?
        public let unlimited: Bool?
    }
    public struct SpendControl: Decodable, Equatable, Sendable {
        public let limit: String?
        public let used: String?
        public let remainingPercent: Int?
        public let resetsAt: Int?
    }
    public struct Window: Decodable, Equatable, Sendable {
        public let usedPercent: Double
        public let windowDurationMins: Int?
        public let resetsAt: Int?
        public var value: CodexRateLimitWindow {
            CodexRateLimitWindow(usedPercent: usedPercent, windowMinutes: windowDurationMins,
                                resetsAt: resetsAt.map { Date(timeIntervalSince1970: Double($0)) })
        }
    }
    public struct Bucket: Decodable, Equatable, Sendable {
        public var limitId: String?
        public var limitName: String?
        public var planType: String?
        public var primary: Window?
        public var secondary: Window?
        public var rateLimitReachedType: String?
        public var normalModelSlug: String?
        public var spendControlReached: Bool?
        public var individualLimit: SpendControl?
        public var credits: Credits?
        public var reachedReasonKey: String? {
            guard let rateLimitReachedType else { return nil }
            switch rateLimitReachedType {
            case "rate_limit_reached": return "account.quotaReached"
            case "workspace_owner_credits_depleted", "workspace_member_credits_depleted": return "account.workspaceCreditsDepleted"
            case "workspace_owner_usage_limit_reached", "workspace_member_usage_limit_reached": return "account.workspaceLimitReached"
            default: return "account.limitReasonUnknown"
            }
        }
        public var value: CodexRateLimits {
            CodexRateLimits(primary: primary?.value, secondary: secondary?.value, limitID: limitId,
                           limitName: limitName, planType: planType, reachedType: rateLimitReachedType)
        }
        fileprivate func merging(_ update: Self) -> Self {
            var result = self
            result.limitId = update.limitId ?? limitId
            result.limitName = update.limitName ?? limitName
            result.planType = update.planType ?? planType
            result.primary = update.primary ?? primary
            result.secondary = update.secondary ?? secondary
            result.rateLimitReachedType = update.rateLimitReachedType ?? rateLimitReachedType
            result.normalModelSlug = update.normalModelSlug ?? normalModelSlug
            result.spendControlReached = update.spendControlReached ?? spendControlReached
            result.individualLimit = update.individualLimit ?? individualLimit
            result.credits = update.credits ?? credits
            return result
        }
    }
    public var generalLimits: CodexRateLimits? {
        generalBucket?.value
    }
    /// Notifications are patches, not full reads. Explicit false is authoritative;
    /// absent/null values never imply recovery or erase known metadata.
    public func merging(_ update: Self) -> Self {
        if let old = accountId, let new = update.accountId, old != new { return update }
        var result = self
        result.accountId = update.accountId ?? accountId
        result.ordinaryUsageAllowed = update.ordinaryUsageAllowed ?? ordinaryUsageAllowed
        if let updateCredits = update.rateLimitResetCredits {
            result.rateLimitResetCredits = rateLimitResetCredits?.merging(updateCredits) ?? updateCredits
        }
        if let bucket = update.rateLimits { result.rateLimits = rateLimits?.merging(bucket) ?? bucket }
        for (key, bucket) in update.rateLimitsByLimitId ?? [:] {
            if result.rateLimitsByLimitId == nil { result.rateLimitsByLimitId = [:] }
            let merged = result.rateLimitsByLimitId?[key]?.merging(bucket) ?? bucket
            result.rateLimitsByLimitId?[key] = merged
        }
        return result
    }
}

public struct CodexAccountUsage: Decodable, Equatable, Sendable {
    public struct Summary: Decodable, Equatable, Sendable {
        public let lifetimeTokens: Int?
        public let peakDailyTokens: Int?
        public let longestRunningTurnSec: Int?
        public let currentStreakDays: Int?
        public let longestStreakDays: Int?
    }
    public struct Day: Decodable, Equatable, Sendable {
        public let startDate: String
        public let tokens: Int
    }
    public let summary: Summary?
    public let dailyUsageBuckets: [Day]?
    /// Only real reported buckets, never interpolated missing dates.
    public var recentDays: [Day] {
        Array((dailyUsageBuckets ?? []).filter { $0.tokens >= 0 }.sorted { $0.startDate < $1.startDate }.suffix(14))
    }
}
