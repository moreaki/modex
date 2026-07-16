import Foundation

public enum LocalCodexAccountRateLimitError: Error, Equatable, Sendable {
    case codexUnavailable(String)
    case timedOut(Int)
    case processFailed(Int, String)
    case malformedResponse
    case noAccountRateLimits
}

public struct CodexAccountRateLimitSnapshot: Equatable, Sendable {
    public let rateLimits: CodexRateLimits
    public let observedAt: Date

    public init(rateLimits: CodexRateLimits, observedAt: Date) {
        self.rateLimits = rateLimits
        self.observedAt = observedAt
    }
}

public struct LocalCodexAccountRateLimitService: Sendable {
    public let executablePath: String
    public let timeoutSeconds: Int

    public init(executablePath: String = "codex", timeoutSeconds: Int = 5) {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.executablePath = executablePath.isEmpty ? "codex" : executablePath
        self.timeoutSeconds = min(max(timeoutSeconds, 1), 15)
    }

    public func fetchGeneralAccountLimits() async throws -> CodexAccountRateLimitSnapshot {
        try await Task.detached(priority: .utility) {
            try fetchGeneralAccountLimitsBlocking()
        }.value
    }

    private func fetchGeneralAccountLimitsBlocking() throws -> CodexAccountRateLimitSnapshot {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("modex-codex-account-limits-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        let stdoutURL = root.appendingPathComponent("codex.out")
        let stderrURL = root.appendingPathComponent("codex.err")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        if executablePath.contains("/") {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["app-server", "--stdio"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath, "app-server", "--stdio"]
        }
        process.currentDirectoryURL = root
        process.standardOutput = stdout
        process.standardError = stderr

        let input = Pipe()
        process.standardInput = input

        do {
            try process.run()
        } catch {
            throw LocalCodexAccountRateLimitError.codexUnavailable(executablePath)
        }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        try writeRequest(Self.initializeRequest, to: input.fileHandleForWriting)
        try writeRequest(#"{"method":"initialized"}"#, to: input.fileHandleForWriting)
        try writeRequest(Self.accountRateLimitsRequest, to: input.fileHandleForWriting)

        var processedLineCount = 0
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while Date() < deadline {
            let data = (try? Data(contentsOf: stdoutURL, options: .mappedIfSafe)) ?? Data()
            guard data.count <= 4 * 1_024 * 1_024 else {
                throw LocalCodexAccountRateLimitError.malformedResponse
            }
            let output = String(decoding: data, as: UTF8.self)
            var lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if output.isEmpty == false, output.hasSuffix("\n") == false, lines.isEmpty == false {
                lines.removeLast()
            }

            if processedLineCount < lines.count {
                for line in lines[processedLineCount...] {
                    guard let message = Self.message(from: line) else {
                        continue
                    }
                    guard message.id == Self.accountRateLimitsRequestID else {
                        continue
                    }
                    if let error = message.error {
                        throw LocalCodexAccountRateLimitError.processFailed(-1, error)
                    }
                    guard let limits = message.response?.generalAccountLimits else {
                        throw LocalCodexAccountRateLimitError.noAccountRateLimits
                    }
                    return CodexAccountRateLimitSnapshot(rateLimits: limits, observedAt: Date())
                }
                processedLineCount = lines.count
            }

            if process.isRunning == false {
                process.waitUntilExit()
                let detail = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
                throw LocalCodexAccountRateLimitError.processFailed(
                    Int(process.terminationStatus),
                    detail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            Thread.sleep(forTimeInterval: 0.025)
        }

        throw LocalCodexAccountRateLimitError.timedOut(timeoutSeconds)
    }

    private func writeRequest(_ request: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data((request + "\n").utf8))
    }

    private struct ParsedMessage {
        let id: Int?
        let response: GetAccountRateLimitsResponse?
        let error: String?
    }

    private struct GetAccountRateLimitsResponse: Decodable {
        let rateLimits: RateLimitSnapshot
        let rateLimitsByLimitID: [String: RateLimitSnapshot]?

        enum CodingKeys: String, CodingKey {
            case rateLimits
            case rateLimitsByLimitID = "rateLimitsByLimitId"
        }

        var generalAccountLimits: CodexRateLimits? {
            if let limits = rateLimitsByLimitID?["codex"]?.codexRateLimits {
                return limits
            }
            let limits = rateLimits.codexRateLimits
            return limits.isGeneralAccountLimit ? limits : nil
        }
    }

    private struct RateLimitSnapshot: Decodable {
        let limitID: String?
        let limitName: String?
        let planType: String?
        let primary: RateLimitWindow?
        let secondary: RateLimitWindow?
        let rateLimitReachedType: String?

        enum CodingKeys: String, CodingKey {
            case limitID = "limitId"
            case limitName
            case planType
            case primary
            case secondary
            case rateLimitReachedType
        }

        var codexRateLimits: CodexRateLimits {
            CodexRateLimits(
                primary: primary?.codexWindow,
                secondary: secondary?.codexWindow,
                limitID: limitID,
                limitName: limitName,
                planType: planType,
                reachedType: rateLimitReachedType
            )
        }
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent
            case windowDurationMins
            case resetsAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let doubleValue = try? container.decode(Double.self, forKey: .usedPercent) {
                usedPercent = doubleValue
            } else {
                usedPercent = Double(try container.decode(Int.self, forKey: .usedPercent))
            }
            windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
            resetsAt = try container.decodeIfPresent(Int.self, forKey: .resetsAt)
        }

        var codexWindow: CodexRateLimitWindow {
            CodexRateLimitWindow(
                usedPercent: usedPercent,
                windowMinutes: windowDurationMins,
                resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
    }

    private static func message(from line: String) -> ParsedMessage? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let id = object["id"] as? Int
        let result = object["result"] as? [String: Any]
        let response: GetAccountRateLimitsResponse?
        if let result,
           let resultData = try? JSONSerialization.data(withJSONObject: result)
        {
            response = try? JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: resultData)
        } else {
            response = nil
        }
        let errorObject = object["error"] as? [String: Any]
        let error = errorObject?["message"] as? String
        return ParsedMessage(id: id, response: response, error: error)
    }

    private static let accountRateLimitsRequestID = 2

    private static let initializeRequest =
        #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"modex","version":"\#(ModexApplicationVersion.current.description)"},"capabilities":{"experimentalApi":true}}}"#

    private static let accountRateLimitsRequest =
        #"{"id":2,"method":"account/rateLimits/read","params":{}}"#
}
