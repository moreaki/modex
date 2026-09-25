import Foundation

/// Account analytics only; never uploads local rollouts or requests thread estimates.
/// The metadata coordinator owns the shared 15-minute refresh TTL.
public struct LocalCodexAccountUsageService: Sendable {
    private let executablePath: String
    private let client: LocalCodexAppServerClient
    private let timeoutSeconds: Int

    public init(executablePath: String, client: LocalCodexAppServerClient = .shared, timeoutSeconds: Int = 5) {
        self.executablePath = executablePath
        self.client = client
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetch() async throws -> CodexAccountUsage {
        try await client.request("account/usage/read", executablePath: executablePath, timeoutSeconds: timeoutSeconds)
    }
}
