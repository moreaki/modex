import Foundation
import ModexCore

enum ModexAccountPresentation {
    static func tokenMagnitude(_ value: Int?, locale: Locale = ModexStrings.localizationLocale) -> String {
        guard let value, value >= 0 else { return ModexStrings.text("overview.contextUnavailable") }
        let scale: (Double, String)? = value >= 1_000_000_000 ? (1_000_000_000, "account.billionTokens")
            : value >= 1_000_000 ? (1_000_000, "account.millionTokens") : nil
        guard let (divisor, key) = scale else { return value.formatted(.number.locale(locale)) }
        let number = (Double(value) / divisor).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return ModexStrings.format(key, number)
    }

    static func turnDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return ModexStrings.text("overview.contextUnavailable") }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = ModexStrings.localizationLocale
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: Double(seconds)) ?? ModexStrings.text("overview.contextUnavailable")
    }

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
