import Foundation

public enum LocalCodexAppServerError: Error, Equatable, Sendable {
    case unavailable, disconnected, malformedResponse, oversizedMessage, overloaded, timedOut
    case remote(Int, String)
}

/// One read-only, event-driven connection. No polling files, background reconnect timer,
/// request replay, or model inference. Retry only when a consumer next needs data.
public actor LocalCodexAppServerClient {
    public static let shared = LocalCodexAppServerClient()
    public struct Notification: Sendable {
        public let method: String
        public let parameters: Data
    }
    public struct Diagnostics: Sendable {
        public var processStarts = 0
        public var requests = 0
        public var timeouts = 0
        public var lastRequestSeconds: Double = 0
    }
    private struct Pending {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
        let started: Date
    }
    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var initialization: Task<Void, Error>?
    private var executable: String?
    private var executableIdentity: String?
    private var generation = UUID()
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    private var subscribers: [UUID: AsyncStream<Notification>.Continuation] = [:]
    private var failures = 0
    private var retryAfter = Date.distantPast
    private var metrics = Diagnostics()
    public private(set) var userAgent = "Codex"
    private let maximumMessageBytes = 4 * 1_024 * 1_024

    public init() {}

    public func diagnostics() -> Diagnostics { metrics }

    public func notifications() -> AsyncStream<Notification> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        }
    }

    private func unsubscribe(_ id: UUID) { subscribers.removeValue(forKey: id) }

    public func request<Response: Decodable & Sendable>(
        _ method: String, parameters: Data = Data("{}".utf8),
        executablePath: String, timeoutSeconds: Int = 5, as: Response.Type = Response.self
    ) async throws -> Response {
        try await connect(executablePath: executablePath, timeoutSeconds: timeoutSeconds)
        guard executable == executablePath else { throw LocalCodexAppServerError.disconnected }
        let data = try await send(method, parameters: parameters, timeoutSeconds: timeoutSeconds)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    public func shutdown() {
        generation = UUID()
        initialization?.cancel()
        initialization = nil
        reader?.cancel()
        reader = nil
        try? input?.close()
        input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        for entry in pending.values {
            entry.timeout.cancel()
            entry.continuation.resume(throwing: LocalCodexAppServerError.disconnected)
        }
        pending.removeAll()
        emit(method: "modex/disconnected")
    }

    private func connectionFailed() {
        shutdown()
        failures = min(failures + 1, 6)
        retryAfter = Date().addingTimeInterval(min(60, pow(2, Double(failures))) + Double.random(in: 0...1))
    }

    private func connect(executablePath: String, timeoutSeconds: Int) async throws {
        let identity: String
        if executablePath.hasPrefix("/"),
           let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath) {
            identity = "\(attributes[.systemFileNumber] ?? ""):\(attributes[.size] ?? ""):\(attributes[.modificationDate] ?? "")"
        } else { identity = executablePath }
        if executable != executablePath || executableIdentity != identity {
            shutdown()
            emit(method: "modex/executableChanged")
            executable = executablePath
            executableIdentity = identity
            failures = 0
            retryAfter = .distantPast
        }
        if let initialization { return try await initialization.value }
        if process?.isRunning == true { return }
        guard Date() >= retryAfter else { throw LocalCodexAppServerError.unavailable }
        let connection = generation
        let task = Task { try await self.start(executablePath, timeoutSeconds: timeoutSeconds) }
        initialization = task
        do {
            try await task.value
            guard connection == generation else { throw LocalCodexAppServerError.disconnected }
            initialization = nil
            failures = 0
        } catch {
            guard connection == generation else { throw error }
            shutdown()
            failures = min(failures + 1, 6)
            retryAfter = Date().addingTimeInterval(min(60, pow(2, Double(failures))) + Double.random(in: 0...1))
            throw error
        }
    }

    private func start(_ path: String, timeoutSeconds: Int) async throws {
        let process = Process()
        if path.contains("/") {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["app-server", "--stdio"]
        } else {
            // Compatibility for an unconfigured installation; configured paths stay explicit.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [path, "app-server", "--stdio"]
        }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        // Never retain diagnostics that could contain credentials or prompt content.
        process.standardError = FileHandle.nullDevice
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(1))
        continuation.onTermination = { _ in
            stdout.fileHandleForReading.readabilityHandler = nil
            try? stdout.fileHandleForReading.close()
        }
        Self.armRead(stdout.fileHandleForReading, continuation: continuation)
        try process.run()
        metrics.processStarts += 1
        self.process = process
        input = stdin.fileHandleForWriting
        let connection = generation
        reader = Task {
            var buffer = Data()
            var scannedBytes = 0
            for await chunk in stream {
                guard connection == self.generation, !Task.isCancelled else { return }
                buffer.append(chunk)
                while let newline = buffer.dropFirst(scannedBytes).firstIndex(of: 10) {
                    guard buffer.distance(from: buffer.startIndex, to: newline) < self.maximumMessageBytes else { self.connectionFailed(); return }
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    scannedBytes = 0
                    guard self.receive(line) else { self.connectionFailed(); return }
                }
                guard buffer.count <= self.maximumMessageBytes else { self.connectionFailed(); return }
                scannedBytes = buffer.count
                // One chunk in flight: let the pipe apply backpressure while the
                // actor frames/decodes it, rather than dropping a valid burst.
                guard !Task.isCancelled, connection == self.generation else { return }
                Self.armRead(stdout.fileHandleForReading, continuation: continuation)
            }
            if connection == self.generation { self.connectionFailed() }
        }
        let initialize = Data("""
        {"clientInfo":{"name":"modex","version":"\(ModexApplicationVersion.current)"},"capabilities":{"experimentalApi":true}}
        """.utf8)
        let result = try await send("initialize", parameters: initialize, timeoutSeconds: timeoutSeconds)
        struct Initialized: Decodable { let userAgent: String? }
        userAgent = (try? JSONDecoder().decode(Initialized.self, from: result).userAgent) ?? "Codex"
        try input?.write(contentsOf: Data("{\"method\":\"initialized\"}\n".utf8))
    }

    private nonisolated static func armRead(_ handle: FileHandle, continuation: AsyncStream<Data>.Continuation) {
        handle.readabilityHandler = { handle in
            handle.readabilityHandler = nil
            let data = handle.availableData
            if data.isEmpty { continuation.finish() }
            else { continuation.yield(data) }
        }
    }

    private func send(_ method: String, parameters: Data, timeoutSeconds: Int) async throws -> Data {
        try Task.checkCancellation()
        guard pending.count < 16 else { throw LocalCodexAppServerError.overloaded }
        nextID += 1
        let id = nextID
        let params = try JSONSerialization.jsonObject(with: parameters, options: .fragmentsAllowed)
        var message = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params],
                                                 options: [.withoutEscapingSlashes])
        message.append(10)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task {
                    do { try await Task.sleep(for: .seconds(min(max(timeoutSeconds, 1), 30))) }
                    catch { return }
                    self.metrics.timeouts += 1
                    self.finish(id, result: .failure(LocalCodexAppServerError.timedOut))
                }
                pending[id] = Pending(continuation: continuation, timeout: timeout, started: Date())
                metrics.requests += 1
                do {
                    guard let input else { throw LocalCodexAppServerError.disconnected }
                    try input.write(contentsOf: message)
                } catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { await self.finish(id, result: .failure(CancellationError())) }
        }
    }

    private func finish(_ id: Int, result: Result<Data, Error>) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout.cancel()
        metrics.lastRequestSeconds = Date().timeIntervalSince(entry.started)
        entry.continuation.resume(with: result)
    }

    private func receive(_ data: Data) -> Bool {
        if data.isEmpty { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let id = object["id"] as? Int {
            if let error = object["error"] as? [String: Any] {
                finish(id, result: .failure(LocalCodexAppServerError.remote(error["code"] as? Int ?? -1, error["message"] as? String ?? "")))
            } else if let result = object["result"],
                      let data = try? JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed) {
                finish(id, result: .success(data))
            } else { return false }
        } else if let method = object["method"] as? String {
            let params = (try? JSONSerialization.data(withJSONObject: object["params"] ?? [:])) ?? Data("{}".utf8)
            emit(method: method, parameters: params)
        }
        return true
    }

    private func emit(method: String, parameters: Data = Data("{}".utf8)) {
        let notification = Notification(method: method, parameters: parameters)
        for subscriber in subscribers.values {
            if case .dropped = subscriber.yield(notification) {
                // Consumers must not keep authoritative state after missing a patch.
                subscriber.yield(Notification(method: "modex/notificationGap", parameters: Data("{}".utf8)))
            }
        }
    }
}
