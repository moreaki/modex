import Foundation

public enum LocalCodexCapabilityDiscoveryError: Error, Equatable, Sendable {
    case codexUnavailable(String)
    case timedOut(Int)
    case processFailed(Int, String)
    case malformedResponse
    case noModels
}

public struct LocalCodexCapabilityDiscoveryService: Sendable {
    public let executablePath: String
    public let timeoutSeconds: Int

    public init(executablePath: String = "codex", timeoutSeconds: Int = 5) {
        let executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.executablePath = executablePath.isEmpty ? "codex" : executablePath
        self.timeoutSeconds = min(max(timeoutSeconds, 1), 15)
    }

    public func discover() async throws -> LocalCodexCapabilities {
        try await Task.detached(priority: .utility) {
            try discoverBlocking()
        }.value
    }

    private func discoverBlocking() throws -> LocalCodexCapabilities {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("modex-codex-capabilities-\(UUID().uuidString)", isDirectory: true)
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
            throw LocalCodexCapabilityDiscoveryError.codexUnavailable(executablePath)
        }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        var requestID = 2
        try writeRequest(Self.initializeRequest, to: input.fileHandleForWriting)
        try writeRequest(#"{"method":"initialized"}"#, to: input.fileHandleForWriting)
        try writeRequest(Self.modelListRequest(id: requestID, cursor: nil), to: input.fileHandleForWriting)

        var userAgent = "Codex"
        var models: [LocalCodexModelCapability] = []
        var processedLineCount = 0
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while Date() < deadline {
            let data = (try? Data(contentsOf: stdoutURL, options: .mappedIfSafe)) ?? Data()
            guard data.count <= 4 * 1_024 * 1_024 else {
                throw LocalCodexCapabilityDiscoveryError.malformedResponse
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
                    if message.id == 1, let discoveredUserAgent = message.userAgent {
                        userAgent = discoveredUserAgent
                    }
                    guard message.id == requestID, let page = message.modelPage else {
                        if message.id == requestID, let error = message.error {
                            throw LocalCodexCapabilityDiscoveryError.processFailed(-1, error)
                        }
                        continue
                    }

                    models.append(contentsOf: page.data.filter { $0.hidden == false })
                    if let cursor = page.nextCursor {
                        requestID += 1
                        try writeRequest(
                            Self.modelListRequest(id: requestID, cursor: cursor),
                            to: input.fileHandleForWriting
                        )
                    } else {
                        guard models.isEmpty == false else {
                            throw LocalCodexCapabilityDiscoveryError.noModels
                        }
                        return LocalCodexCapabilities(userAgent: userAgent, models: models)
                    }
                }
                processedLineCount = lines.count
            }

            if process.isRunning == false {
                process.waitUntilExit()
                let detail = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
                throw LocalCodexCapabilityDiscoveryError.processFailed(
                    Int(process.terminationStatus),
                    detail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            Thread.sleep(forTimeInterval: 0.025)
        }

        throw LocalCodexCapabilityDiscoveryError.timedOut(timeoutSeconds)
    }

    private func writeRequest(_ request: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data((request + "\n").utf8))
    }

    private struct ModelPage: Decodable {
        let data: [LocalCodexModelCapability]
        let nextCursor: String?
    }

    private struct ParsedMessage {
        let id: Int?
        let userAgent: String?
        let modelPage: ModelPage?
        let error: String?
    }

    private static func message(from line: String) -> ParsedMessage? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let id = object["id"] as? Int
        let result = object["result"] as? [String: Any]
        let userAgent = result?["userAgent"] as? String
        let modelPage: ModelPage?
        if let result,
           let resultData = try? JSONSerialization.data(withJSONObject: result)
        {
            modelPage = try? JSONDecoder().decode(ModelPage.self, from: resultData)
        } else {
            modelPage = nil
        }
        let errorObject = object["error"] as? [String: Any]
        let error = errorObject?["message"] as? String
        return ParsedMessage(id: id, userAgent: userAgent, modelPage: modelPage, error: error)
    }

    private static let initializeRequest =
        #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"modex","version":"\#(ModexApplicationVersion.current.description)"},"capabilities":{"experimentalApi":true}}}"#

    private static func modelListRequest(id: Int, cursor: String?) -> String {
        let request: [String: Any] = [
            "id": id,
            "method": "model/list",
            "params": [
                "cursor": cursor.map { $0 as Any } ?? NSNull(),
                "includeHidden": false,
                "limit": 100,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }
}
