import Foundation

public struct CodexThreadRuntimeStatus: Decodable, Equatable, Sendable {
    public let type: String
    public let activeFlags: [String]?
    public var presentationKey: String? {
        switch type {
        case "active":
            return activeFlags?.contains(where: { ["waitingOnApproval", "waitingOnUserInput"].contains($0) }) == true
                ? "runtime.needsInput" : "runtime.active"
        case "idle": return "runtime.idle"
        case "systemError": return "runtime.error"
        default: return nil // notLoaded is not idle, especially on a private stdio server.
        }
    }
}

public struct CodexThreadRuntimeMetadata: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let projectId: String?
    public let originator: String?
    public let historyMode: String?
    public let isPinned: Bool?
    public var status: CodexThreadRuntimeStatus?
    public let updatedAt: Int?
    // Never decode preview or prompt content, nor replace observed turn model/effort.
    public func enriching(_ session: SessionSnapshot, live: Bool) -> SessionSnapshot {
        var result = session
        if let updatedAt, Date(timeIntervalSince1970: Double(updatedAt)) >= (session.updatedAt ?? .distantPast) {
            result.threadName = name ?? result.threadName
            result.projectID = projectId ?? result.projectID
            result.originator = originator ?? result.originator
            result.historyMode = historyMode ?? result.historyMode
            result.isPinned = isPinned ?? result.isPinned
        }
        result.runtimeStatus = live ? status : nil
        return result
    }
}

public struct CodexMetadataSnapshot: Equatable, Sendable {
    public var limits: CodexAccountLimits?
    public var limitsObservedAt: Date?
    public var usage: CodexAccountUsage?
    public var usageObservedAt: Date?
    public var threads: [String: CodexThreadRuntimeMetadata] = [:]
    public var threadsObservedAt: Date?
    public var connected = false
    public var refreshFailed = false
    public init() {}
}

/// In-memory enrichment only. Analytics have a 15-minute TTL, metadata one minute.
/// Failure preserves dated successes; identity changes discard them. No history writes.
public actor LocalCodexMetadataService {
    private let client: LocalCodexAppServerClient
    private var snapshot = CodexMetadataSnapshot()
    private var path: String?
    private var archived = false
    private var revision = 0
    private var lastRefresh = Date.distantPast
    private var lastUsageAttempt = Date.distantPast
    private var refreshing = false
    private var notificationsTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<CodexMetadataSnapshot>.Continuation] = [:]

    public init(client: LocalCodexAppServerClient = .shared) { self.client = client }
    public func cachedSnapshot() -> CodexMetadataSnapshot { snapshot }

    public func updates() -> AsyncStream<CodexMetadataSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            subscribers[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        }
    }
    private func unsubscribe(_ id: UUID) { subscribers.removeValue(forKey: id) }
    private func publish() { for subscriber in subscribers.values { subscriber.yield(snapshot) } }

    public func refresh(executablePath: String, includeArchived: Bool, now: Date = Date()) async {
        if path != executablePath {
            revision += 1
            path = executablePath
            snapshot = CodexMetadataSnapshot()
            lastRefresh = .distantPast
            lastUsageAttempt = .distantPast
            publish()
        }
        if archived != includeArchived { archived = includeArchived; lastRefresh = .distantPast }
        guard !refreshing, now.timeIntervalSince(lastRefresh) >= 60 else { return }
        refreshing = true
        defer { refreshing = false }
        lastRefresh = now
        let requestRevision = revision
        if notificationsTask == nil {
            let stream = await client.notifications()
            notificationsTask = Task { [weak self] in
                for await notification in stream { await self?.receive(notification) }
            }
        }
        do {
            let limits: CodexAccountLimits = try await client.request("account/rateLimits/read",
                parameters: Data("{\"skipResetCreditDetails\":true}".utf8), executablePath: executablePath)
            guard revision == requestRevision else { return }
            if let old = snapshot.limits?.accountId, let new = limits.accountId, old != new {
                snapshot = CodexMetadataSnapshot()
                lastUsageAttempt = .distantPast
            }
            snapshot.limits = limits
            snapshot.limitsObservedAt = now
            snapshot.connected = true
            snapshot.refreshFailed = false
            publish()
        } catch {
            guard revision == requestRevision else { return }
            snapshot.refreshFailed = true
            snapshot.connected = false
            publish()
        }
        guard !Task.isCancelled, revision == requestRevision else { return }
        if now.timeIntervalSince(lastUsageAttempt) >= 900 {
            lastUsageAttempt = now
            if let usage: CodexAccountUsage = try? await client.request("account/usage/read", executablePath: executablePath),
               revision == requestRevision {
                snapshot.usage = usage
                snapshot.usageObservedAt = now
                publish()
            }
        }
        guard !Task.isCancelled, revision == requestRevision else { return }
        do {
            let threads = try await readThreads(executablePath: executablePath, includeArchived: includeArchived)
            guard revision == requestRevision else { return }
            snapshot.threads = threads
            snapshot.threadsObservedAt = now
            snapshot.connected = true
            publish()
        } catch { /* Keep the last complete page set, never replace it with a partial list. */ }
    }

    private func readThreads(executablePath: String, includeArchived: Bool) async throws -> [String: CodexThreadRuntimeMetadata] {
        struct Page: Decodable, Sendable { let data: [CodexThreadRuntimeMetadata]; let nextCursor: String? }
        var result: [String: CodexThreadRuntimeMetadata] = [:]
        for archived in includeArchived ? [false, true] : [false] {
            var cursor: String?
            var seen: Set<String> = []
            repeat {
                let params = try JSONSerialization.data(withJSONObject: [
                    "cursor": cursor as Any? ?? NSNull(), "limit": 100, "archived": archived,
                    "useStateDbOnly": true, "sortKey": "recency_at",
                    "sourceKinds": ["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview",
                                    "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"],
                ])
                let page: Page = try await client.request("thread/list", parameters: params, executablePath: executablePath)
                for thread in page.data { result[thread.id] = thread }
                cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw LocalCodexAppServerError.malformedResponse }
                try Task.checkCancellation()
            } while cursor != nil
        }
        return result
    }

    private func receive(_ notification: LocalCodexAppServerClient.Notification) {
        switch notification.method {
        case "account/rateLimits/updated":
            guard let update = try? JSONDecoder().decode(CodexAccountLimits.self, from: notification.parameters) else { return }
            if let old = snapshot.limits?.accountId, let new = update.accountId, old != new {
                revision += 1
                snapshot = CodexMetadataSnapshot()
                lastUsageAttempt = .distantPast
                lastRefresh = .distantPast
            }
            snapshot.limits = snapshot.limits?.merging(update) ?? update
            snapshot.limitsObservedAt = Date()
        case "account/updated":
            // initialize announces the current auth mode before the first read.
            // There is no previous account data to invalidate in that case.
            guard snapshot.limits != nil || snapshot.usage != nil || !snapshot.threads.isEmpty else { return }
            revision += 1
            snapshot = CodexMetadataSnapshot()
            lastRefresh = .distantPast
            lastUsageAttempt = .distantPast
        case "thread/status/changed":
            struct Update: Decodable { let threadId: String; let status: CodexThreadRuntimeStatus }
            guard let update = try? JSONDecoder().decode(Update.self, from: notification.parameters) else { return }
            snapshot.threads[update.threadId]?.status = update.status
        case "thread/started":
            struct Update: Decodable { let thread: CodexThreadRuntimeMetadata }
            guard let update = try? JSONDecoder().decode(Update.self, from: notification.parameters) else { return }
            snapshot.threads[update.thread.id] = update.thread
        case "thread/closed":
            struct Update: Decodable { let threadId: String }
            guard let update = try? JSONDecoder().decode(Update.self, from: notification.parameters) else { return }
            snapshot.threads[update.threadId]?.status = nil
        case "modex/executableChanged":
            // First connection has no old identity-bound data. A replacement at
            // the same path must invalidate cached usage just like a new selection.
            guard snapshot.limits != nil || snapshot.usage != nil || !snapshot.threads.isEmpty else { return }
            revision += 1
            snapshot = CodexMetadataSnapshot()
            lastRefresh = .distantPast
            lastUsageAttempt = .distantPast
        case "modex/notificationGap":
            revision += 1
            snapshot = CodexMetadataSnapshot()
            lastRefresh = .distantPast
            lastUsageAttempt = .distantPast
        case "modex/disconnected":
            snapshot.connected = false
        default: return
        }
        publish()
    }
}
