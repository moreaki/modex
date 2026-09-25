import Foundation

public enum LocalCodexCapabilityDiscoveryError: Error, Equatable, Sendable {
    case codexUnavailable(String), timedOut(Int), processFailed(Int, String), malformedResponse, noModels
}

public struct LocalCodexCapabilityDiscoveryService: Sendable {
    public let executablePath: String
    public let timeoutSeconds: Int
    private let client: LocalCodexAppServerClient
    public init(executablePath: String = "codex", timeoutSeconds: Int = 5, client: LocalCodexAppServerClient = .shared) {
        self.executablePath = executablePath.isEmpty ? "codex" : executablePath
        self.timeoutSeconds = min(max(timeoutSeconds, 1), 15)
        self.client = client
    }

    public func discover() async throws -> LocalCodexCapabilities {
        struct Page: Decodable, Sendable {
            let data: [LocalCodexModelCapability]
            let nextCursor: String?
        }
        var models: [LocalCodexModelCapability] = []
        var cursor: String?
        var seen: Set<String> = []
        repeat {
            let parameters = try JSONSerialization.data(withJSONObject: [
                "includeHidden": false, "limit": 100, "cursor": cursor as Any? ?? NSNull(),
            ])
            let page: Page = try await client.request(
                "model/list", parameters: parameters, executablePath: executablePath, timeoutSeconds: timeoutSeconds
            )
            models.append(contentsOf: page.data.filter { !$0.hidden })
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw LocalCodexCapabilityDiscoveryError.malformedResponse }
            guard models.count <= 10_000 else { throw LocalCodexCapabilityDiscoveryError.malformedResponse }
        } while cursor != nil
        guard !models.isEmpty else { throw LocalCodexCapabilityDiscoveryError.noModels }
        return await LocalCodexCapabilities(userAgent: client.userAgent, models: models)
    }
}
