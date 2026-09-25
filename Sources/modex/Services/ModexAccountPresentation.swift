import Foundation
import ModexCore

enum ModexAccountPresentation {
    static func plan(_ value: String?) -> String {
        guard let value else { return ModexStrings.text("overview.contextUnavailable") }
        switch value {
        case "pro", "plus", "free", "go", "business", "enterprise", "edu":
            return ModexStrings.text("account.plan.\(value)")
        default: return ModexStrings.text("overview.contextUnavailable")
        }
    }

    static func windowTitle(_ minutes: Int?) -> String {
        switch minutes {
        case 10_080: return ModexStrings.text("account.weeklyLimit")
        case 300: return ModexStrings.text("account.fiveHourLimit")
        case .some(let minutes): return ModexStrings.format("account.otherLimit", minutes)
        case nil: return ModexStrings.text("account.planLimits")
        }
    }

    static func resetTime(_ date: Date, now: Date = Date()) -> String {
        guard date > now else { return ModexStrings.text("account.resetPending") }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = ModexStrings.localizationLocale
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        let duration = formatter.string(from: max(60, date.timeIntervalSince(now))) ?? "—"
        return ModexStrings.format("account.resetsIn", duration)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(ModexStrings.localizationLocale))
    }

    static func resetTitle(_ credit: CodexAccountLimits.ResetCredit) -> String {
        credit.resetType == "codexRateLimits" ? ModexStrings.text("account.fullReset")
            : credit.title ?? ModexStrings.text("account.resetCredit")
    }
}
