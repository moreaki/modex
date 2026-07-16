import Foundation

public struct LocalCodexExecutableDiscoveryService: Sendable {
    public let configuredPath: String

    public init(configuredPath: String = "codex") {
        let configuredPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configuredPath = configuredPath.isEmpty ? "codex" : configuredPath
    }

    public func discover() async -> LocalCodexExecutableDiscovery {
        await Task.detached(priority: .utility) {
            discoverBlocking()
        }.value
    }

    private func discoverBlocking() -> LocalCodexExecutableDiscovery {
        let configuredCandidates = resolvedPaths(for: configuredPath)
        var candidates = configuredCandidates
        candidates.append(contentsOf: Self.knownApplicationPaths)
        candidates.append(contentsOf: resolvedPaths(for: "codex"))
        candidates.append("/opt/homebrew/bin/codex")
        candidates.append("/usr/local/bin/codex")

        var seen: Set<String> = []
        let uniqueCandidates = candidates.compactMap { candidate -> String? in
            let path = NSString(string: candidate).expandingTildeInPath
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard seen.insert(normalized).inserted,
                  FileManager.default.isExecutableFile(atPath: normalized)
            else {
                return nil
            }
            return normalized
        }

        let executables = uniqueCandidates.compactMap { path -> LocalCodexExecutable? in
            guard let version = version(at: path) else {
                return nil
            }
            return LocalCodexExecutable(
                path: path,
                version: version,
                source: Self.source(for: path, configuredPath: configuredPath)
            )
        }
        return LocalCodexExecutableDiscovery(
            executables: executables,
            resolvedConfiguredPath: configuredCandidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            })
        )
    }

    private func resolvedPaths(for commandOrPath: String) -> [String] {
        if commandOrPath.contains("/") {
            return [NSString(string: commandOrPath).expandingTildeInPath]
        }
        return Self.capture(
            executableURL: URL(fileURLWithPath: "/usr/bin/which"),
            arguments: ["-a", commandOrPath],
            timeoutSeconds: 1
        )?
        .split(whereSeparator: \.isNewline)
        .map(String.init) ?? []
    }

    private func version(at path: String) -> String? {
        guard let output = Self.capture(
            executableURL: URL(fileURLWithPath: path),
            arguments: ["--version"],
            timeoutSeconds: 2
        ) else {
            return nil
        }
        let version = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "codex-cli ", with: "")
        return version.isEmpty ? nil : version
    }

    private static func capture(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: Int
    ) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= 64 * 1_024 else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func source(
        for path: String,
        configuredPath: String
    ) -> LocalCodexExecutableSource {
        if path.contains("/Codex.app/") {
            return .codexApp
        }
        if path.contains("/ChatGPT.app/") {
            return .chatGPTApp
        }
        if path.hasPrefix("/opt/homebrew/") || path.contains("/Homebrew/") {
            return .homebrew
        }
        if configuredPath.contains("/"),
           URL(fileURLWithPath: NSString(string: configuredPath).expandingTildeInPath)
            .standardizedFileURL.path == path
        {
            return .custom
        }
        return .commandLine
    }

    private static var knownApplicationPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/MacOS/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
        ]
    }
}
