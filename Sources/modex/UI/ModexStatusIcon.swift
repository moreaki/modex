import CoreGraphics
import SwiftUI

struct ModexStatusIcon: View {
    let contextUsagePercent: Double?
    var thresholds: ModexContextThresholds = .default
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = Self.makeImage(
            contextUsagePercent: contextUsagePercent,
            thresholds: thresholds,
            colorScheme: colorScheme
        ) {
            Image(decorative: image, scale: Self.scale, orientation: .up)
                .renderingMode(.original)
        } else {
            Image(systemName: "waveform.path.ecg.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
        }
    }

    private static let pointSize: CGFloat = 18
    private static let scale: CGFloat = 2

    private static func makeImage(
        contextUsagePercent: Double?,
        thresholds: ModexContextThresholds,
        colorScheme: ColorScheme
    ) -> CGImage? {
        let pixelSize = Int(pointSize * scale)
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let percent = min(max(contextUsagePercent ?? 0, 0), 100)
        let progress = percent / 100
        let accent = color(
            for: percent,
            thresholds: thresholds,
            hasData: contextUsagePercent != nil
        )
        let center = CGPoint(x: pointSize / 2, y: pointSize / 2)
        let radius: CGFloat = pointSize / 2 - 2.5

        context.setStrokeColor(primaryColor(for: colorScheme).copy(alpha: 0.16) ?? CGColor(gray: 1, alpha: 0.16))
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: 2.5, y: 2.5, width: 13, height: 13))

        context.setStrokeColor(accent)
        context.setLineWidth(2.3)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + (2 * .pi * progress),
            clockwise: false
        )
        context.strokePath()

        context.setFillColor(accent.copy(alpha: 0.18) ?? accent)
        context.fillEllipse(in: CGRect(x: 5.3, y: 5.3, width: 7.4, height: 7.4))

        let pulse = CGMutablePath()
        pulse.move(to: mirroredPoint(x: 4.2, y: center.y - 0.8))
        pulse.addLine(to: mirroredPoint(x: 6.2, y: center.y - 0.8))
        pulse.addLine(to: mirroredPoint(x: 7.5, y: center.y + 3.2))
        pulse.addLine(to: mirroredPoint(x: 9.4, y: center.y - 3.1))
        pulse.addLine(to: mirroredPoint(x: 11.2, y: center.y + 1.5))
        pulse.addLine(to: mirroredPoint(x: 13.8, y: center.y + 1.5))
        context.addPath(pulse)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.94))
        context.setLineWidth(1.35)
        context.strokePath()

        return context.makeImage()
    }

    private static func mirroredPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: pointSize - y)
    }

    private static func color(
        for percent: Double,
        thresholds: ModexContextThresholds,
        hasData: Bool
    ) -> CGColor {
        ModexTheme.contextCGColor(for: percent, thresholds: thresholds, hasData: hasData)
    }

    private static func primaryColor(for colorScheme: ColorScheme) -> CGColor {
        switch colorScheme {
        case .light:
            return CGColor(gray: 0, alpha: 1)
        case .dark:
            return CGColor(gray: 1, alpha: 1)
        @unknown default:
            return CGColor(gray: 1, alpha: 1)
        }
    }
}
