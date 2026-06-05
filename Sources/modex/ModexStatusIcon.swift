import AppKit

enum ModexStatusIcon {
    static func make(contextUsagePercent: Double?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect, contextUsagePercent: contextUsagePercent)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(in rect: NSRect, contextUsagePercent: Double?) {
        let percent = min(max(contextUsagePercent ?? 0, 0), 100)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 2.5
        let color = color(for: percent, hasData: contextUsagePercent != nil)

        let background = NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
        NSColor.labelColor.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 2
        background.stroke()

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - (percent / 100 * 360),
            clockwise: true
        )
        color.setStroke()
        arc.lineWidth = 2.3
        arc.lineCapStyle = .round
        arc.stroke()

        let glow = NSBezierPath(ovalIn: rect.insetBy(dx: 5.3, dy: 5.3))
        color.withAlphaComponent(0.18).setFill()
        glow.fill()

        let pulse = NSBezierPath()
        pulse.move(to: NSPoint(x: rect.minX + 4.2, y: rect.midY - 0.8))
        pulse.line(to: NSPoint(x: rect.minX + 6.2, y: rect.midY - 0.8))
        pulse.line(to: NSPoint(x: rect.minX + 7.5, y: rect.midY + 3.2))
        pulse.line(to: NSPoint(x: rect.minX + 9.4, y: rect.midY - 3.1))
        pulse.line(to: NSPoint(x: rect.minX + 11.2, y: rect.midY + 1.5))
        pulse.line(to: NSPoint(x: rect.minX + 13.8, y: rect.midY + 1.5))
        NSColor.white.withAlphaComponent(0.92).setStroke()
        pulse.lineWidth = 1.35
        pulse.lineJoinStyle = .round
        pulse.lineCapStyle = .round
        pulse.stroke()
    }

    private static func color(for percent: Double, hasData: Bool) -> NSColor {
        guard hasData else {
            return .systemGray
        }
        switch percent {
        case ..<55:
            return .systemMint
        case ..<78:
            return .systemYellow
        case ..<90:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}
