import Foundation

public struct CodexAccountLimits: Decodable, Equatable, Sendable {
    public var accountId: String?
    public var ordinaryUsageAllowed: Bool?
    public var rateLimits: Bucket?
    public var rateLimitsByLimitId: [String: Bucket]?
    public var rateLimitResetCredits: ResetCredits?

    public struct ResetCredits: Decodable, Equatable, Sendable {
        public let availableCount: Int?
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
        public var spendControlReached: Bool?
        public var individualLimit: SpendControl?
        public var credits: Credits?
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
            result.spendControlReached = update.spendControlReached ?? spendControlReached
            result.individualLimit = update.individualLimit ?? individualLimit
            result.credits = update.credits ?? credits
            return result
        }
    }
    public var generalLimits: CodexRateLimits? {
        if let bucket = rateLimitsByLimitId?["codex"] { return bucket.value }
        guard let value = rateLimits?.value, value.isGeneralAccountLimit else { return nil }
        return value
    }
    /// Notifications are patches, not full reads. Explicit false is authoritative;
    /// absent/null values never imply recovery or erase known metadata.
    public func merging(_ update: Self) -> Self {
        if let old = accountId, let new = update.accountId, old != new { return update }
        var result = self
        result.accountId = update.accountId ?? accountId
        result.ordinaryUsageAllowed = update.ordinaryUsageAllowed ?? ordinaryUsageAllowed
        result.rateLimitResetCredits = update.rateLimitResetCredits ?? rateLimitResetCredits
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
