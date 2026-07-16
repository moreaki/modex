import Foundation
import IkigaJSON
import ModexCore
import NIOCore

private struct Options {
    var limit = 10
    var iterations = 5
    var includeArchived = false
    var maximumConcurrentParses = CodexSessionScannerConfiguration.defaultMaximumConcurrentParses
    var onlyVariant: String?
    var cacheEnabled = false
    var chunkSizeBytes = CodexSessionScannerConfiguration.defaultChunkSizeBytes
    var codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")

    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--limit":
                if let value = Self.intValue(after: &index, in: arguments) {
                    limit = max(1, value)
                }
            case "--iterations":
                if let value = Self.intValue(after: &index, in: arguments) {
                    iterations = max(1, value)
                }
            case "--chunk-kb":
                if let value = Self.intValue(after: &index, in: arguments) {
                    chunkSizeBytes = max(16, value) * 1024
                }
            case "--concurrency":
                if let value = Self.intValue(after: &index, in: arguments) {
                    maximumConcurrentParses = max(1, value)
                }
            case "--only":
                onlyVariant = Self.stringValue(after: &index, in: arguments)
            case "--cache":
                cacheEnabled = true
            case "--codex-home":
                if let value = Self.stringValue(after: &index, in: arguments), value.isEmpty == false {
                    codexHome = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
                }
            case "--include-archived":
                includeArchived = true
            case "--help", "-h":
                Self.printUsageAndExit()
            default:
                break
            }
            index += 1
        }
    }

    private static func intValue(after index: inout Int, in arguments: [String]) -> Int? {
        guard arguments.indices.contains(index + 1) else {
            return nil
        }
        index += 1
        return Int(arguments[index])
    }

    private static func stringValue(after index: inout Int, in arguments: [String]) -> String? {
        guard arguments.indices.contains(index + 1) else {
            return nil
        }
        index += 1
        return arguments[index]
    }

    private static func printUsageAndExit() -> Never {
        print(
            """
            Usage:
              swift run -c release ParserComparison [options]

            Options:
              --limit N             Number of newest JSONL files to scan. Default: 10
              --iterations N        Timed iterations after warmup. Default: 5
              --include-archived    Include ~/.codex/archived_sessions
              --concurrency N       File concurrency for all parser variants. Default: scanner default
              --chunk-kb N          Streaming read chunk size. Default: 256
              --only NAME           One variant: modex, nio-scan, ikiga-prefilter, ikiga-all
              --cache               Reuse Modex's scan cache after the warmup pass
              --codex-home PATH     Codex home folder. Default: ~/.codex
            """
        )
        Foundation.exit(0)
    }
}

private struct SessionFile {
    let url: URL
    let modificationDate: Date
    let fileSize: Int
}

private struct ParseCounters: Equatable {
    var files = 0
    var bytesRead = 0
    var linesSeen = 0
    var linesParsed = 0
    var parseErrors = 0
    var tokenEvents = 0
    var compactionEvents = 0
    var modelEvents = 0
    var sessionMetaEvents = 0
    var totalTokensChecksum = 0
    var contextWindowChecksum = 0
    var maximumLineBytes = 0
}

private struct BenchmarkResult {
    let name: String
    let samples: [Double]
    let counters: ParseCounters

    var best: Double {
        samples.min() ?? 0
    }

    var median: Double {
        percentile(0.50)
    }

    var worst: Double {
        samples.max() ?? 0
    }

    private func percentile(_ fraction: Double) -> Double {
        let ordered = samples.sorted()
        guard ordered.isEmpty == false else {
            return 0
        }
        let index = Int((Double(ordered.count - 1) * fraction).rounded())
        return ordered[min(max(index, 0), ordered.count - 1)]
    }
}

private enum IkigaMode {
    case allLines
    case prefilteredRelevantLines
}

private enum Pattern {
    static let space: UInt8 = 32
    static let quote: UInt8 = 34
    static let minus: UInt8 = 45
    static let zero: UInt8 = 48
    static let nine: UInt8 = 57
    static let backslash: UInt8 = 92

    static let type = Array(#""type":""#.utf8)
    static let payloadType = Array(#""payload":{"type":""#.utf8)
    static let sessionMeta = Array(#""session_meta""#.utf8)
    static let sessionMetaValue = Array("session_meta".utf8)
    static let tokenCount = Array(#""token_count""#.utf8)
    static let tokenCountValue = Array("token_count".utf8)
    static let turnContext = Array(#""turn_context""#.utf8)
    static let turnContextValue = Array("turn_context".utf8)
    static let compactLower = Array("compact".utf8)
    static let payloadID = Array(#""payload":{"id":""#.utf8)
    static let cwd = Array(#""cwd":""#.utf8)
    static let model = Array(#""model":""#.utf8)
    static let reasoningEffort = Array(#""reasoning_effort":""#.utf8)
    static let effort = Array(#""effort":""#.utf8)
    static let inputTokens = Array(#""input_tokens":"#.utf8)
    static let cachedInputTokens = Array(#""cached_input_tokens":"#.utf8)
    static let outputTokens = Array(#""output_tokens":"#.utf8)
    static let reasoningOutputTokens = Array(#""reasoning_output_tokens":"#.utf8)
    static let totalTokens = Array(#""total_tokens":"#.utf8)
    static let modelContextWindow = Array(#""model_context_window":"#.utf8)
}

private let options = Options(arguments: CommandLine.arguments)
private let files = try selectedSessionFiles(options: options)
guard files.isEmpty == false else {
    print("No Codex JSONL files found under \(options.codexHome.path)")
    Foundation.exit(1)
}

let totalBytes = files.reduce(0) { $0 + $1.fileSize }
print("Codex home: \(options.codexHome.path)")
print("Files: \(files.count) newest \(options.includeArchived ? "active+archived" : "active") JSONL files")
print("Bytes: \(formatBytes(totalBytes))")
print("File concurrency: \(options.maximumConcurrentParses)x configured")
print("Modex scan cache: \(options.cacheEnabled ? "enabled" : "disabled")")
print("Iterations: \(options.iterations) timed after one warmup")
print("Build: use -c release for meaningful Swift parser timings")
print("")

private var results: [BenchmarkResult] = []
if shouldRun("modex", options: options) {
    let scanCache = options.cacheEnabled ? CodexSessionScanCache() : nil
    results.append(
        try await benchmarkAsync(name: "modex-streaming-byte-scan", iterations: options.iterations) {
            try await runModexScanner(options: options, cache: scanCache)
        }
    )
}
if shouldRun("ikiga-prefilter", options: options) {
    results.append(
        try benchmark(name: "ikiga-jsonobject-prefilter", iterations: options.iterations) {
            try runIkiga(files: files, options: options, mode: .prefilteredRelevantLines)
        }
    )
}
if shouldRun("nio-scan", options: options) {
    results.append(
        try benchmark(name: "nio-bytebuffer-scan", iterations: options.iterations) {
            try runNIOScanner(files: files, options: options)
        }
    )
}
if shouldRun("ikiga-all", options: options) {
    results.append(
        try benchmark(name: "ikiga-jsonobject-all-lines", iterations: options.iterations) {
            try runIkiga(files: files, options: options, mode: .allLines)
        }
    )
}

printResults(results)
print("")
print("Note: IkigaJSON is a full JSON parser. The Modex path intentionally extracts a small set of known fields with a streaming byte scan.")

private func selectedSessionFiles(options: Options) throws -> [SessionFile] {
    let directoryNames = options.includeArchived
        ? ["sessions", "archived_sessions"]
        : ["sessions"]
    var candidates: [SessionFile] = []

    for directoryName in directoryNames {
        let directory = options.codexHome.appendingPathComponent(directoryName, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            continue
        }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            candidates.append(
                SessionFile(
                    url: url,
                    modificationDate: values?.contentModificationDate ?? .distantPast,
                    fileSize: max(0, values?.fileSize ?? 0)
                )
            )
        }
    }

    return Array(
        candidates
            .sorted { $0.modificationDate > $1.modificationDate }
            .prefix(options.limit)
    )
}

private func shouldRun(_ variant: String, options: Options) -> Bool {
    guard let onlyVariant = options.onlyVariant else {
        return true
    }
    return onlyVariant == variant
}

private func runModexScanner(
    options: Options,
    cache: CodexSessionScanCache?
) async throws -> ParseCounters {
    let configuration = CodexSessionScannerConfiguration(
        maximumConcurrentParses: options.maximumConcurrentParses,
        chunkSizeBytes: options.chunkSizeBytes,
        includeArchivedSessions: options.includeArchived
    )
    let result = try await CodexSessionScanner(
        codexHome: options.codexHome,
        configuration: configuration
    )
        .scanResult(limit: options.limit, cache: cache)

    return ParseCounters(
        files: result.metrics.filesParsed,
        bytesRead: result.metrics.bytesRead,
        linesSeen: 0,
        linesParsed: result.sessions.reduce(0) { $0 + $1.tokenEvents.count },
        parseErrors: 0,
        tokenEvents: result.sessions.reduce(0) { $0 + $1.tokenEvents.count },
        compactionEvents: result.sessions.reduce(0) { $0 + $1.compactionEvents },
        modelEvents: result.sessions.filter { $0.model != nil }.count,
        sessionMetaEvents: result.sessions.filter { $0.sessionID != nil || $0.workingDirectory != nil }.count,
        totalTokensChecksum: result.sessions.reduce(0) { $0 + $1.totalTokens },
        contextWindowChecksum: result.sessions.reduce(0) { $0 + ($1.contextWindow ?? 0) },
        maximumLineBytes: result.metrics.fileMetrics.map(\.maximumBufferedLineBytes).max() ?? 0
    )
}

private func runIkiga(files: [SessionFile], options: Options, mode: IkigaMode) throws -> ParseCounters {
    let lockedCounters = LockedParseCounters()
    let lockedErrors = LockedErrors()
    let group = DispatchGroup()
    let semaphore = DispatchSemaphore(value: options.maximumConcurrentParses)
    let queue = DispatchQueue.global(qos: .userInitiated)

    for file in files {
        semaphore.wait()
        group.enter()
        queue.async {
            defer {
                semaphore.signal()
                group.leave()
            }

            do {
                let counters = try parseIkigaFile(file, options: options, mode: mode)
                lockedCounters.add(counters)
            } catch {
                lockedErrors.append(error)
            }
        }
    }

    group.wait()
    if let error = lockedErrors.first {
        throw error
    }
    return lockedCounters.value
}

private func runNIOScanner(files: [SessionFile], options: Options) throws -> ParseCounters {
    let lockedCounters = LockedParseCounters()
    let lockedErrors = LockedErrors()
    let group = DispatchGroup()
    let semaphore = DispatchSemaphore(value: options.maximumConcurrentParses)
    let queue = DispatchQueue.global(qos: .userInitiated)

    for file in files {
        semaphore.wait()
        group.enter()
        queue.async {
            defer {
                semaphore.signal()
                group.leave()
            }

            do {
                let counters = try parseNIOFile(file, options: options)
                lockedCounters.add(counters)
            } catch {
                lockedErrors.append(error)
            }
        }
    }

    group.wait()
    if let error = lockedErrors.first {
        throw error
    }
    return lockedCounters.value
}

@Sendable private func parseNIOFile(_ file: SessionFile, options: Options) throws -> ParseCounters {
    let handle = try FileHandle(forReadingFrom: file.url)
    defer {
        try? handle.close()
    }

    var counters = ParseCounters()
    counters.files = 1
    var buffer = ByteBufferAllocator().buffer(capacity: options.chunkSizeBytes)

    while let chunk = try handle.read(upToCount: options.chunkSizeBytes),
          chunk.isEmpty == false
    {
        buffer.writeBytes(chunk)
        counters.bytesRead += chunk.count
        parseCompleteNIOLines(in: &buffer, counters: &counters)
    }

    if buffer.readableBytes > 0 {
        counters.linesSeen += 1
        let line = buffer.readableBytesView
        counters.maximumLineBytes = max(counters.maximumLineBytes, line.count)
        NIOByteScanner.extract(from: line, counters: &counters)
        buffer.clear()
    }

    return counters
}

@Sendable private func parseCompleteNIOLines(in buffer: inout ByteBuffer, counters: inout ParseCounters) {
    while let lineFeedIndex = buffer.readableBytesView.firstIndex(of: 10) {
        let view = buffer.readableBytesView
        let start = view.startIndex
        let line = view[start..<lineFeedIndex]
        counters.linesSeen += 1
        counters.maximumLineBytes = max(counters.maximumLineBytes, line.count)
        NIOByteScanner.extract(from: line, counters: &counters)
        buffer.moveReaderIndex(forwardBy: line.count + 1)

        if buffer.readerIndex > 1_048_576 {
            buffer.discardReadBytes()
        }
    }
    buffer.discardReadBytes()
}

@Sendable private func parseIkigaFile(
    _ file: SessionFile,
    options: Options,
    mode: IkigaMode
) throws -> ParseCounters {
    var counters = ParseCounters()
    counters.files = 1
    try forEachLine(in: file.url, chunkSizeBytes: options.chunkSizeBytes) { line in
        counters.linesSeen += 1
        counters.bytesRead += line.count + 1
        counters.maximumLineBytes = max(counters.maximumLineBytes, line.count)

        if mode == .prefilteredRelevantLines, isRelevant(line) == false {
            return
        }

        do {
            let object = try JSONObject(data: Data(line))
            counters.linesParsed += 1
            extract(from: object, counters: &counters)
        } catch {
            counters.parseErrors += 1
        }
    }
    return counters
}

private final class LockedParseCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var counters = ParseCounters()

    var value: ParseCounters {
        lock.withLock { counters }
    }

    func add(_ next: ParseCounters) {
        lock.withLock {
            counters.files += next.files
            counters.bytesRead += next.bytesRead
            counters.linesSeen += next.linesSeen
            counters.linesParsed += next.linesParsed
            counters.parseErrors += next.parseErrors
            counters.tokenEvents += next.tokenEvents
            counters.compactionEvents += next.compactionEvents
            counters.modelEvents += next.modelEvents
            counters.sessionMetaEvents += next.sessionMetaEvents
            counters.totalTokensChecksum &+= next.totalTokensChecksum
            counters.contextWindowChecksum &+= next.contextWindowChecksum
            counters.maximumLineBytes = max(counters.maximumLineBytes, next.maximumLineBytes)
        }
    }
}

private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    var first: Error? {
        lock.withLock { errors.first }
    }

    func append(_ error: Error) {
        lock.withLock {
            errors.append(error)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try body()
    }
}

@Sendable private func forEachLine(
    in fileURL: URL,
    chunkSizeBytes: Int,
    body: (Data.SubSequence) throws -> Void
) throws {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
        try? handle.close()
    }

    var pendingLine = Data()
    while let chunk = try handle.read(upToCount: chunkSizeBytes),
          chunk.isEmpty == false
    {
        var lineStart = chunk.startIndex
        var index = chunk.startIndex

        while index < chunk.endIndex {
            if chunk[index] == 10 {
                if pendingLine.isEmpty {
                    if lineStart < index {
                        try body(chunk[lineStart..<index])
                    }
                } else {
                    pendingLine.append(chunk[lineStart..<index])
                    try body(pendingLine[pendingLine.startIndex..<pendingLine.endIndex])
                    pendingLine.removeAll(keepingCapacity: true)
                }
                lineStart = chunk.index(after: index)
            }
            index = chunk.index(after: index)
        }

        if lineStart < chunk.endIndex {
            pendingLine.append(chunk[lineStart..<chunk.endIndex])
        }
    }

    if pendingLine.isEmpty == false {
        try body(pendingLine[pendingLine.startIndex..<pendingLine.endIndex])
    }
}

@Sendable private func isRelevant(_ line: Data.SubSequence) -> Bool {
    contains(Pattern.sessionMeta, in: line)
        || contains(Pattern.tokenCount, in: line)
        || contains(Pattern.turnContext, in: line)
        || contains(Pattern.compactLower, in: line)
}

@Sendable private func contains(_ pattern: [UInt8], in bytes: Data.SubSequence) -> Bool {
    guard pattern.isEmpty == false, bytes.count >= pattern.count else {
        return false
    }

    var index = bytes.startIndex
    while index < bytes.endIndex {
        var needleIndex = 0
        var haystackIndex = index
        while needleIndex < pattern.count,
              haystackIndex < bytes.endIndex,
              bytes[haystackIndex] == pattern[needleIndex]
        {
            needleIndex += 1
            haystackIndex = bytes.index(after: haystackIndex)
        }
        if needleIndex == pattern.count {
            return true
        }
        index = bytes.index(after: index)
    }
    return false
}

@Sendable private func extract(from object: JSONObject, counters: inout ParseCounters) {
    let topLevelType = object["type"].string
    let payload = object["payload"].object
    let payloadType = payload?["type"].string

    if topLevelType == "session_meta" {
        counters.sessionMetaEvents += 1
        if let id = payload?["id"].string ?? object["id"].string {
            counters.totalTokensChecksum &+= id.count
        }
        if let cwd = payload?["cwd"].string ?? object["cwd"].string {
            counters.totalTokensChecksum &+= cwd.count
        }
    }

    if topLevelType == "turn_context" || payloadType == "turn_context" {
        counters.modelEvents += 1
        if let model = payload?["model"].string ?? object["model"].string {
            counters.totalTokensChecksum &+= model.count
        }
        if let effort = payload?["reasoning_effort"].string
            ?? payload?["effort"].string
            ?? object["reasoning_effort"].string
            ?? object["effort"].string
        {
            counters.totalTokensChecksum &+= effort.count
        }
    }

    if topLevelType == "token_count" || payloadType == "token_count" {
        let info = payload?["info"].object ?? object["info"].object
        let last = info?["last_token_usage"].object
        let total = info?["total_token_usage"].object
        counters.tokenEvents += 1
        counters.totalTokensChecksum &+= tokenTotal(in: last)
        counters.totalTokensChecksum &+= tokenTotal(in: total)
        counters.contextWindowChecksum &+= info?["model_context_window"].int ?? 0

        if let limits = payload?["rate_limits"].object ?? object["rate_limits"].object {
            let primary = limits["primary"].object
            let secondary = limits["secondary"].object
            counters.totalTokensChecksum &+= Int(primary?["used_percent"].double ?? 0)
            counters.totalTokensChecksum &+= Int(secondary?["used_percent"].double ?? 0)
        }
    }

    if topLevelType?.localizedCaseInsensitiveContains("compact") == true
        || payloadType?.localizedCaseInsensitiveContains("compact") == true
    {
        counters.compactionEvents += 1
    }
}

@Sendable private func tokenTotal(in object: JSONObject?) -> Int {
    guard let object else {
        return 0
    }
    return (object["input_tokens"].int ?? 0)
        + (object["cached_input_tokens"].int ?? 0)
        + (object["output_tokens"].int ?? 0)
        + (object["reasoning_output_tokens"].int ?? 0)
        + (object["total_tokens"].int ?? 0)
}

private enum NIOByteScanner {
    static func extract<C: Collection>(from line: C, counters: inout ParseCounters) where C.Element == UInt8 {
        let isSessionMeta = valueEquals(after: Pattern.type, literal: Pattern.sessionMetaValue, in: line)
        let isTokenCount = valueEquals(after: Pattern.type, literal: Pattern.tokenCountValue, in: line)
            || valueEquals(after: Pattern.payloadType, literal: Pattern.tokenCountValue, in: line)
        let isTurnContext = valueEquals(after: Pattern.type, literal: Pattern.turnContextValue, in: line)
            || valueEquals(after: Pattern.payloadType, literal: Pattern.turnContextValue, in: line)
        let isCompaction = contains(Pattern.compactLower, in: line)

        guard isSessionMeta || isTokenCount || isTurnContext || isCompaction else {
            return
        }

        counters.linesParsed += 1

        if isSessionMeta {
            counters.sessionMetaEvents += 1
            counters.totalTokensChecksum &+= stringLength(after: Pattern.payloadID, in: line) ?? 0
            counters.totalTokensChecksum &+= stringLength(after: Pattern.cwd, in: line) ?? 0
        }

        if isTurnContext {
            counters.modelEvents += 1
            counters.totalTokensChecksum &+= stringLength(after: Pattern.model, in: line) ?? 0
            counters.totalTokensChecksum &+= stringLength(after: Pattern.reasoningEffort, in: line)
                ?? stringLength(after: Pattern.effort, in: line)
                ?? 0
        }

        if isTokenCount {
            counters.tokenEvents += 1
            counters.totalTokensChecksum &+= int(after: Pattern.inputTokens, in: line) ?? 0
            counters.totalTokensChecksum &+= int(after: Pattern.cachedInputTokens, in: line) ?? 0
            counters.totalTokensChecksum &+= int(after: Pattern.outputTokens, in: line) ?? 0
            counters.totalTokensChecksum &+= int(after: Pattern.reasoningOutputTokens, in: line) ?? 0
            counters.totalTokensChecksum &+= int(after: Pattern.totalTokens, in: line) ?? 0
            counters.contextWindowChecksum &+= int(after: Pattern.modelContextWindow, in: line) ?? 0
        }

        if isCompaction {
            counters.compactionEvents += 1
        }
    }

    private static func valueEquals<C: Collection>(
        after pattern: [UInt8],
        literal: [UInt8],
        in bytes: C
    ) -> Bool where C.Element == UInt8 {
        guard let range = range(of: pattern, in: bytes) else {
            return false
        }

        var index = range.upperBound
        for byte in literal {
            guard index < bytes.endIndex, bytes[index] == byte else {
                return false
            }
            index = bytes.index(after: index)
        }
        return true
    }

    private static func stringLength<C: Collection>(
        after pattern: [UInt8],
        in bytes: C
    ) -> Int? where C.Element == UInt8 {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }

        var index = range.upperBound
        var count = 0
        var escaping = false
        while index < bytes.endIndex {
            let byte = bytes[index]
            if escaping {
                escaping = false
                count += 1
            } else if byte == Pattern.backslash {
                escaping = true
            } else if byte == Pattern.quote {
                return count
            } else {
                count += 1
            }
            index = bytes.index(after: index)
        }
        return nil
    }

    private static func int<C: Collection>(
        after pattern: [UInt8],
        in bytes: C
    ) -> Int? where C.Element == UInt8 {
        guard let range = range(of: pattern, in: bytes) else {
            return nil
        }

        var index = range.upperBound
        var sign = 1
        var value = 0
        var foundDigit = false

        while index < bytes.endIndex, bytes[index] == Pattern.space {
            index = bytes.index(after: index)
        }

        if index < bytes.endIndex, bytes[index] == Pattern.minus {
            sign = -1
            index = bytes.index(after: index)
        }

        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte >= Pattern.zero, byte <= Pattern.nine else {
                break
            }
            foundDigit = true
            value = value * 10 + Int(byte - Pattern.zero)
            index = bytes.index(after: index)
        }

        return foundDigit ? value * sign : nil
    }

    private static func contains<C: Collection>(
        _ pattern: [UInt8],
        in bytes: C
    ) -> Bool where C.Element == UInt8 {
        range(of: pattern, in: bytes) != nil
    }

    private static func range<C: Collection>(
        of pattern: [UInt8],
        in bytes: C
    ) -> Range<C.Index>? where C.Element == UInt8 {
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
}

private func benchmark(
    name: String,
    iterations: Int,
    body: () throws -> ParseCounters
) throws -> BenchmarkResult {
    _ = try body()
    var samples: [Double] = []
    var finalCounters: ParseCounters?

    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        let counters = try body()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000_000_000)
        finalCounters = counters
    }

    return BenchmarkResult(
        name: name,
        samples: samples,
        counters: finalCounters ?? ParseCounters()
    )
}

private func benchmarkAsync(
    name: String,
    iterations: Int,
    body: () async throws -> ParseCounters
) async throws -> BenchmarkResult {
    _ = try await body()
    var samples: [Double] = []
    var finalCounters: ParseCounters?

    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        let counters = try await body()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000_000_000)
        finalCounters = counters
    }

    return BenchmarkResult(
        name: name,
        samples: samples,
        counters: finalCounters ?? ParseCounters()
    )
}

private func printResults(_ results: [BenchmarkResult]) {
    guard results.isEmpty == false else {
        return
    }
    let baseline = results.first(where: { $0.name == "modex-streaming-byte-scan" }) ?? results[0]

    print(
        [
            pad("variant", 30),
            pad("best", 10),
            pad("median", 10),
            pad("worst", 10),
            pad("vs modex", 10),
            "parsed/token/errors"
        ].joined(separator: "  ")
    )
    print(String(repeating: "-", count: 102))

    for result in results {
        let ratio = result.median / max(baseline.median, 0.000_001)
        let counters = result.counters
        print(
            [
                pad(result.name, 30),
                pad(formatSeconds(result.best), 10),
                pad(formatSeconds(result.median), 10),
                pad(formatSeconds(result.worst), 10),
                pad(String(format: "%.1fx", ratio), 10),
                "\(counters.linesParsed)/\(counters.tokenEvents)/\(counters.parseErrors)"
            ].joined(separator: "  ")
        )
    }

    print("")
    for result in results {
        let counters = result.counters
        print(
            "\(result.name): files=\(counters.files), bytes=\(formatBytes(counters.bytesRead)), " +
                "linesSeen=\(counters.linesSeen), maxLine=\(formatBytes(counters.maximumLineBytes)), " +
                "tokensChecksum=\(counters.totalTokensChecksum), contextChecksum=\(counters.contextWindowChecksum)"
        )
    }
}

private func pad(_ value: String, _ width: Int) -> String {
    value.padding(toLength: width, withPad: " ", startingAt: 0)
}

private func formatSeconds(_ seconds: Double) -> String {
    if seconds < 1 {
        return String(format: "%.0fms", seconds * 1_000)
    }
    return String(format: "%.2fs", seconds)
}

private func formatBytes(_ bytes: Int) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    if unitIndex == 0 {
        return "\(bytes) B"
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}
