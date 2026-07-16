import Foundation
import os

public struct CodexSessionScannerConfiguration: Equatable, Sendable {
    public static let maximumAllowedConcurrentParses = max(1, min(16, ProcessInfo.processInfo.activeProcessorCount))
    public static let defaultMaximumConcurrentParses = min(
        maximumAllowedConcurrentParses,
        max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    )
    public static let minimumChunkSizeBytes = 16 * 1024
    public static let defaultChunkSizeBytes = 256 * 1024
    public static let maximumAllowedChunkSizeBytes = 4 * 1024 * 1024
    public static let minimumLineBufferBytes = 64 * 1024
    public static let defaultLineBufferBytes = 512 * 1024
    public static let maximumAllowedLineBufferBytes = 4 * 1024 * 1024
    public static let minimumSessionIndexLineBufferBytes = 16 * 1024
    public static let defaultSessionIndexLineBufferBytes = 128 * 1024
    public static let maximumAllowedSessionIndexLineBufferBytes = 1024 * 1024

    public static let `default` = CodexSessionScannerConfiguration()

    public let maximumConcurrentParses: Int
    public let chunkSizeBytes: Int
    public let maximumLineBufferBytes: Int
    public let sessionIndexMaximumLineBufferBytes: Int
    public let includeArchivedSessions: Bool

    public init(
        maximumConcurrentParses: Int = Self.defaultMaximumConcurrentParses,
        chunkSizeBytes: Int = Self.defaultChunkSizeBytes,
        maximumLineBufferBytes: Int = Self.defaultLineBufferBytes,
        sessionIndexMaximumLineBufferBytes: Int = Self.defaultSessionIndexLineBufferBytes,
        includeArchivedSessions: Bool = false
    ) {
        self.maximumConcurrentParses = Self.clamped(
            maximumConcurrentParses,
            minimum: 1,
            maximum: Self.maximumAllowedConcurrentParses
        )
        self.chunkSizeBytes = Self.clamped(
            chunkSizeBytes,
            minimum: Self.minimumChunkSizeBytes,
            maximum: Self.maximumAllowedChunkSizeBytes
        )
        self.maximumLineBufferBytes = Self.clamped(
            maximumLineBufferBytes,
            minimum: Self.minimumLineBufferBytes,
            maximum: Self.maximumAllowedLineBufferBytes
        )
        self.sessionIndexMaximumLineBufferBytes = Self.clamped(
            sessionIndexMaximumLineBufferBytes,
            minimum: Self.minimumSessionIndexLineBufferBytes,
            maximum: Self.maximumAllowedSessionIndexLineBufferBytes
        )
        self.includeArchivedSessions = includeArchivedSessions
    }

    private static func clamped(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(max(value, minimum), maximum)
    }
}

public final class CodexSessionScanner {
    private let codexHome: URL
    private let configuration: CodexSessionScannerConfiguration

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        configuration: CodexSessionScannerConfiguration = .default
    ) {
        self.codexHome = codexHome
        self.configuration = configuration
    }

    public func scan(limit: Int? = nil) async throws -> [SessionSnapshot] {
        try await scanResult(limit: limit).sessions
    }

    public func scanResult(
        limit: Int? = nil,
        initialBatchSize: Int = 7,
        cache: CodexSessionScanCache? = nil,
        onProgress: (@Sendable (CodexScanResult) async -> Void)? = nil
    ) async throws -> CodexScanResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let resourceStart = ProcessResourceSampler.sample()
        let safeLimit = limit.map { max(0, $0) }
        if safeLimit == 0 {
            return CodexScanResult(
                sessions: [],
                metrics: ScanMetrics(
                    parserMode: FastCodexJSONLParser.parserMode,
                    filesSelected: 0,
                    filesParsed: 0,
                    bytesRead: 0,
                    durationSeconds: ProcessInfo.processInfo.systemUptime - startedAt,
                    maximumConcurrentParses: 0,
                    configuredMaximumConcurrentParses: configuration.maximumConcurrentParses,
                    chunkSizeBytes: configuration.chunkSizeBytes,
                    maximumLineBufferBytes: configuration.maximumLineBufferBytes,
                    sessionIndexMaximumLineBufferBytes: configuration.sessionIndexMaximumLineBufferBytes,
                    cacheEnabled: cache != nil,
                    cacheEntries: cache?.entryCount ?? 0,
                    fileMetrics: []
                )
            )
        }

        let sidebarStateRead = CodexSidebarStateReader.read(codexHome: codexHome)
        let discovery = try sessionFileDiscovery(limit: safeLimit)
        let prioritized = Self.prioritizedCandidates(
            discovery.candidates,
            sidebarState: sidebarStateRead?.state,
            initialCountPerScope: initialBatchSize
        )
        let files = prioritized.candidates
        guard files.isEmpty == false else {
            return CodexScanResult(
                sessions: [],
                metrics: ScanMetrics(
                    parserMode: FastCodexJSONLParser.parserMode,
                    filesSelected: 0,
                    filesParsed: 0,
                    bytesRead: 0,
                    durationSeconds: ProcessInfo.processInfo.systemUptime - startedAt,
                    maximumConcurrentParses: 0,
                    configuredMaximumConcurrentParses: configuration.maximumConcurrentParses,
                    chunkSizeBytes: configuration.chunkSizeBytes,
                    maximumLineBufferBytes: configuration.maximumLineBufferBytes,
                    sessionIndexMaximumLineBufferBytes: configuration.sessionIndexMaximumLineBufferBytes,
                    discoveryMode: discovery.mode,
                    cacheEnabled: cache != nil,
                    cacheEntries: cache?.entryCount ?? 0,
                    fileMetrics: []
                )
            )
        }

        let configuration = configuration
        let cachedResults: [Int: ParseResult]
        if let cache {
            cachedResults = Dictionary(
                uniqueKeysWithValues: files.enumerated().compactMap { index, file in
                    cache.result(for: SessionScanCacheKey(candidate: file)).map { (index, $0) }
                }
            )
        } else {
            cachedResults = [:]
        }
        let threadIndex = threadNames(for: files, cachedResults: cachedResults)
        let metadataHits = files.reduce(0) { $0 + ($1.metadata == nil ? 0 : 1) }
        var results: [IndexedParseResult] = []
        var cacheHits = 0
        var cacheMisses = 0
        var cacheBytesSaved = 0

        func enriched(_ indexedResult: IndexedParseResult) -> IndexedParseResult {
            var snapshot = indexedResult.result.snapshot
            var metrics = indexedResult.result.metrics
            if files.indices.contains(indexedResult.index),
               let metadata = files[indexedResult.index].metadata
            {
                Self.apply(metadata: metadata, to: &snapshot)
            }
            if let sessionID = snapshot.sessionID,
               let threadName = threadIndex.threadNames[sessionID],
               threadName.isEmpty == false,
               snapshot.threadName?.isEmpty ?? true
            {
                snapshot.threadName = threadName
            }
            if let sessionID = snapshot.sessionID,
               let sidebarState = sidebarStateRead?.state
            {
                snapshot.threadScope = sidebarState.scope(for: sessionID)
            } else {
                snapshot.threadScope = CodexThreadScope.resolve(for: snapshot)
            }
            if let threadName = snapshot.threadName, threadName.isEmpty == false {
                metrics = metrics.withThreadName(threadName)
            }
            return IndexedParseResult(
                index: indexedResult.index,
                result: ParseResult(
                    snapshot: snapshot,
                    metrics: metrics,
                    checkpoint: indexedResult.result.checkpoint
                )
            )
        }

        func append(_ indexedResult: IndexedParseResult) {
            let indexedResult = enriched(indexedResult)
            results.append(indexedResult)
            if let cache,
               indexedResult.result.metrics.cacheHit == false,
               files.indices.contains(indexedResult.index)
            {
                cache.store(
                    indexedResult.result,
                    for: SessionScanCacheKey(candidate: files[indexedResult.index])
                )
            }
        }

        func prepare(_ range: Range<Int>) -> [IndexedSessionFileCandidate] {
            var workItems: [IndexedSessionFileCandidate] = []
            workItems.reserveCapacity(range.count)
            for index in range {
                let file = files[index]
                if cache != nil {
                    if let cachedResult = cachedResults[index] {
                        cacheHits += 1
                        cacheBytesSaved += file.fileSize
                        append(
                            IndexedParseResult(
                                index: index,
                                result: cachedResult.asCacheHit()
                            )
                        )
                        continue
                    }
                    cacheMisses += 1
                }
                workItems.append(
                    IndexedSessionFileCandidate(
                        index: index,
                        file: file,
                        checkpoint: cache?.checkpointForGrowth(of: SessionScanCacheKey(candidate: file))
                    )
                )
            }
            return workItems
        }

        func currentResult() -> CodexScanResult {
            let orderedResults = results.sorted { $0.index < $1.index }
            let fileMetrics = orderedResults.map(\.result.metrics)
            let sessions = orderedResults.map(\.result.snapshot)
            let bytesRead = fileMetrics.reduce(
                threadIndex.bytesRead + (sidebarStateRead?.bytesRead ?? 0)
            ) { $0 + $1.bytesRead }
            let parseWorkItemCount = cache == nil ? results.count : cacheMisses
            let activeConcurrentParses = parseWorkItemCount == 0
                ? 0
                : min(configuration.maximumConcurrentParses, parseWorkItemCount)
            let resources = ProcessResourceSampler.delta(from: resourceStart)
            return CodexScanResult(
                sessions: sessions,
                metrics: ScanMetrics(
                    parserMode: FastCodexJSONLParser.parserMode,
                    filesSelected: files.count,
                    filesParsed: sessions.count,
                    bytesRead: bytesRead,
                    durationSeconds: ProcessInfo.processInfo.systemUptime - startedAt,
                    maximumConcurrentParses: activeConcurrentParses,
                    configuredMaximumConcurrentParses: configuration.maximumConcurrentParses,
                    chunkSizeBytes: configuration.chunkSizeBytes,
                    maximumLineBufferBytes: configuration.maximumLineBufferBytes,
                    sessionIndexMaximumLineBufferBytes: configuration.sessionIndexMaximumLineBufferBytes,
                    discoveryMode: discovery.mode,
                    metadataHits: metadataHits,
                    sessionIndexBytesRead: threadIndex.bytesRead,
                    sidebarStateBytesRead: sidebarStateRead?.bytesRead ?? 0,
                    sidebarStateCacheHit: sidebarStateRead?.cacheHit ?? false,
                    cacheEnabled: cache != nil,
                    cacheHits: cacheHits,
                    cacheMisses: cacheMisses,
                    cacheEntries: cache?.entryCount ?? 0,
                    cacheBytesSaved: cacheBytesSaved,
                    incrementalFiles: fileMetrics.filter { $0.incrementalBytesSaved > 0 }.count,
                    incrementalBytesSaved: fileMetrics.reduce(0) { $0 + $1.incrementalBytesSaved },
                    processMemoryBytes: resources.currentMemoryBytes,
                    processPeakMemoryBytes: resources.peakMemoryBytes,
                    cpuTimeSeconds: resources.cpuTimeSeconds,
                    physicalBytesRead: resources.physicalBytesRead,
                    physicalBytesWritten: resources.physicalBytesWritten,
                    idleWakeups: resources.idleWakeups,
                    interruptWakeups: resources.interruptWakeups,
                    voluntaryContextSwitches: resources.voluntaryContextSwitches,
                    involuntaryContextSwitches: resources.involuntaryContextSwitches,
                    fileMetrics: fileMetrics
                )
            )
        }

        let firstCount = min(files.count, prioritized.initialCount)
        let firstWorkItems = prepare(0..<firstCount)
        var lastProgressCount = 0
        if let onProgress, results.isEmpty == false {
            lastProgressCount = results.count
            await onProgress(currentResult())
        }
        _ = await Self.parseConcurrently(
            firstWorkItems,
            maximumConcurrentParses: configuration.maximumConcurrentParses,
            configuration: configuration,
            priority: .userInitiated
        ) { result in
            append(result)
            guard let onProgress else {
                return
            }
            lastProgressCount = results.count
            await onProgress(currentResult())
        }

        if let onProgress, lastProgressCount == 0 {
            lastProgressCount = results.count
            await onProgress(currentResult())
        }

        let remainingWorkItems = prepare(firstCount..<files.count)
        if let onProgress, results.count > lastProgressCount {
            lastProgressCount = results.count
            await onProgress(currentResult())
        }

        let progressStride = max(8, configuration.maximumConcurrentParses * 4)
        var completedSinceProgress = 0
        _ = await Self.parseConcurrently(
            remainingWorkItems,
            maximumConcurrentParses: configuration.maximumConcurrentParses,
            configuration: configuration,
            priority: .utility
        ) { result in
            append(result)
            completedSinceProgress += 1
            guard let onProgress, completedSinceProgress >= progressStride else {
                return
            }
            completedSinceProgress = 0
            lastProgressCount = results.count
            await onProgress(currentResult())
        }

        let finalResult = currentResult()
        if let onProgress, finalResult.sessions.count != lastProgressCount {
            await onProgress(finalResult)
        }
        return finalResult
    }

    public func summary(
        limit: Int? = nil,
        cache: CodexSessionScanCache? = nil,
        statusRateLimits: CodexRateLimits? = nil
    ) async throws -> ModexSummary {
        let result = try await scanResult(limit: limit, cache: cache)
        return ModexSummary(
            sessions: result.sessions,
            scanMetrics: result.metrics,
            statusRateLimits: statusRateLimits
        )
    }

    private static func parseConcurrently(
        _ workItems: [IndexedSessionFileCandidate],
        maximumConcurrentParses: Int,
        configuration: CodexSessionScannerConfiguration,
        priority: TaskPriority,
        onResult: ((IndexedParseResult) async -> Void)? = nil
    ) async -> [IndexedParseResult] {
        guard workItems.isEmpty == false else {
            return []
        }

        let maximumConcurrentParses = max(1, maximumConcurrentParses)
        return await withTaskGroup(of: IndexedParseResult?.self, returning: [IndexedParseResult].self) { group in
            var nextIndex = 0
            var activeTasks = 0
            var parsedResults: [IndexedParseResult] = []

            func enqueueAvailableWork() {
                while activeTasks < maximumConcurrentParses, nextIndex < workItems.count {
                    let workItem = workItems[nextIndex]
                    nextIndex += 1
                    activeTasks += 1
                    group.addTask(priority: priority) {
                        guard Task.isCancelled == false else {
                            return nil
                        }
                        guard let result = try? parseSnapshot(
                            fileURL: workItem.file.url,
                            fallbackModificationDate: workItem.file.modificationDate,
                            maximumBytes: workItem.file.fileSize,
                            checkpoint: workItem.checkpoint,
                            configuration: configuration
                        ) else {
                            return nil
                        }
                        return IndexedParseResult(index: workItem.index, result: result)
                    }
                }
            }

            enqueueAvailableWork()
            while let result = await group.next() {
                activeTasks -= 1
                if let result {
                    if onResult == nil {
                        parsedResults.append(result)
                    }
                    await onResult?(result)
                }
                enqueueAvailableWork()
            }

            return parsedResults
        }
    }

    public func sessionFiles() throws -> [URL] {
        try filesystemSessionFileCandidates().map(\.url)
    }

    public func parse(fileURL: URL) throws -> SessionSnapshot {
        try Self.parseSnapshot(
            fileURL: fileURL,
            fallbackModificationDate: Self.modificationDate(fileURL),
            maximumBytes: Self.fileSize(fileURL),
            checkpoint: nil,
            configuration: configuration
        ).snapshot
    }

    private func sessionFileDiscovery(limit: Int?) throws -> SessionFileDiscovery {
        if let index = CodexThreadIndex.recentThreads(
            codexHome: codexHome,
            limit: limit,
            includeArchived: configuration.includeArchivedSessions
        ) {
            let candidates = index.threads.compactMap { metadata -> SessionFileCandidate? in
                let values = try? metadata.fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )
                guard let fileSize = values?.fileSize else {
                    return nil
                }
                return SessionFileCandidate(
                    url: metadata.fileURL,
                    modificationDate: values?.contentModificationDate ?? metadata.recencyDate,
                    fileSize: max(0, fileSize),
                    metadata: metadata
                )
            }
            let sortedCandidates = candidates.sorted { $0.modificationDate > $1.modificationDate }
            return SessionFileDiscovery(
                candidates: limit.map { Array(sortedCandidates.prefix($0)) } ?? sortedCandidates,
                mode: CodexThreadIndex.discoveryMode
            )
        }

        let candidates = try filesystemSessionFileCandidates()
            .sorted { lhs, rhs in
                lhs.modificationDate > rhs.modificationDate
            }
        return SessionFileDiscovery(
            candidates: limit.map { Array(candidates.prefix($0)) } ?? candidates,
            mode: "filesystem"
        )
    }

    private func filesystemSessionFileCandidates() throws -> [SessionFileCandidate] {
        var candidates: [SessionFileCandidate] = []
        let directoryNames = configuration.includeArchivedSessions
            ? ["sessions", "archived_sessions"]
            : ["sessions"]
        for directoryName in directoryNames {
            let directory = codexHome.appendingPathComponent(directoryName, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let modificationDate = values?.contentModificationDate ?? Self.modificationDate(url)
                let fileSize = values?.fileSize ?? Self.fileSize(url)
                candidates.append(
                    SessionFileCandidate(
                        url: url,
                        modificationDate: modificationDate,
                        fileSize: max(0, fileSize),
                        metadata: nil
                    )
                )
            }
        }
        return candidates
    }

    private static func apply(metadata: CodexThreadMetadata, to snapshot: inout SessionSnapshot) {
        // The Codex index identifies the rollout file authoritatively. Sub-agent logs may
        // repeat inherited parent metadata later in the file, but that must not replace
        // the child's own session identity.
        snapshot.sessionID = metadata.sessionID
        snapshot.threadName = metadata.threadName ?? snapshot.threadName
        snapshot.workingDirectory = snapshot.workingDirectory ?? metadata.workingDirectory
        snapshot.gitOriginURL = metadata.gitOriginURL ?? snapshot.gitOriginURL
        snapshot.model = snapshot.model ?? metadata.model
        snapshot.reasoningEffort = snapshot.reasoningEffort ?? metadata.reasoningEffort
        snapshot.source = metadata.source ?? snapshot.source
        snapshot.cliVersion = metadata.cliVersion ?? snapshot.cliVersion
        snapshot.modelProvider = metadata.modelProvider ?? snapshot.modelProvider
        snapshot.agentNickname = metadata.agentNickname ?? snapshot.agentNickname
        snapshot.agentRole = metadata.agentRole ?? snapshot.agentRole
        snapshot.agentPath = metadata.agentPath ?? snapshot.agentPath
        snapshot.parentThreadID = metadata.parentThreadID ?? snapshot.parentThreadID
        snapshot.threadSource = metadata.threadSource ?? snapshot.threadSource
        snapshot.isArchived = metadata.archived
        snapshot.updatedAt = max(snapshot.updatedAt ?? .distantPast, metadata.recencyDate)
    }

    private static func parseSnapshot(
        fileURL: URL,
        fallbackModificationDate: Date,
        maximumBytes: Int,
        checkpoint: FastParserCheckpoint?,
        configuration: CodexSessionScannerConfiguration
    ) throws -> ParseResult {
        try FastCodexJSONLParser(configuration: configuration)
            .parse(
                fileURL: fileURL,
                fallbackModificationDate: fallbackModificationDate,
                maximumBytes: maximumBytes,
                checkpoint: checkpoint
            )
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func threadNames(
        for files: [SessionFileCandidate],
        cachedResults: [Int: ParseResult]
    ) -> SessionIndexResult {
        var requiresCompleteIndex = false
        var missingMetadataSessionIDs: Set<String> = []
        for (index, file) in files.enumerated() {
            if file.metadata?.threadName?.isEmpty == false
                || cachedResults[index]?.snapshot.threadName?.isEmpty == false
            {
                continue
            }
            if let sessionID = file.metadata?.sessionID ?? Self.sessionID(from: file.url) {
                missingMetadataSessionIDs.insert(sessionID)
            } else {
                requiresCompleteIndex = true
            }
        }
        if requiresCompleteIndex {
            return threadNamesBySessionID(matching: nil)
        }
        return threadNamesBySessionID(matching: missingMetadataSessionIDs)
    }

    private static func sessionID(from fileURL: URL) -> String? {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        guard fileName.count >= 36 else {
            return nil
        }
        let candidate = String(fileName.suffix(36))
        return UUID(uuidString: candidate) == nil ? nil : candidate
    }

    private static func prioritizedCandidates(
        _ candidates: [SessionFileCandidate],
        sidebarState: CodexSidebarState?,
        initialCountPerScope: Int
    ) -> (candidates: [SessionFileCandidate], initialCount: Int) {
        let initialCountPerScope = max(1, initialCountPerScope)
        guard let sidebarState else {
            let initialCandidates = Array(
                candidates.lazy.filter { $0.isSubagent == false }.prefix(initialCountPerScope)
            )
            guard initialCandidates.isEmpty == false else {
                return (candidates, min(candidates.count, initialCountPerScope))
            }
            let initialPaths = Set(initialCandidates.map { $0.url.path })
            let remainingCandidates = candidates.filter { initialPaths.contains($0.url.path) == false }
            return (initialCandidates + remainingCandidates, initialCandidates.count)
        }

        var projectCount = 0
        var taskCount = 0
        var initialPaths: Set<String> = []
        initialPaths.reserveCapacity(initialCountPerScope * 2)

        for candidate in candidates {
            guard candidate.isSubagent == false else {
                continue
            }
            guard let sessionID = candidate.metadata?.sessionID ?? sessionID(from: candidate.url) else {
                continue
            }
            switch sidebarState.scope(for: sessionID) {
            case .project where projectCount < initialCountPerScope:
                projectCount += 1
                initialPaths.insert(candidate.url.path)
            case .task where taskCount < initialCountPerScope:
                taskCount += 1
                initialPaths.insert(candidate.url.path)
            default:
                break
            }
            if projectCount == initialCountPerScope, taskCount == initialCountPerScope {
                break
            }
        }

        guard initialPaths.isEmpty == false else {
            return (candidates, min(candidates.count, initialCountPerScope))
        }
        let initialCandidates = candidates.filter { initialPaths.contains($0.url.path) }
        let remainingCandidates = candidates.filter { initialPaths.contains($0.url.path) == false }
        return (initialCandidates + remainingCandidates, initialCandidates.count)
    }

    private func threadNamesBySessionID(matching sessionIDs: Set<String>?) -> SessionIndexResult {
        if sessionIDs?.isEmpty == true {
            return SessionIndexResult(threadNames: [:], bytesRead: 0)
        }

        let indexURL = codexHome.appendingPathComponent("session_index.jsonl", isDirectory: false)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return SessionIndexResult(threadNames: [:], bytesRead: 0)
        }

        return (try? SessionIndexParser(configuration: configuration).parse(fileURL: indexURL, matching: sessionIDs))
            ?? SessionIndexResult(threadNames: [:], bytesRead: 0)
    }
}

public final class CodexSessionScanCache: @unchecked Sendable {
    private struct Storage: Sendable {
        var entries: [SessionScanCacheKey: ParseResult] = [:]
        var keysByPath: [String: SessionScanCacheKey] = [:]
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    public init() {}

    public var entryCount: Int {
        storage.withLock { $0.entries.count }
    }

    public func removeAll() {
        storage.withLock { storage in
            storage.entries.removeAll(keepingCapacity: true)
            storage.keysByPath.removeAll(keepingCapacity: true)
        }
    }

    fileprivate func result(for key: SessionScanCacheKey) -> ParseResult? {
        storage.withLock { $0.entries[key] }
    }

    fileprivate func checkpointForGrowth(of key: SessionScanCacheKey) -> FastParserCheckpoint? {
        storage.withLock { storage in
            guard let previousKey = storage.keysByPath[key.path],
                  previousKey.fileSize < key.fileSize,
                  let result = storage.entries[previousKey],
                  result.checkpoint.processedBytes == previousKey.fileSize
            else {
                return nil
            }
            return result.checkpoint
        }
    }

    fileprivate func store(_ result: ParseResult, for key: SessionScanCacheKey) {
        storage.withLock { storage in
            if let previousKey = storage.keysByPath[key.path], previousKey != key {
                storage.entries.removeValue(forKey: previousKey)
            }
            storage.entries[key] = result
            storage.keysByPath[key.path] = key
        }
    }
}

private struct SessionScanCacheKey: Hashable, Sendable {
    let path: String
    let fileSize: Int
    let modificationDate: Date

    init(candidate: SessionFileCandidate) {
        path = candidate.url.path
        fileSize = candidate.fileSize
        modificationDate = candidate.modificationDate
    }
}

fileprivate struct SessionFileCandidate: Sendable {
    let url: URL
    let modificationDate: Date
    let fileSize: Int
    let metadata: CodexThreadMetadata?

    var isSubagent: Bool {
        if let source = metadata?.threadSource,
           source.caseInsensitiveCompare("subagent") == .orderedSame
        {
            return true
        }
        return metadata?.parentThreadID?.isEmpty == false
    }
}

private struct SessionFileDiscovery: Sendable {
    let candidates: [SessionFileCandidate]
    let mode: String
}

private struct IndexedSessionFileCandidate: Sendable {
    let index: Int
    let file: SessionFileCandidate
    let checkpoint: FastParserCheckpoint?
}

private struct IndexedParseResult: Sendable {
    let index: Int
    let result: ParseResult
}

fileprivate struct ParseResult: Sendable {
    let snapshot: SessionSnapshot
    let metrics: FileScanMetrics
    let checkpoint: FastParserCheckpoint

    func asCacheHit() -> ParseResult {
        ParseResult(snapshot: snapshot, metrics: metrics.asCacheHit(), checkpoint: checkpoint)
    }
}

fileprivate struct FastParserCheckpoint: Sendable {
    let snapshot: SessionSnapshot
    let parserState: FastParserState
    let pendingLine: Data
    let skippingOversizedLine: Bool
    let processedBytes: Int
    let tailFingerprint: Data
    let maximumBufferedLineBytes: Int
    let oversizedLines: Int
}

private struct SessionIndexResult: Sendable {
    let threadNames: [String: String]
    let bytesRead: Int
}

private final class SessionIndexParser {
    private let configuration: CodexSessionScannerConfiguration

    init(configuration: CodexSessionScannerConfiguration) {
        self.configuration = configuration
    }

    func parse(fileURL: URL, matching sessionIDs: Set<String>?) throws -> SessionIndexResult {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var threadNames: [String: String] = [:]
        var pendingLine = Data()
        var skippingOversizedLine = false
        var bytesRead = 0

        while true {
            let didRead = try autoreleasepool { () throws -> Bool in
                guard let chunk = try handle.read(upToCount: configuration.chunkSizeBytes),
                      chunk.isEmpty == false
                else {
                    return false
                }
                bytesRead += chunk.count
                var lineStart = chunk.startIndex
                var index = chunk.startIndex

                while index < chunk.endIndex {
                    if chunk[index] == FastJSONPattern.lineFeed {
                        if skippingOversizedLine {
                            skippingOversizedLine = false
                        } else if pendingLine.isEmpty {
                            if lineStart < index {
                                parseLine(chunk[lineStart..<index], matching: sessionIDs, into: &threadNames)
                            }
                        } else {
                            pendingLine.append(chunk[lineStart..<index])
                            parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], matching: sessionIDs, into: &threadNames)
                            pendingLine.removeAll(keepingCapacity: false)
                        }
                        lineStart = chunk.index(after: index)
                    }
                    index = chunk.index(after: index)
                }

                if lineStart < chunk.endIndex, skippingOversizedLine == false {
                    let segment = chunk[lineStart..<chunk.endIndex]
                    if pendingLine.count + segment.count > configuration.sessionIndexMaximumLineBufferBytes {
                        let remainingBytes = max(0, configuration.sessionIndexMaximumLineBufferBytes - pendingLine.count)
                        pendingLine.append(segment.prefix(remainingBytes))
                        parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], matching: sessionIDs, into: &threadNames)
                        pendingLine.removeAll(keepingCapacity: false)
                        skippingOversizedLine = true
                    } else {
                        pendingLine.append(segment)
                    }
                }

                return true
            }
            guard didRead else {
                break
            }
            if let sessionIDs, threadNames.count == sessionIDs.count {
                return SessionIndexResult(threadNames: threadNames, bytesRead: bytesRead)
            }
        }

        if skippingOversizedLine == false, pendingLine.isEmpty == false {
            parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], matching: sessionIDs, into: &threadNames)
        }

        return SessionIndexResult(threadNames: threadNames, bytesRead: bytesRead)
    }

    private func parseLine(
        _ line: Data.SubSequence,
        matching sessionIDs: Set<String>?,
        into threadNames: inout [String: String]
    ) {
        guard let sessionID = FastJSONValue.string(after: FastJSONPattern.id, in: line),
              sessionIDs?.contains(sessionID) ?? true,
              let threadName = FastJSONValue.string(after: FastJSONPattern.threadName, in: line),
              threadName.isEmpty == false
        else {
            return
        }
        threadNames[sessionID] = threadName
    }
}

private final class FastCodexJSONLParser {
    static let parserMode = "streaming-byte-scan"
    private static let fingerprintSize = 64
    private static let maximumFailureSamples = 24

    private let configuration: CodexSessionScannerConfiguration

    init(configuration: CodexSessionScannerConfiguration) {
        self.configuration = configuration
    }

    func parse(
        fileURL: URL,
        fallbackModificationDate: Date,
        maximumBytes: Int,
        checkpoint: FastParserCheckpoint?
    ) throws -> ParseResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let maximumBytes = max(0, maximumBytes)
        var snapshot = SessionSnapshot(fileURL: fileURL)
        var pendingLine = Data()
        var skippingOversizedLine = false
        var bytesRead = 0
        var parsedBytes = 0
        var processedBytes = 0
        var maximumBufferedLineBytes = 0
        var oversizedLines = 0
        var parserState = FastParserState()
        var tailFingerprint = Data()
        var incrementalBytesSaved = 0

        if let checkpoint,
           checkpoint.processedBytes < maximumBytes,
           try validate(checkpoint: checkpoint, using: handle, bytesRead: &bytesRead)
        {
            snapshot = checkpoint.snapshot
            pendingLine = checkpoint.pendingLine
            skippingOversizedLine = checkpoint.skippingOversizedLine
            processedBytes = checkpoint.processedBytes
            maximumBufferedLineBytes = checkpoint.maximumBufferedLineBytes
            oversizedLines = checkpoint.oversizedLines
            parserState = checkpoint.parserState
            tailFingerprint = checkpoint.tailFingerprint
            incrementalBytesSaved = checkpoint.processedBytes
            try handle.seek(toOffset: UInt64(checkpoint.processedBytes))
        } else {
            try handle.seek(toOffset: 0)
        }

        while processedBytes + parsedBytes < maximumBytes {
            let didRead = try autoreleasepool { () throws -> Bool in
                let readSize = min(configuration.chunkSizeBytes, maximumBytes - processedBytes - parsedBytes)
                guard let chunk = try handle.read(upToCount: readSize), chunk.isEmpty == false else {
                    return false
                }
                bytesRead += chunk.count
                parsedBytes += chunk.count
                updateTailFingerprint(with: chunk, fingerprint: &tailFingerprint)
                var lineStart = chunk.startIndex
                var index = chunk.startIndex

                while index < chunk.endIndex {
                    if chunk[index] == FastJSONPattern.lineFeed {
                        if skippingOversizedLine {
                            skippingOversizedLine = false
                        } else if pendingLine.isEmpty {
                            if lineStart < index {
                                parseLine(chunk[lineStart..<index], into: &snapshot, state: &parserState)
                            }
                        } else {
                            let segment = chunk[lineStart..<index]
                            if pendingLine.count + segment.count > configuration.maximumLineBufferBytes {
                                appendCapped(segment, to: &pendingLine)
                                maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                                parseLine(
                                    pendingLine[pendingLine.startIndex..<pendingLine.endIndex],
                                    into: &snapshot,
                                    state: &parserState
                                )
                                pendingLine.removeAll(keepingCapacity: false)
                                oversizedLines += 1
                            } else {
                                pendingLine.append(segment)
                                maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                                parseLine(
                                    pendingLine[pendingLine.startIndex..<pendingLine.endIndex],
                                    into: &snapshot,
                                    state: &parserState
                                )
                                pendingLine.removeAll(keepingCapacity: false)
                            }
                        }

                        lineStart = chunk.index(after: index)
                    }
                    index = chunk.index(after: index)
                }

                if lineStart < chunk.endIndex, skippingOversizedLine == false {
                    let segment = chunk[lineStart..<chunk.endIndex]
                    if pendingLine.count + segment.count > configuration.maximumLineBufferBytes {
                        appendCapped(segment, to: &pendingLine)
                        maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                        // The fields Modex needs occur near the front of Codex JSONL records.
                        // Parse the retained prefix, then skip the rest of this pathological line.
                        parseLine(
                            pendingLine[pendingLine.startIndex..<pendingLine.endIndex],
                            into: &snapshot,
                            state: &parserState
                        )
                        pendingLine.removeAll(keepingCapacity: false)
                        oversizedLines += 1
                        skippingOversizedLine = true
                    } else {
                        pendingLine.append(segment)
                        maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                    }
                }

                return true
            }
            if didRead == false {
                break
            }
        }

        let rawSnapshot = snapshot
        let rawParserState = parserState
        let rawPendingLine = pendingLine
        let rawSkippingOversizedLine = skippingOversizedLine

        if skippingOversizedLine == false, pendingLine.isEmpty == false {
            parseLine(
                pendingLine[pendingLine.startIndex..<pendingLine.endIndex],
                into: &snapshot,
                state: &parserState
            )
        }

        if snapshot.updatedAt == nil {
            snapshot.updatedAt = fallbackModificationDate
        }

        return ParseResult(
            snapshot: snapshot,
            metrics: FileScanMetrics(
                fileURL: fileURL,
                sessionID: snapshot.sessionID,
                threadName: snapshot.threadName,
                workingDirectory: snapshot.workingDirectory,
                bytesRead: bytesRead,
                durationSeconds: ProcessInfo.processInfo.systemUptime - startedAt,
                tokenEvents: snapshot.tokenEvents.count,
                compactionEvents: snapshot.compactionEvents,
                maximumBufferedLineBytes: maximumBufferedLineBytes,
                oversizedLines: oversizedLines,
                incrementalBytesSaved: incrementalBytesSaved
            ),
            checkpoint: FastParserCheckpoint(
                snapshot: rawSnapshot,
                parserState: rawParserState,
                pendingLine: rawPendingLine,
                skippingOversizedLine: rawSkippingOversizedLine,
                processedBytes: processedBytes + parsedBytes,
                tailFingerprint: tailFingerprint,
                maximumBufferedLineBytes: maximumBufferedLineBytes,
                oversizedLines: oversizedLines
            )
        )
    }

    private func validate(
        checkpoint: FastParserCheckpoint,
        using handle: FileHandle,
        bytesRead: inout Int
    ) throws -> Bool {
        let fingerprintSize = checkpoint.tailFingerprint.count
        guard checkpoint.processedBytes >= fingerprintSize else {
            return false
        }
        guard fingerprintSize > 0 else {
            return checkpoint.processedBytes == 0
        }

        try handle.seek(toOffset: UInt64(checkpoint.processedBytes - fingerprintSize))
        let currentTail = try handle.read(upToCount: fingerprintSize) ?? Data()
        bytesRead += currentTail.count
        return currentTail == checkpoint.tailFingerprint
    }

    private func updateTailFingerprint(with chunk: Data, fingerprint: inout Data) {
        if chunk.count >= Self.fingerprintSize {
            fingerprint = Data(chunk.suffix(Self.fingerprintSize))
            return
        }

        let overflow = fingerprint.count + chunk.count - Self.fingerprintSize
        if overflow > 0 {
            fingerprint.removeFirst(overflow)
        }
        fingerprint.append(chunk)
    }

    private func appendCapped(_ segment: Data.SubSequence, to pendingLine: inout Data) {
        let remainingBytes = max(0, configuration.maximumLineBufferBytes - pendingLine.count)
        guard remainingBytes > 0 else {
            return
        }

        pendingLine.append(segment.prefix(remainingBytes))
    }

    private func parseLine(
        _ line: Data.SubSequence,
        into snapshot: inout SessionSnapshot,
        state: inout FastParserState
    ) {
        guard let topLevelType = FastJSONValue.string(after: FastJSONPattern.type, in: line) else {
            return
        }

        let isSessionMeta = topLevelType == "session_meta"
        let isOwnSessionMeta = isSessionMeta && state.hasParsedSessionMetadata == false
        let payloadType = isSessionMeta ? nil : FastJSONValue.string(after: FastJSONPattern.payloadType, in: line)
        let isTokenCount = topLevelType == "token_count" || payloadType == "token_count"
        let isTurnContext = topLevelType == "turn_context" || payloadType == "turn_context"
        let isThreadSettings = payloadType == "thread_settings_applied"
        let isTaskComplete = payloadType == "task_complete"
        let isCommandEnd = payloadType == "exec_command_end"
        let isToolCall = topLevelType == "response_item" && Self.isToolCallPayloadType(payloadType)
        let isToolOutput = topLevelType == "response_item" && Self.isToolOutputPayloadType(payloadType)
        let isPatchEnd = payloadType == "patch_apply_end"
        let isMCPToolCallEnd = payloadType == "mcp_tool_call_end"
        let isWebSearchEnd = payloadType == "web_search_end"
        let isSubagentActivity = payloadType == "sub_agent_activity"
        let isTurnAborted = payloadType == "turn_aborted"
        let hasFileChanges = FastJSONValue.contains(FastJSONPattern.changes, in: line)
        let isCompaction = topLevelType.contains("compact")
            || payloadType?.contains("compact") == true

        guard isOwnSessionMeta
            || isTokenCount
            || isTurnContext
            || isThreadSettings
            || isTaskComplete
            || isCommandEnd
            || isToolCall
            || isToolOutput
            || isPatchEnd
            || isMCPToolCallEnd
            || isWebSearchEnd
            || isSubagentActivity
            || isTurnAborted
            || hasFileChanges
            || isCompaction
        else {
            return
        }

        let timestamp = dateValue(after: FastJSONPattern.timestamp, in: line)
        if snapshot.startedAt == nil {
            snapshot.startedAt = timestamp
        }
        snapshot.updatedAt = timestamp ?? snapshot.updatedAt

        if isOwnSessionMeta {
            state.hasParsedSessionMetadata = true
            snapshot.sessionID = FastJSONValue.string(after: FastJSONPattern.payloadID, in: line)
                ?? FastJSONValue.string(after: FastJSONPattern.id, in: line)
                ?? snapshot.sessionID
            snapshot.workingDirectory = FastJSONValue.string(after: FastJSONPattern.cwd, in: line) ?? snapshot.workingDirectory
            snapshot.gitOriginURL = nonEmpty(FastJSONValue.string(after: FastJSONPattern.repositoryURL, in: line))
                ?? snapshot.gitOriginURL
            snapshot.cliVersion = nonEmpty(FastJSONValue.string(after: FastJSONPattern.cliVersion, in: line))
                ?? snapshot.cliVersion
            snapshot.modelProvider = nonEmpty(FastJSONValue.string(after: FastJSONPattern.modelProvider, in: line))
                ?? snapshot.modelProvider
            snapshot.source = nonEmpty(FastJSONValue.string(after: FastJSONPattern.source, in: line))
                ?? snapshot.source
            snapshot.agentNickname = nonEmpty(FastJSONValue.string(after: FastJSONPattern.agentNickname, in: line))
                ?? snapshot.agentNickname
            snapshot.agentRole = nonEmpty(FastJSONValue.string(after: FastJSONPattern.agentRole, in: line))
                ?? snapshot.agentRole
            snapshot.agentPath = nonEmpty(FastJSONValue.string(after: FastJSONPattern.agentPath, in: line))
                ?? snapshot.agentPath
            snapshot.parentThreadID = nonEmpty(FastJSONValue.string(after: FastJSONPattern.parentThreadID, in: line))
                ?? snapshot.parentThreadID
            snapshot.threadSource = nonEmpty(FastJSONValue.string(after: FastJSONPattern.threadSource, in: line))
                ?? snapshot.threadSource
        }

        if isTokenCount {
            appendTokenEvent(line: line, timestamp: timestamp, snapshot: &snapshot)
        }

        if isTurnContext {
            applyTurnContext(line: line, snapshot: &snapshot)
        }

        if isThreadSettings {
            applyThreadSettings(line: line, snapshot: &snapshot)
        }

        if isTaskComplete {
            applyTaskComplete(line: line, snapshot: &snapshot)
        }

        if isCommandEnd {
            applyCommandEnd(line: line, snapshot: &snapshot, state: &state)
        }

        if isToolCall {
            snapshot.toolCallEvents += 1
            applyToolCall(line: line, snapshot: &snapshot, state: &state)
        }

        if isToolOutput {
            applyToolOutput(
                line: line,
                payloadType: payloadType,
                snapshot: &snapshot,
                state: &state
            )
        }

        if isPatchEnd {
            snapshot.patchEvents += 1
            if FastJSONValue.bool(after: FastJSONPattern.success, in: line) == false {
                snapshot.failedPatchEvents += 1
            }
        }

        if isMCPToolCallEnd {
            snapshot.mcpToolCallEvents += 1
        }

        if isWebSearchEnd {
            snapshot.webSearchEvents += 1
        }

        if isSubagentActivity {
            snapshot.subagentActivityEvents += 1
        }

        if isTurnAborted {
            snapshot.abortedTurnEvents += 1
        }

        if hasFileChanges {
            snapshot.changedFileEvents += FastJSONValue.topLevelObjectKeyCount(
                after: FastJSONPattern.changes,
                in: line
            )
        }

        if isCompaction, state.shouldCountCompaction(at: timestamp) {
            snapshot.compactionEvents += 1
        }
    }

    private static func isToolCallPayloadType(_ payloadType: String?) -> Bool {
        guard let payloadType else {
            return false
        }
        return payloadType.contains("call") && payloadType.contains("output") == false
    }

    private static func isToolOutputPayloadType(_ payloadType: String?) -> Bool {
        payloadType == "function_call_output" || payloadType == "custom_tool_call_output"
    }

    private func applyTurnContext(line: Data.SubSequence, snapshot: inout SessionSnapshot) {
        snapshot.model = nonEmpty(FastJSONValue.string(after: FastJSONPattern.model, in: line)) ?? snapshot.model
        snapshot.reasoningEffort = nonEmpty(
            FastJSONValue.string(after: FastJSONPattern.reasoningEffort, in: line)
        )
            ?? nonEmpty(FastJSONValue.string(after: FastJSONPattern.effort, in: line))
            ?? snapshot.reasoningEffort
        snapshot.summaryMode = nonEmpty(FastJSONValue.string(after: FastJSONPattern.summary, in: line))
            ?? snapshot.summaryMode
        snapshot.realtimeActive = FastJSONValue.bool(after: FastJSONPattern.realtimeActive, in: line)
            ?? snapshot.realtimeActive
        snapshot.personality = nonEmpty(FastJSONValue.string(after: FastJSONPattern.personality, in: line))
            ?? snapshot.personality
        snapshot.collaborationMode = nonEmpty(
            FastJSONValue.string(after: FastJSONPattern.collaborationMode, in: line)
        )
            ?? nonEmpty(FastJSONValue.string(after: FastJSONPattern.collaborationModeObject, in: line))
            ?? snapshot.collaborationMode
    }

    private func applyThreadSettings(line: Data.SubSequence, snapshot: inout SessionSnapshot) {
        applyTurnContext(line: line, snapshot: &snapshot)
        snapshot.serviceTier = nonEmpty(FastJSONValue.string(after: FastJSONPattern.serviceTier, in: line))
            ?? snapshot.serviceTier
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else {
            return nil
        }
        return value
    }

    private func appendTokenEvent(line: Data.SubSequence, timestamp: Date?, snapshot: inout SessionSnapshot) {
        let limits = rateLimits(line)
        guard let last = FastJSONValue.object(after: FastJSONPattern.lastTokenUsage, in: line),
              let total = FastJSONValue.object(after: FastJSONPattern.totalTokenUsage, in: line)
        else {
            guard let limits else {
                return
            }
            snapshot.tokenEvents.append(
                TokenEvent(
                    timestamp: timestamp,
                    lastUsage: TokenUsage(),
                    totalUsage: TokenUsage(),
                    modelContextWindow: nil,
                    rateLimits: limits
                )
            )
            return
        }

        snapshot.tokenEvents.append(
            TokenEvent(
                timestamp: timestamp,
                lastUsage: tokenUsage(last),
                totalUsage: tokenUsage(total),
                modelContextWindow: FastJSONValue.int(after: FastJSONPattern.modelContextWindow, in: line),
                rateLimits: limits
            )
        )
    }

    private func applyTaskComplete(line: Data.SubSequence, snapshot: inout SessionSnapshot) {
        if let duration = FastJSONValue.int(after: FastJSONPattern.durationMilliseconds, in: line), duration >= 0 {
            snapshot.turnDurationsMilliseconds.append(duration)
        }
        if let timeToFirstToken = FastJSONValue.int(after: FastJSONPattern.timeToFirstTokenMilliseconds, in: line),
           timeToFirstToken >= 0
        {
            snapshot.timeToFirstTokenMilliseconds.append(timeToFirstToken)
        }
    }

    private func applyCommandEnd(
        line: Data.SubSequence,
        snapshot: inout SessionSnapshot,
        state: inout FastParserState
    ) {
        let callID = FastJSONValue.string(after: FastJSONPattern.callID, in: line)
        if let callID {
            if state.countedCommandCallIDs.insert(callID).inserted {
                snapshot.commandEvents += 1
            }
        } else {
            snapshot.commandEvents += 1
        }
        if let exitCode = FastJSONValue.int(after: FastJSONPattern.exitCode, in: line),
           exitCode != 0
        {
            recordCommandFailure(
                exitCode: exitCode,
                commandName: sanitizedCommandName(
                    FastJSONValue.stringArray(after: FastJSONPattern.command, in: line).first
                ),
                timestamp: dateValue(after: FastJSONPattern.timestamp, in: line),
                snapshot: &snapshot
            )
        }
    }

    private func applyToolCall(
        line: Data.SubSequence,
        snapshot: inout SessionSnapshot,
        state: inout FastParserState
    ) {
        guard let name = FastJSONValue.string(after: FastJSONPattern.name, in: line),
              name == "exec" || name == "exec_command",
              let callID = FastJSONValue.string(after: FastJSONPattern.callID, in: line)
        else {
            return
        }

        if state.countedCommandCallIDs.insert(callID).inserted {
            snapshot.commandEvents += 1
        }
        state.pendingCommandNames[callID] = commandLabel(for: name, in: line)
    }

    private func applyToolOutput(
        line: Data.SubSequence,
        payloadType: String?,
        snapshot: inout SessionSnapshot,
        state: inout FastParserState
    ) {
        guard let callID = FastJSONValue.string(after: FastJSONPattern.callID, in: line),
              let commandName = state.pendingCommandNames.removeValue(forKey: callID),
              let output = toolOutputText(line, payloadType: payloadType)
        else {
            return
        }

        guard let exitCode = commandExitCode(output), exitCode != 0 else {
            return
        }
        recordCommandFailure(
            exitCode: exitCode,
            commandName: commandName,
            timestamp: dateValue(after: FastJSONPattern.timestamp, in: line),
            snapshot: &snapshot
        )
    }

    private func toolOutputText(_ line: Data.SubSequence, payloadType: String?) -> String? {
        if payloadType == "custom_tool_call_output",
           FastJSONValue.contains(FastJSONPattern.outputArray, in: line)
        {
            return FastJSONValue.stringPrefix(after: FastJSONPattern.text, in: line, maximumBytes: 512)
        }
        return FastJSONValue.stringPrefix(after: FastJSONPattern.output, in: line, maximumBytes: 512)
    }

    private func commandExitCode(_ output: String) -> Int? {
        if output.hasPrefix("Script failed") {
            return 1
        }
        if output.hasPrefix("Script completed") || output.hasPrefix("Script running") {
            return 0
        }

        let bytes = Data(output.utf8)
        if let exitCode = FastJSONValue.int(after: FastJSONPattern.exitCode, in: bytes[...]) {
            return exitCode
        }
        return FastJSONValue.int(after: FastJSONPattern.exitCodeText, in: bytes[...])
            ?? FastJSONValue.int(after: FastJSONPattern.processExitCodeText, in: bytes[...])
    }

    private func recordCommandFailure(
        exitCode: Int,
        commandName: String?,
        timestamp: Date?,
        snapshot: inout SessionSnapshot
    ) {
        snapshot.failedCommandEvents += 1
        snapshot.failedCommandSummaries.append(
            CommandFailureSummary(
                timestamp: timestamp,
                commandName: commandName,
                exitCode: exitCode
            )
        )
        if snapshot.failedCommandSummaries.count > Self.maximumFailureSamples {
            snapshot.failedCommandSummaries.removeFirst()
        }
    }

    private func commandLabel(for toolName: String, in line: Data.SubSequence) -> String {
        guard let command = FastJSONValue.commandPrefix(in: line),
              let label = sanitizedCommandName(command)
        else {
            return toolName
        }
        return label
    }

    private func sanitizedCommandName(_ command: String?) -> String? {
        guard let command, command.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: command).lastPathComponent
    }

    private func rateLimits(_ line: Data.SubSequence) -> CodexRateLimits? {
        guard let object = FastJSONValue.object(after: FastJSONPattern.rateLimits, in: line) else {
            return nil
        }

        let generalBucket = rateLimitBucket(
            object,
            defaultID: CodexRateLimitBucket.generalID,
            defaultName: "General"
        )
        let individualBucket = FastJSONValue
            .object(after: FastJSONPattern.individualLimit, in: object)
            .flatMap {
                rateLimitBucket($0, defaultID: nil, defaultName: nil)
            }
        let planType = FastJSONValue.string(after: FastJSONPattern.planType, in: object)
        let reachedType = FastJSONValue.string(after: FastJSONPattern.rateLimitReachedType, in: object)
        let buckets = [generalBucket, individualBucket].compactMap(\.self)

        guard buckets.isEmpty == false
            || planType != nil
            || reachedType != nil
        else {
            return nil
        }

        return CodexRateLimits(
            buckets: buckets,
            planType: planType,
            reachedType: reachedType
        )
    }

    private func rateLimitBucket(
        _ object: Data.SubSequence,
        defaultID: String?,
        defaultName: String?
    ) -> CodexRateLimitBucket? {
        let primary = FastJSONValue
            .object(after: FastJSONPattern.primaryRateLimit, in: object)
            .flatMap(rateLimitWindow)
        let secondary = FastJSONValue
            .object(after: FastJSONPattern.secondaryRateLimit, in: object)
            .flatMap(rateLimitWindow)
        let limitID = FastJSONValue.string(after: FastJSONPattern.limitID, in: object) ?? defaultID
        let limitName = FastJSONValue.string(after: FastJSONPattern.limitName, in: object) ?? defaultName
        let planType = FastJSONValue.string(after: FastJSONPattern.planType, in: object)

        guard primary != nil
            || secondary != nil
            || limitID != nil
            || limitName != nil
            || planType != nil
        else {
            return nil
        }

        return CodexRateLimitBucket(
            id: limitID,
            name: limitName,
            primary: primary,
            secondary: secondary,
            planType: planType
        )
    }

    private func rateLimitWindow(_ object: Data.SubSequence) -> CodexRateLimitWindow? {
        guard let usedPercent = FastJSONValue.double(after: FastJSONPattern.usedPercent, in: object) else {
            return nil
        }

        let resetTimestamp = FastJSONValue.int(after: FastJSONPattern.resetsAt, in: object)
        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: FastJSONValue.int(after: FastJSONPattern.windowMinutes, in: object),
            resetsAt: resetTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func tokenUsage(_ object: Data.SubSequence) -> TokenUsage {
        TokenUsage(
            inputTokens: FastJSONValue.int(after: FastJSONPattern.inputTokens, in: object) ?? 0,
            cachedInputTokens: FastJSONValue.int(after: FastJSONPattern.cachedInputTokens, in: object) ?? 0,
            outputTokens: FastJSONValue.int(after: FastJSONPattern.outputTokens, in: object) ?? 0,
            reasoningOutputTokens: FastJSONValue.int(after: FastJSONPattern.reasoningOutputTokens, in: object) ?? 0,
            totalTokens: FastJSONValue.int(after: FastJSONPattern.totalTokens, in: object) ?? 0
        )
    }

    private func dateValue(after pattern: [UInt8], in bytes: Data.SubSequence) -> Date? {
        FastJSONValue.iso8601Date(after: pattern, in: bytes)
    }

}

private struct FastParserState {
    var hasParsedSessionMetadata = false
    var pendingCommandNames: [String: String] = [:]
    var countedCommandCallIDs: Set<String> = []
    private var lastCompactionTimestamp: Date?

    mutating func shouldCountCompaction(at timestamp: Date?) -> Bool {
        guard let timestamp else {
            return true
        }
        defer {
            lastCompactionTimestamp = timestamp
        }
        guard let lastCompactionTimestamp else {
            return true
        }
        return abs(timestamp.timeIntervalSince(lastCompactionTimestamp)) > 1
    }
}

private enum FastJSONValue {
    static func string(after pattern: [UInt8], in bytes: Data.SubSequence) -> String? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }
        return jsonString(startingAt: range.upperBound, in: bytes)
    }

    static func stringPrefix(
        after pattern: [UInt8],
        in bytes: Data.SubSequence,
        maximumBytes: Int
    ) -> String? {
        guard maximumBytes > 0,
              let range = range(of: pattern, in: bytes)
        else {
            return nil
        }

        var output: [UInt8] = []
        output.reserveCapacity(min(maximumBytes, 512))
        var index = range.upperBound
        while index < bytes.endIndex, output.count < maximumBytes {
            let byte = bytes[index]
            if byte == FastJSONPattern.quote {
                break
            }
            if byte == FastJSONPattern.backslash {
                let nextIndex = bytes.index(after: index)
                guard nextIndex < bytes.endIndex else {
                    break
                }
                appendEscapedByte(bytes[nextIndex], to: &output)
                index = bytes.index(after: nextIndex)
                continue
            }
            output.append(byte)
            index = bytes.index(after: index)
        }
        return output.isEmpty ? nil : String(decoding: output, as: UTF8.self)
    }

    static func commandPrefix(in bytes: Data.SubSequence) -> String? {
        for pattern in FastJSONPattern.commandPrefixes {
            guard let range = range(of: pattern, in: bytes) else {
                continue
            }

            var output: [UInt8] = []
            output.reserveCapacity(32)
            var index = range.upperBound
            while index < bytes.endIndex, output.count < 96 {
                let byte = bytes[index]
                if byte == FastJSONPattern.space
                    || byte == FastJSONPattern.tab
                    || byte == FastJSONPattern.lineFeed
                    || byte == FastJSONPattern.carriageReturn
                    || byte == FastJSONPattern.quote
                    || byte == FastJSONPattern.backslash
                    || byte == FastJSONPattern.semicolon
                    || byte == FastJSONPattern.ampersand
                    || byte == FastJSONPattern.pipe
                {
                    break
                }
                output.append(byte)
                index = bytes.index(after: index)
            }
            if output.isEmpty == false {
                return String(decoding: output, as: UTF8.self)
            }
        }
        return nil
    }

    static func int(after pattern: [UInt8], in bytes: Data.SubSequence) -> Int? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }

        var index = range.upperBound
        var sign = 1
        var value = 0
        var foundDigit = false

        while index < bytes.endIndex, bytes[index] == FastJSONPattern.space {
            index = bytes.index(after: index)
        }

        if index < bytes.endIndex, bytes[index] == FastJSONPattern.minus {
            sign = -1
            index = bytes.index(after: index)
        }

        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte >= FastJSONPattern.zero, byte <= FastJSONPattern.nine else {
                break
            }
            foundDigit = true
            value = value * 10 + Int(byte - FastJSONPattern.zero)
            index = bytes.index(after: index)
        }

        return foundDigit ? value * sign : nil
    }

    static func double(after pattern: [UInt8], in bytes: Data.SubSequence) -> Double? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }

        var index = range.upperBound
        var sign = 1.0
        var whole = 0.0
        var fraction = 0.0
        var divisor = 10.0
        var foundDigit = false

        while index < bytes.endIndex, bytes[index] == FastJSONPattern.space {
            index = bytes.index(after: index)
        }

        if index < bytes.endIndex, bytes[index] == FastJSONPattern.minus {
            sign = -1.0
            index = bytes.index(after: index)
        }

        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte >= FastJSONPattern.zero, byte <= FastJSONPattern.nine else {
                break
            }
            foundDigit = true
            whole = whole * 10 + Double(byte - FastJSONPattern.zero)
            index = bytes.index(after: index)
        }

        if index < bytes.endIndex, bytes[index] == FastJSONPattern.dot {
            index = bytes.index(after: index)
            while index < bytes.endIndex {
                let byte = bytes[index]
                guard byte >= FastJSONPattern.zero, byte <= FastJSONPattern.nine else {
                    break
                }
                foundDigit = true
                fraction += Double(byte - FastJSONPattern.zero) / divisor
                divisor *= 10
                index = bytes.index(after: index)
            }
        }

        return foundDigit ? sign * (whole + fraction) : nil
    }

    static func bool(after pattern: [UInt8], in bytes: Data.SubSequence) -> Bool? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }

        var index = range.upperBound
        while index < bytes.endIndex, bytes[index] == FastJSONPattern.space {
            index = bytes.index(after: index)
        }

        if matches(FastJSONPattern.trueLiteral, startingAt: index, in: bytes) {
            return true
        }
        if matches(FastJSONPattern.falseLiteral, startingAt: index, in: bytes) {
            return false
        }
        return nil
    }

    static func stringArray(
        after pattern: [UInt8],
        in bytes: Data.SubSequence,
        maximumCount: Int = 6
    ) -> [String] {
        guard let range = range(of: pattern, in: bytes) else {
            return []
        }

        var values: [String] = []
        var index = range.upperBound
        while index < bytes.endIndex, values.count < maximumCount {
            let byte = bytes[index]
            if byte == FastJSONPattern.closeBracket {
                break
            }
            if byte == FastJSONPattern.quote,
               let value = jsonString(startingAt: bytes.index(after: index), in: bytes)
            {
                values.append(value)
                index = skipString(startingAt: bytes.index(after: index), in: bytes) ?? bytes.index(after: index)
                continue
            }
            index = bytes.index(after: index)
        }
        return values
    }

    static func iso8601Date(after pattern: [UInt8], in bytes: Data.SubSequence) -> Date? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }
        return iso8601Date(startingAt: range.upperBound, in: bytes)
    }

    static func object(after pattern: [UInt8], in bytes: Data.SubSequence) -> Data.SubSequence? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }

        var index = range.upperBound
        var depth = 1
        var insideString = false
        var escaping = false
        let start = index

        while index < bytes.endIndex {
            let byte = bytes[index]
            if insideString {
                if escaping {
                    escaping = false
                } else if byte == FastJSONPattern.backslash {
                    escaping = true
                } else if byte == FastJSONPattern.quote {
                    insideString = false
                }
            } else if byte == FastJSONPattern.quote {
                insideString = true
            } else if byte == FastJSONPattern.openBrace {
                depth += 1
            } else if byte == FastJSONPattern.closeBrace {
                depth -= 1
                if depth == 0 {
                    return bytes[start..<index]
                }
            }

            index = bytes.index(after: index)
        }

        return nil
    }

    static func contains(_ pattern: [UInt8], in bytes: Data.SubSequence) -> Bool {
        range(of: pattern, in: bytes) != nil
    }

    static func topLevelObjectKeyCount(after pattern: [UInt8], in bytes: Data.SubSequence) -> Int {
        guard let object = object(after: pattern, in: bytes) else {
            return 0
        }

        var index = object.startIndex
        var depth = 0
        var count = 0
        var insideString = false
        var escaping = false
        var possibleKeyStart: Data.SubSequence.Index?

        while index < object.endIndex {
            let byte = object[index]
            if insideString {
                if escaping {
                    escaping = false
                } else if byte == FastJSONPattern.backslash {
                    escaping = true
                } else if byte == FastJSONPattern.quote {
                    insideString = false
                }
            } else if byte == FastJSONPattern.quote {
                insideString = true
                if depth == 0 {
                    possibleKeyStart = index
                }
            } else if byte == FastJSONPattern.openBrace {
                depth += 1
            } else if byte == FastJSONPattern.closeBrace {
                depth = max(0, depth - 1)
            } else if byte == FastJSONPattern.colon, depth == 0, possibleKeyStart != nil {
                count += 1
                possibleKeyStart = nil
            } else if byte == FastJSONPattern.comma, depth == 0 {
                possibleKeyStart = nil
            }

            index = object.index(after: index)
        }

        return count
    }

    private static func iso8601Date(startingAt start: Data.SubSequence.Index, in bytes: Data.SubSequence) -> Date? {
        var index = start
        guard let year = fixedInt(length: 4, index: &index, in: bytes),
              consume(FastJSONPattern.minus, index: &index, in: bytes),
              let month = fixedInt(length: 2, index: &index, in: bytes),
              consume(FastJSONPattern.minus, index: &index, in: bytes),
              let day = fixedInt(length: 2, index: &index, in: bytes),
              consume(FastJSONPattern.uppercaseT, index: &index, in: bytes),
              let hour = fixedInt(length: 2, index: &index, in: bytes),
              consume(FastJSONPattern.colon, index: &index, in: bytes),
              let minute = fixedInt(length: 2, index: &index, in: bytes),
              consume(FastJSONPattern.colon, index: &index, in: bytes),
              let second = fixedInt(length: 2, index: &index, in: bytes)
        else {
            return nil
        }

        var fraction = 0.0
        if index < bytes.endIndex, bytes[index] == FastJSONPattern.dot {
            index = bytes.index(after: index)
            var divisor = 10.0
            while index < bytes.endIndex {
                let byte = bytes[index]
                guard byte >= FastJSONPattern.zero, byte <= FastJSONPattern.nine else {
                    break
                }
                fraction += Double(byte - FastJSONPattern.zero) / divisor
                divisor *= 10.0
                index = bytes.index(after: index)
            }
        }

        var timezoneOffsetSeconds = 0
        if index < bytes.endIndex {
            let byte = bytes[index]
            if byte == FastJSONPattern.uppercaseZ {
                index = bytes.index(after: index)
            } else if byte == FastJSONPattern.plus || byte == FastJSONPattern.minus {
                let sign = byte == FastJSONPattern.plus ? 1 : -1
                index = bytes.index(after: index)
                guard let offsetHours = fixedInt(length: 2, index: &index, in: bytes),
                      consume(FastJSONPattern.colon, index: &index, in: bytes),
                      let offsetMinutes = fixedInt(length: 2, index: &index, in: bytes)
                else {
                    return nil
                }
                timezoneOffsetSeconds = sign * ((offsetHours * 60 + offsetMinutes) * 60)
            }
        }

        guard year > 0,
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...60).contains(second)
        else {
            return nil
        }

        let days = daysSinceUnixEpoch(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - timezoneOffsetSeconds
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    private static func fixedInt(
        length: Int,
        index: inout Data.SubSequence.Index,
        in bytes: Data.SubSequence
    ) -> Int? {
        var value = 0
        for _ in 0..<length {
            guard index < bytes.endIndex else {
                return nil
            }
            let byte = bytes[index]
            guard byte >= FastJSONPattern.zero, byte <= FastJSONPattern.nine else {
                return nil
            }
            value = value * 10 + Int(byte - FastJSONPattern.zero)
            index = bytes.index(after: index)
        }
        return value
    }

    private static func consume(
        _ byte: UInt8,
        index: inout Data.SubSequence.Index,
        in bytes: Data.SubSequence
    ) -> Bool {
        guard index < bytes.endIndex, bytes[index] == byte else {
            return false
        }
        index = bytes.index(after: index)
        return true
    }

    private static func daysSinceUnixEpoch(year: Int, month: Int, day: Int) -> Int {
        var adjustedYear = year
        let adjustedMonth = month
        adjustedYear -= adjustedMonth <= 2 ? 1 : 0
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let monthPrime = adjustedMonth + (adjustedMonth > 2 ? -3 : 9)
        let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func jsonString(startingAt start: Data.SubSequence.Index, in bytes: Data.SubSequence) -> String? {
        var index = start
        var escapedBytes: [UInt8]?

        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == FastJSONPattern.quote {
                if let escapedBytes {
                    return String(decoding: escapedBytes, as: UTF8.self)
                }
                return String(decoding: bytes[start..<index], as: UTF8.self)
            }

            if byte == FastJSONPattern.backslash {
                if escapedBytes == nil {
                    escapedBytes = Array(bytes[start..<index])
                }
                let nextIndex = bytes.index(after: index)
                guard nextIndex < bytes.endIndex else {
                    return nil
                }
                appendEscapedByte(bytes[nextIndex], to: &escapedBytes!)
                index = bytes.index(after: nextIndex)
                continue
            }

            escapedBytes?.append(byte)
            index = bytes.index(after: index)
        }

        return nil
    }

    private static func skipString(
        startingAt start: Data.SubSequence.Index,
        in bytes: Data.SubSequence
    ) -> Data.SubSequence.Index? {
        var index = start
        var escaping = false
        while index < bytes.endIndex {
            let byte = bytes[index]
            if escaping {
                escaping = false
            } else if byte == FastJSONPattern.backslash {
                escaping = true
            } else if byte == FastJSONPattern.quote {
                return bytes.index(after: index)
            }
            index = bytes.index(after: index)
        }
        return nil
    }

    private static func appendEscapedByte(_ byte: UInt8, to output: inout [UInt8]) {
        switch byte {
        case FastJSONPattern.quote, FastJSONPattern.backslash, FastJSONPattern.slash:
            output.append(byte)
        case FastJSONPattern.lowercaseB:
            output.append(8)
        case FastJSONPattern.lowercaseF:
            output.append(12)
        case FastJSONPattern.lowercaseN:
            output.append(10)
        case FastJSONPattern.lowercaseR:
            output.append(13)
        case FastJSONPattern.lowercaseT:
            output.append(9)
        default:
            output.append(byte)
        }
    }

    private static func range(of pattern: [UInt8], in bytes: Data.SubSequence) -> Range<Data.SubSequence.Index>? {
        guard pattern.isEmpty == false, bytes.isEmpty == false else {
            return nil
        }

        var index = bytes.startIndex
        while index < bytes.endIndex {
            var current = index
            var patternIndex = pattern.startIndex

            while current < bytes.endIndex,
                  patternIndex < pattern.endIndex,
                  bytes[current] == pattern[patternIndex]
            {
                current = bytes.index(after: current)
                patternIndex = pattern.index(after: patternIndex)
            }

            if patternIndex == pattern.endIndex {
                return index..<current
            }

            index = bytes.index(after: index)
        }

        return nil
    }

    private static func matches(
        _ pattern: [UInt8],
        startingAt start: Data.SubSequence.Index,
        in bytes: Data.SubSequence
    ) -> Bool {
        var index = start
        var patternIndex = pattern.startIndex
        while index < bytes.endIndex, patternIndex < pattern.endIndex {
            guard bytes[index] == pattern[patternIndex] else {
                return false
            }
            index = bytes.index(after: index)
            patternIndex = pattern.index(after: patternIndex)
        }
        return patternIndex == pattern.endIndex
    }
}

private enum FastJSONPattern {
    static let lineFeed: UInt8 = 10
    static let space: UInt8 = 32
    static let quote: UInt8 = 34
    static let ampersand: UInt8 = 38
    static let plus: UInt8 = 43
    static let comma: UInt8 = 44
    static let minus: UInt8 = 45
    static let slash: UInt8 = 47
    static let dot: UInt8 = 46
    static let colon: UInt8 = 58
    static let semicolon: UInt8 = 59
    static let uppercaseT: UInt8 = 84
    static let uppercaseZ: UInt8 = 90
    static let zero: UInt8 = 48
    static let nine: UInt8 = 57
    static let backslash: UInt8 = 92
    static let tab: UInt8 = 9
    static let carriageReturn: UInt8 = 13
    static let pipe: UInt8 = 124
    static let openBrace: UInt8 = 123
    static let closeBracket: UInt8 = 93
    static let closeBrace: UInt8 = 125
    static let lowercaseB: UInt8 = 98
    static let lowercaseF: UInt8 = 102
    static let lowercaseN: UInt8 = 110
    static let lowercaseR: UInt8 = 114
    static let lowercaseT: UInt8 = 116

    static let trueLiteral = Array("true".utf8)
    static let falseLiteral = Array("false".utf8)

    static let type = Array("\"type\":\"".utf8)
    static let payloadType = Array("\"payload\":{\"type\":\"".utf8)
    static let timestamp = Array("\"timestamp\":\"".utf8)
    static let payloadID = Array("\"payload\":{\"id\":\"".utf8)
    static let id = Array("\"id\":\"".utf8)
    static let threadName = Array("\"thread_name\":\"".utf8)
    static let cwd = Array("\"cwd\":\"".utf8)
    static let repositoryURL = Array("\"repository_url\":\"".utf8)
    static let model = Array("\"model\":\"".utf8)
    static let modelProvider = Array("\"model_provider\":\"".utf8)
    static let reasoningEffort = Array("\"reasoning_effort\":\"".utf8)
    static let effort = Array("\"effort\":\"".utf8)
    static let serviceTier = Array("\"service_tier\":\"".utf8)
    static let personality = Array("\"personality\":\"".utf8)
    static let collaborationMode = Array("\"collaboration_mode\":\"".utf8)
    static let collaborationModeObject = Array("\"collaboration_mode\":{\"mode\":\"".utf8)
    static let summary = Array("\"summary\":\"".utf8)
    static let realtimeActive = Array("\"realtime_active\":".utf8)
    static let cliVersion = Array("\"cli_version\":\"".utf8)
    static let source = Array("\"source\":\"".utf8)
    static let agentNickname = Array("\"agent_nickname\":\"".utf8)
    static let agentRole = Array("\"agent_role\":\"".utf8)
    static let agentPath = Array("\"agent_path\":\"".utf8)
    static let parentThreadID = Array("\"parent_thread_id\":\"".utf8)
    static let threadSource = Array("\"thread_source\":\"".utf8)
    static let durationMilliseconds = Array("\"duration_ms\":".utf8)
    static let timeToFirstTokenMilliseconds = Array("\"time_to_first_token_ms\":".utf8)
    static let exitCode = Array("\"exit_code\":".utf8)
    static let command = Array("\"command\":[".utf8)
    // Matches current JavaScript tool input plus escaped and direct JSON argument forms.
    static let commandPrefixes: [[UInt8]] = [
        Array(#"cmd:\""#.utf8),
        Array(#"cmd\":\""#.utf8),
        Array(#"cmd":""#.utf8),
    ]
    static let callID = Array("\"call_id\":\"".utf8)
    static let name = Array("\"name\":\"".utf8)
    static let output = Array("\"output\":\"".utf8)
    static let outputArray = Array("\"output\":[".utf8)
    static let text = Array("\"text\":\"".utf8)
    static let success = Array("\"success\":".utf8)
    static let changes = Array("\"changes\":{".utf8)
    static let lastTokenUsage = Array("\"last_token_usage\":{".utf8)
    static let totalTokenUsage = Array("\"total_token_usage\":{".utf8)
    static let modelContextWindow = Array("\"model_context_window\":".utf8)
    static let rateLimits = Array("\"rate_limits\":{".utf8)
    static let individualLimit = Array("\"individual_limit\":{".utf8)
    static let primaryRateLimit = Array("\"primary\":{".utf8)
    static let secondaryRateLimit = Array("\"secondary\":{".utf8)
    static let usedPercent = Array("\"used_percent\":".utf8)
    static let windowMinutes = Array("\"window_minutes\":".utf8)
    static let resetsAt = Array("\"resets_at\":".utf8)
    static let planType = Array("\"plan_type\":\"".utf8)
    static let limitID = Array("\"limit_id\":\"".utf8)
    static let limitName = Array("\"limit_name\":\"".utf8)
    static let rateLimitReachedType = Array("\"rate_limit_reached_type\":\"".utf8)
    static let exitCodeText = Array("Exit code: ".utf8)
    static let processExitCodeText = Array("Process exited with code ".utf8)
    static let inputTokens = Array("\"input_tokens\":".utf8)
    static let cachedInputTokens = Array("\"cached_input_tokens\":".utf8)
    static let outputTokens = Array("\"output_tokens\":".utf8)
    static let reasoningOutputTokens = Array("\"reasoning_output_tokens\":".utf8)
    static let totalTokens = Array("\"total_tokens\":".utf8)
}
