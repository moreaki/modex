import Foundation
import os

struct CodexSidebarState: Sendable {
    let projectlessThreadIDs: Set<String>

    func scope(for sessionID: String) -> CodexThreadScope {
        projectlessThreadIDs.contains(sessionID) ? .task : .project
    }
}

struct CodexSidebarStateReadResult: Sendable {
    let state: CodexSidebarState
    let bytesRead: Int
    let cacheHit: Bool
}

enum CodexSidebarStateReader {
    private static let cache = Cache()
    private static let fileName = ".codex-global-state.json"
    private static let key = Array("\"projectless-thread-ids\"".utf8)
    private static let chunkSize = 64 * 1024

    static func read(codexHome: URL) -> CodexSidebarStateReadResult? {
        let fileURL = codexHome.appendingPathComponent(fileName, isDirectory: false)
        guard let values = try? fileURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ),
        let fileSize = values.fileSize
        else {
            return nil
        }

        let fingerprint = Fingerprint(
            path: fileURL.standardizedFileURL.path,
            size: fileSize,
            modificationDate: values.contentModificationDate ?? .distantPast
        )
        if let state = cache.state(for: fingerprint) {
            return CodexSidebarStateReadResult(state: state, bytesRead: 0, cacheHit: true)
        }

        guard let parsed = parse(fileURL: fileURL) else {
            return nil
        }
        cache.store(parsed.state, for: fingerprint)
        return CodexSidebarStateReadResult(
            state: parsed.state,
            bytesRead: parsed.bytesRead,
            cacheHit: false
        )
    }

    private static func parse(fileURL: URL) -> (state: CodexSidebarState, bytesRead: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        var phase = ParsePhase.findingKey
        var keyIndex = 0
        var valueBytes: [UInt8] = []
        valueBytes.reserveCapacity(36)
        var isEscaping = false
        var projectlessThreadIDs: Set<String> = []
        var bytesRead = 0

        while let chunk = try? handle.read(upToCount: chunkSize), chunk.isEmpty == false {
            bytesRead += chunk.count
            for byte in chunk {
                switch phase {
                case .findingKey:
                    if byte == key[keyIndex] {
                        keyIndex += 1
                        if keyIndex == key.count {
                            phase = .findingArray
                        }
                    } else {
                        keyIndex = byte == key[0] ? 1 : 0
                    }
                case .findingArray:
                    if byte == UInt8(ascii: "[") {
                        phase = .inArray
                    }
                case .inArray:
                    if byte == UInt8(ascii: "]") {
                        return (
                            CodexSidebarState(projectlessThreadIDs: projectlessThreadIDs),
                            bytesRead
                        )
                    }
                    if byte == UInt8(ascii: "\"") {
                        valueBytes.removeAll(keepingCapacity: true)
                        isEscaping = false
                        phase = .inString
                    }
                case .inString:
                    if isEscaping {
                        valueBytes.append(byte)
                        isEscaping = false
                    } else if byte == UInt8(ascii: "\\") {
                        isEscaping = true
                    } else if byte == UInt8(ascii: "\"") {
                        if let value = String(bytes: valueBytes, encoding: .utf8), value.isEmpty == false {
                            projectlessThreadIDs.insert(value)
                        }
                        phase = .inArray
                    } else if valueBytes.count < 512 {
                        valueBytes.append(byte)
                    }
                }
            }
        }
        return nil
    }
}

private extension CodexSidebarStateReader {
    enum ParsePhase {
        case findingKey
        case findingArray
        case inArray
        case inString
    }

    struct Fingerprint: Equatable, Sendable {
        let path: String
        let size: Int
        let modificationDate: Date
    }

    final class Cache: @unchecked Sendable {
        private struct Storage: Sendable {
            var fingerprint: Fingerprint?
            var state: CodexSidebarState?
        }

        private let storage = OSAllocatedUnfairLock(initialState: Storage())

        func state(for fingerprint: Fingerprint) -> CodexSidebarState? {
            storage.withLock { storage in
                storage.fingerprint == fingerprint ? storage.state : nil
            }
        }

        func store(_ state: CodexSidebarState, for fingerprint: Fingerprint) {
            storage.withLock { storage in
                storage.fingerprint = fingerprint
                storage.state = state
            }
        }
    }
}
