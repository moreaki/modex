import Foundation

public enum LocalCodexAccountRateLimitError: Error, Equatable, Sendable {
    case codexUnavailable(String), timedOut(Int), processFailed(Int, String), malformedResponse, noAccountRateLimits
}

public struct CodexAccountRateLimitSnapshot: Equatable, Sendable {
    public let rateLimits: CodexRateLimits
    public let observedAt: Date
    public let account: CodexAccountLimits?
    public init(rateLimits: CodexRateLimits, observedAt: Date, account: CodexAccountLimits? = nil) {
        self.rateLimits = rateLimits
        self.observedAt = observedAt
        self.account = account
    }
}

public struct LocalCodexAccountRateLimitService: Sendable {
    public let executablePath: String
    public let timeoutSeconds: Int
    private let client: LocalCodexAppServerClient
    public init(executablePath: String = "codex", timeoutSeconds: Int = 5, client: LocalCodexAppServerClient = .shared) {
        self.executablePath = executablePath.isEmpty ? "codex" : executablePath
        self.timeoutSeconds = min(max(timeoutSeconds, 1), 15)
        self.client = client
    }
    public func fetchGeneralAccountLimits() async throws -> CodexAccountRateLimitSnapshot {
        let account = try await fetchAccountLimits()
        guard let limits = account.generalLimits else { throw LocalCodexAccountRateLimitError.noAccountRateLimits }
        return CodexAccountRateLimitSnapshot(rateLimits: limits, observedAt: Date(), account: account)
    }
    public func fetchAccountLimits() async throws -> CodexAccountLimits {
        try await client.request(
            "account/rateLimits/read",
            executablePath: executablePath, timeoutSeconds: timeoutSeconds
        )
    }
}
