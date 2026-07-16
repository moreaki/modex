public enum LocalCodexExecutableSource: String, Equatable, Sendable {
    case homebrew
    case codexApp
    case chatGPTApp
    case commandLine
    case custom
}

public struct LocalCodexExecutable: Equatable, Sendable {
    public let path: String
    public let version: String
    public let source: LocalCodexExecutableSource

    public init(path: String, version: String, source: LocalCodexExecutableSource) {
        self.path = path
        self.version = version
        self.source = source
    }
}

public struct LocalCodexExecutableDiscovery: Equatable, Sendable {
    public let executables: [LocalCodexExecutable]
    public let resolvedConfiguredPath: String?

    public init(executables: [LocalCodexExecutable], resolvedConfiguredPath: String?) {
        self.executables = executables
        self.resolvedConfiguredPath = resolvedConfiguredPath
    }
}
