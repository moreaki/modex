import Foundation
import Testing
@testable import ModexCore
@testable import modex

@Test func displayedAccountDaysAreReportedEntriesNotACalendarWeek() throws {
    let json = #"{"summary":{"lifetimeTokens":25253809535},"dailyUsageBuckets":[{"startDate":"2026-09-25","tokens":129767909},{"startDate":"2026-09-24","tokens":22059557},{"startDate":"2026-09-23","tokens":2084105},{"startDate":"2026-09-21","tokens":2658340},{"startDate":"2026-09-20","tokens":5691733},{"startDate":"2026-09-19","tokens":7109232},{"startDate":"2026-09-18","tokens":14273310},{"startDate":"2026-09-17","tokens":999},{"startDate":"2026-09-26","tokens":-1}]}"#
    let usage = try JSONDecoder().decode(CodexAccountUsage.self, from: Data(json.utf8))
    #expect(usage.displayedDays.count == 7)
    #expect(usage.displayedDays.first?.startDate == "2026-09-18")
    #expect(usage.displayedDays.last?.startDate == "2026-09-25")
    #expect(!usage.displayedDays.contains { $0.startDate == "2026-09-22" })
    #expect(usage.displayedDaysTotal == 183_644_186)
    #expect(try #require(usage.displayedDaysTotal) < #require(usage.summary?.lifetimeTokens))
}

@Test func accountSubtotalPreservesMissingZeroAndOverflow() throws {
    func usage(_ buckets: String) throws -> CodexAccountUsage {
        try JSONDecoder().decode(CodexAccountUsage.self, from: Data("{\"dailyUsageBuckets\":\(buckets)}".utf8))
    }
    #expect(try usage("null").displayedDaysTotal == nil)
    #expect(try usage("[]").displayedDaysTotal == nil)
    #expect(try usage(#"[{"startDate":"2026-09-25","tokens":0}]"#).displayedDaysTotal == 0)
    #expect(try usage("[{\"startDate\":\"2026-09-24\",\"tokens\":\(Int.max)},{\"startDate\":\"2026-09-25\",\"tokens\":1}]").displayedDaysTotal == nil)
}

@Test func accountMagnitudesAndDurationsAreReadable() {
    let en = Locale(identifier: "en_US")
    #expect(ModexAccountPresentation.tokenMagnitude(25_253_809_535, locale: en) == ModexStrings.format("account.billionTokens", "25.25"))
    #expect(ModexAccountPresentation.tokenMagnitude(183_644_186, locale: en) == ModexStrings.format("account.millionTokens", "183.64"))
    #expect(ModexAccountPresentation.tokenMagnitude(0, locale: en) == "0")
    #expect(ModexAccountPresentation.tokenMagnitude(nil) == ModexStrings.text("overview.contextUnavailable"))
    #expect(ModexAccountPresentation.tokenMagnitude(-1) == ModexStrings.text("overview.contextUnavailable"))
    let duration = ModexAccountPresentation.turnDuration(17_385)
    #expect(duration.contains("4") && duration.contains("49") && duration.contains("45"))
    #expect(!duration.contains("17,385"))
    #expect(ModexAccountPresentation.turnDuration(nil) == ModexStrings.text("overview.contextUnavailable"))
    #expect(ModexAccountPresentation.turnDuration(-1) == ModexStrings.text("overview.contextUnavailable"))
}
