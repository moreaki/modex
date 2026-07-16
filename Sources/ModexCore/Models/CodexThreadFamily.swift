import Foundation

public struct CodexThreadFamily: Equatable, Sendable {
    public let id: String
    public let representative: SessionSnapshot
    public let members: [SessionSnapshot]

    public var nestedAgents: [SessionSnapshot] {
        members.filter { $0.fileURL != representative.fileURL }
    }

    public var subagentCount: Int {
        members.lazy.filter(\.isSubagent).count
    }
}

public enum CodexThreadFamilyBuilder {
    public static func build(from sessions: [SessionSnapshot]) -> [CodexThreadFamily] {
        let sessionsByID = Dictionary(
            sessions.compactMap { session in
                session.sessionID.map { ($0, session) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        var familyOrder: [String] = []
        var familyMembers: [String: [SessionSnapshot]] = [:]

        for session in sessions {
            let familyID = rootThreadID(for: session, sessionsByID: sessionsByID)
            if familyMembers[familyID] == nil {
                familyOrder.append(familyID)
            }
            familyMembers[familyID, default: []].append(session)
        }

        return familyOrder.compactMap { familyID in
            guard let members = familyMembers[familyID],
                  let representative = members.first(where: { $0.sessionID == familyID })
                    ?? members.first(where: { $0.isSubagent == false })
                    ?? members.first
            else {
                return nil
            }
            return CodexThreadFamily(
                id: familyID,
                representative: representative,
                members: members
            )
        }
    }

    private static func rootThreadID(
        for session: SessionSnapshot,
        sessionsByID: [String: SessionSnapshot]
    ) -> String {
        var current = session
        var visited: Set<String> = []

        while let parentID = current.parentThreadID, parentID.isEmpty == false {
            guard visited.insert(parentID).inserted else {
                break
            }
            guard let parent = sessionsByID[parentID] else {
                return parentID
            }
            current = parent
        }

        return current.sessionID ?? current.fileURL.standardizedFileURL.path
    }
}
