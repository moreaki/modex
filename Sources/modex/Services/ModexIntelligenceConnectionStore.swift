import Foundation

final class ModexIntelligenceConnectionStore {
    private struct Receipt: Codable {
        let provider: String
        let executablePath: String
        let model: String
        let reasoningEffort: String
        let speed: String
        let verifiedAt: Date

        func matches(_ settings: ModexIntelligenceSettings) -> Bool {
            provider == settings.provider.rawValue
                && executablePath == settings.codexExecutablePath
                && model == settings.model
                && reasoningEffort == settings.reasoningEffort
                && speed == settings.speed
        }
    }

    private static let receiptKey = "intelligenceConnectionReceipt"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(for settings: ModexIntelligenceSettings) -> ModexIntelligenceConnectionState {
        let settings = settings.normalized()
        guard settings.enabled, settings.provider != .off else {
            return .off
        }
        guard let receipt = receipt(), receipt.matches(settings) else {
            return .unknown
        }
        return .connected(receipt.verifiedAt)
    }

    func recordConnected(at date: Date, for settings: ModexIntelligenceSettings) {
        let settings = settings.normalized()
        guard settings.enabled, settings.provider != .off else {
            return
        }
        let receipt = Receipt(
            provider: settings.provider.rawValue,
            executablePath: settings.codexExecutablePath,
            model: settings.model,
            reasoningEffort: settings.reasoningEffort,
            speed: settings.speed,
            verifiedAt: date
        )
        guard let data = try? encoder.encode(receipt) else {
            return
        }
        defaults.set(data, forKey: Self.receiptKey)
    }

    func invalidate(for settings: ModexIntelligenceSettings) {
        guard let receipt = receipt(), receipt.matches(settings.normalized()) else {
            return
        }
        defaults.removeObject(forKey: Self.receiptKey)
    }

    private func receipt() -> Receipt? {
        guard let data = defaults.data(forKey: Self.receiptKey) else {
            return nil
        }
        return try? decoder.decode(Receipt.self, from: data)
    }
}
