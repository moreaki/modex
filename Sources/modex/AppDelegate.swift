import AppKit
import ModexCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scanner = CodexSessionScanner()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    private func configureMenu(summary: ModexSummary? = nil) {
        let menu = NSMenu()

        if let summary {
            menu.addItem(NSMenuItem(title: "Sessions: \(summary.sessionsScanned)", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Total tokens: \(summary.totalTokens.formatted())", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Median turn: \(summary.medianTurnTokens.formatted())", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Average turn: \(summary.averageTurnTokens.formatted())", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Compactions: \(summary.compactionEvents)", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "No Codex token data found", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Codex Folder", action: #selector(openCodexFolder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Modex", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func refresh() {
        do {
            let summary = try scanner.summary()
            if let button = statusItem.button {
                button.image = ModexStatusIcon.make(contextUsagePercent: summary.contextUsagePercent)
                button.imagePosition = .imageLeading
                button.title = title(for: summary)
                button.toolTip = tooltip(for: summary)
            }
            configureMenu(summary: summary)
        } catch {
            if let button = statusItem.button {
                button.image = ModexStatusIcon.make(contextUsagePercent: nil)
                button.imagePosition = .imageLeading
                button.title = "!"
                button.toolTip = "Modex could not read Codex session data."
            }
            configureMenu()
        }
    }

    @objc private func openCodexFolder() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func title(for summary: ModexSummary) -> String {
        if let percent = summary.contextUsagePercent {
            return " \(Int(percent.rounded()))%"
        }
        if summary.totalTokens > 0 {
            return " \(summary.totalTokens.formatted(.number.notation(.compactName)))"
        }
        return ""
    }

    private func tooltip(for summary: ModexSummary) -> String {
        let context = summary.contextUsagePercent.map { "\(Int($0.rounded()))% context" } ?? "unknown context"
        return "Modex: \(context), \(summary.medianTurnTokens.formatted()) median tokens/turn, \(summary.compactionEvents) compactions"
    }
}
