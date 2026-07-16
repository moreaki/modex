import Foundation

public struct CodexAppServerRateLimitReader: Sendable {
    private let executablePath: String
    private let codexHome: URL
    private let timeoutSeconds: TimeInterval

    public init(
        executablePath: String = "codex",
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        timeoutSeconds: TimeInterval = 3
    ) {
        self.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "codex"
            : executablePath
        self.codexHome = codexHome
        self.timeoutSeconds = timeoutSeconds
    }

    public func latestRateLimits(now: Date = Date()) throws -> CodexRateLimits? {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let messages = AppServerMessageBuffer()

        if executablePath.contains("/") {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["app-server", "--stdio"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath, "app-server", "--stdio"]
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else {
                return
            }
            messages.append(data)
        }

        try process.run()
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        try write(
            AppServerInitializeRequest(),
            to: inputPipe.fileHandleForWriting
        )
        guard messages.waitForMessage(id: 1, timeout: timeoutSeconds) != nil else {
            throw CodexAppServerRateLimitReaderError.timedOut
        }

        try write(
            AppServerRateLimitRequest(),
            to: inputPipe.fileHandleForWriting
        )
        guard let response = messages.waitForMessage(id: 2, timeout: timeoutSeconds) else {
            throw CodexAppServerRateLimitReaderError.timedOut
        }

        return try Self.rateLimits(from: response, now: now)
    }

    private func write(_ request: some Encodable, to handle: FileHandle) throws {
        let data = try JSONEncoder().encode(request)
        try handle.write(contentsOf: data + Data([0x0A]))
    }

    static func rateLimits(from data: Data, now: Date = Date()) throws -> CodexRateLimits? {
        let envelope = try JSONDecoder().decode(AppServerResponse<AppServerRateLimitResponse>.self, from: data)
        guard let result = envelope.result else {
            return nil
        }

        var bucketsByKey: [String: CodexRateLimitBucket] = [:]
        if let fallbackBucket = result.rateLimits.bucket,
           fallbackBucket.hasFreshLimitWindow(at: now)
        {
            bucketsByKey[fallbackBucket.key] = fallbackBucket
        }

        for snapshot in (result.rateLimitsByLimitID ?? [:]).values {
            guard let bucket = snapshot.bucket,
                  bucket.hasFreshLimitWindow(at: now)
            else {
                continue
            }
            bucketsByKey[bucket.key] = bucket
        }

        let buckets = bucketsByKey.values.sorted { lhs, rhs in
            if lhs.isGeneral != rhs.isGeneral {
                return lhs.isGeneral
            }
            if lhs.isSpark != rhs.isSpark {
                return rhs.isSpark == false
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        guard buckets.isEmpty == false || result.rateLimits.planType != nil else {
            return nil
        }
        return CodexRateLimits(buckets: buckets, planType: result.rateLimits.planType)
    }
}

public enum CodexAppServerRateLimitReaderError: Error, Equatable, Sendable {
    case timedOut
}

private final class AppServerMessageBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var messagesByID: [Int: Data] = [:]
    private var semaphoresByID: [Int: DispatchSemaphore] = [:]

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard line.isEmpty == false,
                  let id = Self.messageID(in: line)
            else {
                continue
            }
            messagesByID[id] = Data(line)
            semaphoresByID[id]?.signal()
        }
        lock.unlock()
    }

    func waitForMessage(id: Int, timeout: TimeInterval) -> Data? {
        let semaphore: DispatchSemaphore
        lock.lock()
        if let message = messagesByID[id] {
            lock.unlock()
            return message
        }
        semaphore = semaphoresByID[id] ?? DispatchSemaphore(value: 0)
        semaphoresByID[id] = semaphore
        lock.unlock()

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success else {
            return nil
        }

        lock.lock()
        let message = messagesByID[id]
        lock.unlock()
        return message
    }

    private static func messageID(in data: Data.SubSequence) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data)) as? [String: Any] else {
            return nil
        }
        return object["id"] as? Int
    }
}

private struct AppServerInitializeRequest: Encodable {
    let id = 1
    let method = "initialize"
    let params = Params()

    struct Params: Encodable {
        let clientInfo = ClientInfo()
        let capabilities = Capabilities()
    }

    struct ClientInfo: Encodable {
        let name = "modex"
        let title: String? = "Modex"
        let version = "0.0.0"
    }

    struct Capabilities: Encodable {
        let experimentalApi = true
        let requestAttestation = false
        let optOutNotificationMethods: [String] = []
    }
}

private struct AppServerRateLimitRequest: Encodable {
    let id = 2
    let method = "account/rateLimits/read"
}

private struct AppServerResponse<Result: Decodable>: Decodable {
    let result: Result?
}

private struct AppServerRateLimitResponse: Decodable {
    let rateLimits: AppServerRateLimitSnapshot
    let rateLimitsByLimitID: [String: AppServerRateLimitSnapshot]?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
    }
}

private struct AppServerRateLimitSnapshot: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
        case planType
    }

    var bucket: CodexRateLimitBucket? {
        let bucket = CodexRateLimitBucket(
            id: limitID,
            name: limitName,
            primary: primary?.window,
            secondary: secondary?.window,
            planType: planType
        )
        return bucket.hasLimitWindows ? bucket : nil
    }
}

private struct AppServerRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?

    var window: CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowDurationMins,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
