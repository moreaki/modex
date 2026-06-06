import Foundation
import os

public struct CodexSessionScannerConfiguration: Equatable, Sendable {
    public static let defaultMaximumConcurrentParses = max(1, min(2, ProcessInfo.processInfo.activeProcessorCount))
    public static let maximumAllowedConcurrentParses = max(1, min(16, ProcessInfo.processInfo.activeProcessorCount))
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

    public func scan(limit: Int = 5) throws -> [SessionSnapshot] {
        try scanResult(limit: limit).sessions
    }

    public func scanResult(limit: Int = 5, cache: CodexSessionScanCache? = nil) throws -> CodexScanResult {
        let startedAt = Date()
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else {
            return CodexScanResult(
                sessions: [],
                metrics: ScanMetrics(
                    parserMode: FastCodexJSONLParser.parserMode,
                    filesSelected: 0,
                    filesParsed: 0,
                    bytesRead: 0,
                    durationSeconds: Date().timeIntervalSince(startedAt),
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

        let files = Array(
            try sessionFileCandidates()
                .sorted { lhs, rhs in
                    lhs.modificationDate > rhs.modificationDate
                }
                .prefix(safeLimit)
        )

        let results = LockedScanResults()
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: configuration.maximumConcurrentParses)
        let queue = DispatchQueue.global(qos: .userInitiated)
        let configuration = configuration
        var cacheHits = 0
        var cacheMisses = 0
        var cacheBytesSaved = 0

        for (index, file) in files.enumerated() {
            if let cache {
                let key = SessionScanCacheKey(candidate: file)
                if let cachedResult = cache.result(for: key) {
                    cacheHits += 1
                    cacheBytesSaved += file.fileSize
                    results.append(index: index, result: cachedResult.asCacheHit())
                    continue
                }
                cacheMisses += 1
            }

            semaphore.wait()
            group.enter()
            queue.async {
                defer {
                    semaphore.signal()
                    group.leave()
                }

                if let snapshot = try? Self.parseSnapshot(
                    fileURL: file.url,
                    fallbackModificationDate: file.modificationDate,
                    configuration: configuration
                ) {
                    results.append(index: index, result: snapshot)
                }
            }
        }
        group.wait()

        let orderedIndexedResults = results.orderedIndexedResults()
        let orderedResults = orderedIndexedResults.map(\.result)
        let missingThreadNameSessionIDs = Set(
            orderedResults
                .map(\.snapshot)
                .filter { snapshot in
                    snapshot.threadName?.isEmpty ?? true
                }
                .compactMap(\.sessionID)
        )
        let threadIndex = threadNamesBySessionID(
            matching: missingThreadNameSessionIDs
        )
        let enrichedResults = orderedIndexedResults.map { indexedResult in
            var snapshot = indexedResult.result.snapshot
            var metrics = indexedResult.result.metrics
            if let sessionID = snapshot.sessionID,
               let threadName = threadIndex.threadNames[sessionID],
               threadName.isEmpty == false
            {
                snapshot.threadName = threadName
                metrics = metrics.withThreadName(threadName)
            }
            return (index: indexedResult.index, snapshot: snapshot, metrics: metrics)
        }
        if let cache {
            for result in enrichedResults where result.metrics.cacheHit == false && files.indices.contains(result.index) {
                cache.store(
                    ParseResult(snapshot: result.snapshot, metrics: result.metrics),
                    for: SessionScanCacheKey(candidate: files[result.index])
                )
            }
        }
        let fileMetrics = enrichedResults.map(\.metrics)
        let sessions = enrichedResults.map(\.snapshot)
        let bytesRead = fileMetrics.reduce(threadIndex.bytesRead) { $0 + $1.bytesRead }
        let parseWorkItemCount = cache == nil ? files.count : cacheMisses
        let activeConcurrentParses = parseWorkItemCount == 0
            ? 0
            : min(configuration.maximumConcurrentParses, parseWorkItemCount)

        return CodexScanResult(
            sessions: sessions,
            metrics: ScanMetrics(
                parserMode: FastCodexJSONLParser.parserMode,
                filesSelected: files.count,
                filesParsed: sessions.count,
                bytesRead: bytesRead,
                durationSeconds: Date().timeIntervalSince(startedAt),
                maximumConcurrentParses: activeConcurrentParses,
                configuredMaximumConcurrentParses: configuration.maximumConcurrentParses,
                chunkSizeBytes: configuration.chunkSizeBytes,
                maximumLineBufferBytes: configuration.maximumLineBufferBytes,
                sessionIndexMaximumLineBufferBytes: configuration.sessionIndexMaximumLineBufferBytes,
                cacheEnabled: cache != nil,
                cacheHits: cacheHits,
                cacheMisses: cacheMisses,
                cacheEntries: cache?.entryCount ?? 0,
                cacheBytesSaved: cacheBytesSaved,
                fileMetrics: fileMetrics
            )
        )
    }

    public func summary(limit: Int = 5, cache: CodexSessionScanCache? = nil) throws -> ModexSummary {
        let result = try scanResult(limit: limit, cache: cache)
        return ModexSummary(sessions: result.sessions, scanMetrics: result.metrics)
    }

    public func sessionFiles() throws -> [URL] {
        try sessionFileCandidates().map(\.url)
    }

    public func parse(fileURL: URL) throws -> SessionSnapshot {
        try Self.parseSnapshot(
            fileURL: fileURL,
            fallbackModificationDate: Self.modificationDate(fileURL),
            configuration: configuration
        ).snapshot
    }

    private func sessionFileCandidates() throws -> [SessionFileCandidate] {
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
                        fileSize: max(0, fileSize)
                    )
                )
            }
        }
        return candidates
    }

    private static func parseSnapshot(
        fileURL: URL,
        fallbackModificationDate: Date,
        configuration: CodexSessionScannerConfiguration
    ) throws -> ParseResult {
        try FastCodexJSONLParser(configuration: configuration)
            .parse(fileURL: fileURL, fallbackModificationDate: fallbackModificationDate)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func threadNamesBySessionID(matching sessionIDs: Set<String>) -> SessionIndexResult {
        guard sessionIDs.isEmpty == false else {
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
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    public init() {}

    public var entryCount: Int {
        storage.withLock { $0.entries.count }
    }

    public func removeAll() {
        storage.withLock { $0.entries.removeAll(keepingCapacity: true) }
    }

    fileprivate func result(for key: SessionScanCacheKey) -> ParseResult? {
        storage.withLock { $0.entries[key] }
    }

    fileprivate func store(_ result: ParseResult, for key: SessionScanCacheKey) {
        storage.withLock { storage in
            storage.entries = storage.entries.filter { entry in
                entry.key.path != key.path || entry.key == key
            }
            storage.entries[key] = result
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
}

private final class LockedScanResults: @unchecked Sendable {
    private let values = OSAllocatedUnfairLock(initialState: [(index: Int, result: ParseResult)]())

    func append(index: Int, result: ParseResult) {
        values.withLock { values in
            values.append((index, result))
        }
    }

    func orderedResults() -> [ParseResult] {
        values.withLock { values in
            values.sorted { $0.index < $1.index }.map(\.result)
        }
    }

    func orderedIndexedResults() -> [(index: Int, result: ParseResult)] {
        values.withLock { values in
            values.sorted { $0.index < $1.index }
        }
    }
}

fileprivate struct ParseResult: Sendable {
    let snapshot: SessionSnapshot
    let metrics: FileScanMetrics

    func asCacheHit() -> ParseResult {
        ParseResult(snapshot: snapshot, metrics: metrics.asCacheHit())
    }
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

    func parse(fileURL: URL, matching sessionIDs: Set<String>) throws -> SessionIndexResult {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var threadNames: [String: String] = [:]
        var pendingLine = Data()
        var skippingOversizedLine = false
        var bytesRead = 0

        while let chunk = try handle.read(upToCount: configuration.chunkSizeBytes),
              chunk.isEmpty == false
        {
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

            if threadNames.count == sessionIDs.count {
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
        matching sessionIDs: Set<String>,
        into threadNames: inout [String: String]
    ) {
        guard let sessionID = FastJSONValue.string(after: FastJSONPattern.id, in: line),
              sessionIDs.contains(sessionID),
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

    private let configuration: CodexSessionScannerConfiguration

    init(configuration: CodexSessionScannerConfiguration) {
        self.configuration = configuration
    }

    func parse(fileURL: URL, fallbackModificationDate: Date) throws -> ParseResult {
        let startedAt = Date()
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var snapshot = SessionSnapshot(fileURL: fileURL)
        var pendingLine = Data()
        var skippingOversizedLine = false
        var bytesRead = 0
        var maximumBufferedLineBytes = 0
        var oversizedLines = 0

        while let chunk = try handle.read(upToCount: configuration.chunkSizeBytes),
              chunk.isEmpty == false
        {
            bytesRead += chunk.count
            var lineStart = chunk.startIndex
            var index = chunk.startIndex

            while index < chunk.endIndex {
                if chunk[index] == FastJSONPattern.lineFeed {
                    if skippingOversizedLine {
                        skippingOversizedLine = false
                    } else if pendingLine.isEmpty {
                        if lineStart < index {
                            parseLine(chunk[lineStart..<index], into: &snapshot)
                        }
                    } else {
                        let segment = chunk[lineStart..<index]
                        if pendingLine.count + segment.count > configuration.maximumLineBufferBytes {
                            appendCapped(segment, to: &pendingLine)
                            maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                            parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], into: &snapshot)
                            pendingLine.removeAll(keepingCapacity: false)
                            oversizedLines += 1
                        } else {
                            pendingLine.append(segment)
                            maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                            parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], into: &snapshot)
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
                    parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], into: &snapshot)
                    pendingLine.removeAll(keepingCapacity: false)
                    oversizedLines += 1
                    skippingOversizedLine = true
                } else {
                    pendingLine.append(segment)
                    maximumBufferedLineBytes = max(maximumBufferedLineBytes, pendingLine.count)
                }
            }
        }

        if skippingOversizedLine == false, pendingLine.isEmpty == false {
            parseLine(pendingLine[pendingLine.startIndex..<pendingLine.endIndex], into: &snapshot)
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
                durationSeconds: Date().timeIntervalSince(startedAt),
                tokenEvents: snapshot.tokenEvents.count,
                compactionEvents: snapshot.compactionEvents,
                maximumBufferedLineBytes: maximumBufferedLineBytes,
                oversizedLines: oversizedLines
            )
        )
    }

    private func appendCapped(_ segment: Data.SubSequence, to pendingLine: inout Data) {
        let remainingBytes = max(0, configuration.maximumLineBufferBytes - pendingLine.count)
        guard remainingBytes > 0 else {
            return
        }

        pendingLine.append(segment.prefix(remainingBytes))
    }

    private func parseLine(_ line: Data.SubSequence, into snapshot: inout SessionSnapshot) {
        guard let topLevelType = FastJSONValue.string(after: FastJSONPattern.type, in: line) else {
            return
        }

        let isSessionMeta = topLevelType == "session_meta"
        let payloadType = isSessionMeta ? nil : FastJSONValue.string(after: FastJSONPattern.payloadType, in: line)
        let isTokenCount = topLevelType == "token_count" || payloadType == "token_count"
        let isTurnContext = topLevelType == "turn_context" || payloadType == "turn_context"
        let isTaskComplete = payloadType == "task_complete"
        let isCommandEnd = payloadType == "exec_command_end"
        let isToolCall = topLevelType == "response_item" && Self.isToolCallPayloadType(payloadType)
        let hasFileChanges = FastJSONValue.contains(FastJSONPattern.changes, in: line)
        let isCompaction = topLevelType.contains("compact")
            || payloadType?.contains("compact") == true

        guard isSessionMeta
            || isTokenCount
            || isTurnContext
            || isTaskComplete
            || isCommandEnd
            || isToolCall
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

        if isSessionMeta {
            snapshot.sessionID = FastJSONValue.string(after: FastJSONPattern.payloadID, in: line)
                ?? FastJSONValue.string(after: FastJSONPattern.id, in: line)
                ?? snapshot.sessionID
            snapshot.workingDirectory = FastJSONValue.string(after: FastJSONPattern.cwd, in: line) ?? snapshot.workingDirectory
        }

        if isTokenCount {
            appendTokenEvent(line: line, timestamp: timestamp, snapshot: &snapshot)
        }

        if isTurnContext {
            applyTurnContext(line: line, snapshot: &snapshot)
        }

        if isTaskComplete {
            applyTaskComplete(line: line, snapshot: &snapshot)
        }

        if isCommandEnd {
            applyCommandEnd(line: line, snapshot: &snapshot)
        }

        if isToolCall {
            snapshot.toolCallEvents += 1
        }

        if hasFileChanges {
            snapshot.changedFileEvents += FastJSONValue.topLevelObjectKeyCount(
                after: FastJSONPattern.changes,
                in: line
            )
        }

        if isCompaction {
            snapshot.compactionEvents += 1
        }
    }

    private static func isToolCallPayloadType(_ payloadType: String?) -> Bool {
        guard let payloadType else {
            return false
        }
        return payloadType.contains("call") && payloadType.contains("output") == false
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
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else {
            return nil
        }
        return value
    }

    private func appendTokenEvent(line: Data.SubSequence, timestamp: Date?, snapshot: inout SessionSnapshot) {
        guard let last = FastJSONValue.object(after: FastJSONPattern.lastTokenUsage, in: line),
              let total = FastJSONValue.object(after: FastJSONPattern.totalTokenUsage, in: line)
        else {
            return
        }

        snapshot.tokenEvents.append(
            TokenEvent(
                timestamp: timestamp,
                lastUsage: tokenUsage(last),
                totalUsage: tokenUsage(total),
                modelContextWindow: FastJSONValue.int(after: FastJSONPattern.modelContextWindow, in: line),
                rateLimits: rateLimits(line)
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

    private func applyCommandEnd(line: Data.SubSequence, snapshot: inout SessionSnapshot) {
        snapshot.commandEvents += 1
        if let exitCode = FastJSONValue.int(after: FastJSONPattern.exitCode, in: line),
           exitCode != 0
        {
            snapshot.failedCommandEvents += 1
            if snapshot.failedCommandSummaries.count < 24 {
                snapshot.failedCommandSummaries.append(
                    CommandFailureSummary(
                        timestamp: dateValue(after: FastJSONPattern.timestamp, in: line),
                        commandName: sanitizedCommandName(
                            FastJSONValue.stringArray(after: FastJSONPattern.command, in: line).first
                        ),
                        exitCode: exitCode
                    )
                )
            }
        }
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

        let primary = FastJSONValue
            .object(after: FastJSONPattern.primaryRateLimit, in: object)
            .flatMap(rateLimitWindow)
        let secondary = FastJSONValue
            .object(after: FastJSONPattern.secondaryRateLimit, in: object)
            .flatMap(rateLimitWindow)
        let planType = FastJSONValue.string(after: FastJSONPattern.planType, in: object)

        guard primary != nil || secondary != nil || planType != nil else {
            return nil
        }

        return CodexRateLimits(primary: primary, secondary: secondary, planType: planType)
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

private enum FastJSONValue {
    static func string(after pattern: [UInt8], in bytes: Data.SubSequence) -> String? {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }
        return jsonString(startingAt: range.upperBound, in: bytes)
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
    static let plus: UInt8 = 43
    static let comma: UInt8 = 44
    static let minus: UInt8 = 45
    static let slash: UInt8 = 47
    static let dot: UInt8 = 46
    static let colon: UInt8 = 58
    static let uppercaseT: UInt8 = 84
    static let uppercaseZ: UInt8 = 90
    static let zero: UInt8 = 48
    static let nine: UInt8 = 57
    static let backslash: UInt8 = 92
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
    static let model = Array("\"model\":\"".utf8)
    static let reasoningEffort = Array("\"reasoning_effort\":\"".utf8)
    static let effort = Array("\"effort\":\"".utf8)
    static let summary = Array("\"summary\":\"".utf8)
    static let realtimeActive = Array("\"realtime_active\":".utf8)
    static let durationMilliseconds = Array("\"duration_ms\":".utf8)
    static let timeToFirstTokenMilliseconds = Array("\"time_to_first_token_ms\":".utf8)
    static let exitCode = Array("\"exit_code\":".utf8)
    static let command = Array("\"command\":[".utf8)
    static let changes = Array("\"changes\":{".utf8)
    static let lastTokenUsage = Array("\"last_token_usage\":{".utf8)
    static let totalTokenUsage = Array("\"total_token_usage\":{".utf8)
    static let modelContextWindow = Array("\"model_context_window\":".utf8)
    static let rateLimits = Array("\"rate_limits\":{".utf8)
    static let primaryRateLimit = Array("\"primary\":{".utf8)
    static let secondaryRateLimit = Array("\"secondary\":{".utf8)
    static let usedPercent = Array("\"used_percent\":".utf8)
    static let windowMinutes = Array("\"window_minutes\":".utf8)
    static let resetsAt = Array("\"resets_at\":".utf8)
    static let planType = Array("\"plan_type\":\"".utf8)
    static let inputTokens = Array("\"input_tokens\":".utf8)
    static let cachedInputTokens = Array("\"cached_input_tokens\":".utf8)
    static let outputTokens = Array("\"output_tokens\":".utf8)
    static let reasoningOutputTokens = Array("\"reasoning_output_tokens\":".utf8)
    static let totalTokens = Array("\"total_tokens\":".utf8)
}
