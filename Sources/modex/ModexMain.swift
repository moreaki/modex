import AppKit
import Foundation
import ModexCore

@main
enum ModexMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--once") {
            printSummary(limit: Self.limitArgument())
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func printSummary(limit: Int) {
        do {
            let summary = try CodexSessionScanner().summary(limit: limit)
            print("sessions: \(summary.sessionsScanned)")
            print("token events: \(summary.tokenEvents)")
            print("total tokens: \(summary.totalTokens)")
            print("median turn tokens: \(summary.medianTurnTokens)")
            print("average turn tokens: \(summary.averageTurnTokens)")
            print("compaction events: \(summary.compactionEvents)")
            if let percent = summary.contextUsagePercent {
                print("latest context usage: \(String(format: "%.1f%%", percent))")
            } else {
                print("latest context usage: unknown")
            }
        } catch {
            FileHandle.standardError.write(Data("modex: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func limitArgument() -> Int {
        guard let index = CommandLine.arguments.firstIndex(of: "--limit"),
              CommandLine.arguments.indices.contains(index + 1),
              let limit = Int(CommandLine.arguments[index + 1]),
              limit > 0
        else {
            return 5
        }
        return limit
    }
}
