import Foundation

public struct LocalCodexReasoningEffortCapability: Decodable, Equatable, Sendable {
    public let reasoningEffort: String
    public let description: String

    public init(reasoningEffort: String, description: String) {
        self.reasoningEffort = reasoningEffort
        self.description = description
    }
}

public struct LocalCodexServiceTierCapability: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String

    public init(id: String, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct LocalCodexModelCapability: Decodable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let displayName: String
    public let description: String
    public let hidden: Bool
    public let supportedReasoningEfforts: [LocalCodexReasoningEffortCapability]
    public let defaultReasoningEffort: String
    public let serviceTiers: [LocalCodexServiceTierCapability]
    public let defaultServiceTier: String?
    public let isDefault: Bool
    public var upgrade: String? = nil
    public var upgradeInfo: UpgradeInfo? = nil
    public var inputModalities: [String] = []
    public var modelSpecialty: String? = nil
    public var multiAgentVersion: String? = nil

    public struct UpgradeInfo: Decodable, Equatable, Sendable {
        public let model: String
        public let retirementAt: Int?
        public let migrationMarkdown: String?
        public let modelLink: String?
        public let upgradeCopy: String?
    }

    public var upgradeTarget: String? { upgradeInfo?.model ?? upgrade }

    /// Render remote copy as bounded plain text, never as executable Markdown/links.
    public var migrationCopy: String? {
        guard let copy = upgradeInfo?.upgradeCopy ?? upgradeInfo?.migrationMarkdown else { return nil }
        let clean = String(copy.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(600))
    }

    public func upgradeDisplayName(in capabilities: LocalCodexCapabilities?) -> String? {
        guard let target = upgradeTarget else { return nil }
        return capabilities?.models.first { $0.model == target }?.displayName ?? target
    }

    public init(
        id: String,
        model: String,
        displayName: String,
        description: String,
        hidden: Bool,
        supportedReasoningEfforts: [LocalCodexReasoningEffortCapability],
        defaultReasoningEffort: String,
        serviceTiers: [LocalCodexServiceTierCapability],
        defaultServiceTier: String?,
        isDefault: Bool
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.hidden = hidden
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
        self.serviceTiers = serviceTiers
        self.defaultServiceTier = defaultServiceTier
        self.isDefault = isDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case displayName
        case description
        case hidden
        case supportedReasoningEfforts
        case defaultReasoningEffort
        case serviceTiers
        case additionalSpeedTiers
        case defaultServiceTier
        case isDefault
        case upgrade, upgradeInfo, inputModalities, modelSpecialty, multiAgentVersion
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decodeIfPresent(String.self, forKey: .id)
        let model = try values.decodeIfPresent(String.self, forKey: .model)
        guard let resolvedModel = model ?? id else {
            throw DecodingError.keyNotFound(
                CodingKeys.model,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Codex model metadata has neither model nor id."
                )
            )
        }

        let efforts = try values.decodeIfPresent(
            [LocalCodexReasoningEffortCapability].self,
            forKey: .supportedReasoningEfforts
        ) ?? []
        let modernTiers = try values.decodeIfPresent(
            [LocalCodexServiceTierCapability].self,
            forKey: .serviceTiers
        )
        let legacyTiers = try values.decodeIfPresent([String].self, forKey: .additionalSpeedTiers) ?? []

        self.id = id ?? resolvedModel
        self.model = resolvedModel
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? resolvedModel
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        supportedReasoningEfforts = efforts
        defaultReasoningEffort = try values.decodeIfPresent(String.self, forKey: .defaultReasoningEffort)
            ?? efforts.first?.reasoningEffort
            ?? "medium"
        serviceTiers = modernTiers ?? legacyTiers.map {
            LocalCodexServiceTierCapability(
                id: $0,
                name: $0.localizedCapitalized,
                description: ""
            )
        }
        defaultServiceTier = try values.decodeIfPresent(String.self, forKey: .defaultServiceTier)
        isDefault = try values.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        upgrade = try? values.decodeIfPresent(String.self, forKey: .upgrade)
        upgradeInfo = try? values.decodeIfPresent(UpgradeInfo.self, forKey: .upgradeInfo)
        inputModalities = (try? values.decodeIfPresent([String].self, forKey: .inputModalities)) ?? []
        modelSpecialty = try? values.decodeIfPresent(String.self, forKey: .modelSpecialty)
        multiAgentVersion = try? values.decodeIfPresent(String.self, forKey: .multiAgentVersion)
    }
}

public struct LocalCodexCapabilities: Equatable, Sendable {
    public let userAgent: String
    public let models: [LocalCodexModelCapability]

    public init(userAgent: String, models: [LocalCodexModelCapability]) {
        self.userAgent = userAgent
        self.models = models
    }

    public var version: String? {
        guard let slash = userAgent.firstIndex(of: "/") else {
            return nil
        }
        let suffix = userAgent[userAgent.index(after: slash)...]
        return suffix.split(whereSeparator: { $0.isWhitespace || $0 == ";" }).first.map(String.init)
    }
}
