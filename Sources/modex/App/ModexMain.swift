import Foundation
import ModexCore
import SwiftUI

@main
enum ModexMain {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--version") {
            print("modex \(ModexApplicationVersion.current) (\(ModexApplicationVersion.buildNumber))")
            return
        }
        if CommandLine.arguments.contains("--version-number") {
            print(ModexApplicationVersion.current)
            return
        }
        if CommandLine.arguments.contains("--build-number") {
            print(ModexApplicationVersion.buildNumber)
            return
        }
        if CommandLine.arguments.contains("--once") {
            await printSummary(configuration: Self.oneShotConfiguration())
            return
        }

        ModexDesktopApplication.main()
    }

    private static func printSummary(configuration: ModexMonitorConfiguration) async {
        do {
            print(try await ModexOneShotCommand(configuration: configuration).report())
        } catch {
            FileHandle.standardError.write(Data("modex: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func oneShotConfiguration() -> ModexMonitorConfiguration {
        ModexMonitorConfiguration(
            scanLimit: optionalIntArgument("--limit"),
            scannerConfiguration: CodexSessionScannerConfiguration(
                maximumConcurrentParses: intArgument(
                    "--concurrency",
                    defaultValue: CodexSessionScannerConfiguration.defaultMaximumConcurrentParses
                ),
                chunkSizeBytes: intArgument(
                    "--chunk-kb",
                    defaultValue: CodexSessionScannerConfiguration.defaultChunkSizeBytes / 1024
                ) * 1024,
                maximumLineBufferBytes: intArgument(
                    "--line-buffer-kb",
                    defaultValue: CodexSessionScannerConfiguration.defaultLineBufferBytes / 1024
                ) * 1024,
                sessionIndexMaximumLineBufferBytes: intArgument(
                    "--index-line-buffer-kb",
                    defaultValue: CodexSessionScannerConfiguration.defaultSessionIndexLineBufferBytes / 1024
                ) * 1024,
                includeArchivedSessions: CommandLine.arguments.contains("--include-archived")
            )
        )
    }

    private static func intArgument(_ name: String, defaultValue: Int) -> Int {
        guard let index = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(index + 1),
              let value = Int(CommandLine.arguments[index + 1]),
              value > 0
        else {
            return defaultValue
        }
        return value
    }

    private static func optionalIntArgument(_ name: String) -> Int? {
        guard let index = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(index + 1),
              let value = Int(CommandLine.arguments[index + 1]),
              value > 0
        else {
            return nil
        }
        return value
    }
}
