import SwiftUI

struct ModexContextAccent: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct ModexPalette: Equatable {
    let background: Color
    let sidebar: Color
    let text: Color
    let secondaryText: Color
    let mutedText: Color
    let accent: Color
    let surface: Color
    let surfaceHighlight: Color
}

enum ModexTheme {
    static func palette(for theme: ModexColorTheme, colorScheme: ColorScheme) -> ModexPalette {
        switch theme {
        case .system:
            if colorScheme == .light {
                return ModexPalette(
                    background: Color(hex: "#F5F5F7"),
                    sidebar: Color(hex: "#FFFFFF"),
                    text: Color(hex: "#1D1D1F"),
                    secondaryText: Color(hex: "#515154"),
                    mutedText: Color(hex: "#86868B"),
                    accent: Color(hex: "#007AFF"),
                    surface: Color(hex: "#D2D2D7"),
                    surfaceHighlight: Color.black.opacity(0.06)
                )
            } else {
                return ModexPalette(
                    background: Color(hex: "#1E1E2E"),
                    sidebar: Color(hex: "#181825"),
                    text: Color(hex: "#CDD6F4"),
                    secondaryText: Color(hex: "#A6ADC8"),
                    mutedText: Color(hex: "#6C7086"),
                    accent: Color(hex: "#89B4FA"),
                    surface: Color(hex: "#313244"),
                    surfaceHighlight: Color.white.opacity(0.10)
                )
            }
        case .black:
            return ModexPalette(
                background: Color(hex: "#060608"),
                sidebar: Color(hex: "#121216"),
                text: Color(hex: "#F2F2F7"),
                secondaryText: Color(hex: "#C7C7D0"),
                mutedText: Color(hex: "#92929D"),
                accent: Color(hex: "#64D2FF"),
                surface: Color(hex: "#34343C"),
                surfaceHighlight: Color(hex: "#24242A")
            )
        }
    }

    static func contextColor(for percent: Double, thresholds: ModexContextThresholds, hasData: Bool = true) -> Color {
        contextAccent(for: percent, thresholds: thresholds, hasData: hasData).color
    }

    static func contextCGColor(
        for percent: Double,
        thresholds: ModexContextThresholds,
        hasData: Bool = true
    ) -> CGColor {
        contextAccent(for: percent, thresholds: thresholds, hasData: hasData).cgColor
    }

    static var calmContextColor: Color {
        contextAccent(.calm).color
    }

    static var noticeContextColor: Color {
        contextAccent(.notice).color
    }

    static var warningContextColor: Color {
        contextAccent(.warning).color
    }

    static var criticalContextColor: Color {
        contextAccent(.critical).color
    }

    private static func contextAccent(
        for percent: Double,
        thresholds: ModexContextThresholds,
        hasData: Bool = true
    ) -> ModexContextAccent {
        guard hasData else {
            return contextAccent(.unknown)
        }
        switch percent {
        case ..<thresholds.yellowPercent:
            return contextAccent(.calm)
        case ..<thresholds.orangePercent:
            return contextAccent(.notice)
        case ..<thresholds.redPercent:
            return contextAccent(.warning)
        default:
            return contextAccent(.critical)
        }
    }

    static func remainingColor(for percentLeft: Double?) -> Color {
        guard let percentLeft else {
            return contextAccent(.unknown).color
        }

        switch percentLeft {
        case ..<10:
            return criticalContextColor
        case ..<22:
            return warningContextColor
        case ..<45:
            return noticeContextColor
        default:
            return calmContextColor
        }
    }

    private static func contextAccent(_ level: ContextLevel) -> ModexContextAccent {
        switch level {
        case .calm:
            return ModexContextAccent(red: 0.30, green: 0.67, blue: 0.62, alpha: 1)
        case .notice:
            return ModexContextAccent(red: 0.80, green: 0.64, blue: 0.26, alpha: 1)
        case .warning:
            return ModexContextAccent(red: 0.74, green: 0.47, blue: 0.28, alpha: 1)
        case .critical:
            return ModexContextAccent(red: 0.79, green: 0.34, blue: 0.34, alpha: 1)
        case .unknown:
            return ModexContextAccent(red: 0.54, green: 0.55, blue: 0.60, alpha: 1)
        }
    }

    private enum ContextLevel {
        case calm
        case notice
        case warning
        case critical
        case unknown
    }
}

private struct ModexPaletteKey: EnvironmentKey {
    static let defaultValue = ModexTheme.palette(for: .system, colorScheme: .dark)
}

extension EnvironmentValues {
    var modexPalette: ModexPalette {
        get { self[ModexPaletteKey.self] }
        set { self[ModexPaletteKey.self] = newValue }
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch value.count {
        case 6:
            red = integer >> 16
            green = integer >> 8 & 0xFF
            blue = integer & 0xFF
        default:
            red = 0
            green = 0
            blue = 0
        }

        let redComponent = CGFloat(red) / CGFloat(255)
        let greenComponent = CGFloat(green) / CGFloat(255)
        let blueComponent = CGFloat(blue) / CGFloat(255)

        self.init(
            .sRGB,
            red: redComponent,
            green: greenComponent,
            blue: blueComponent,
            opacity: 1
        )
    }
}
