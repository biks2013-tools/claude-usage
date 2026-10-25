import AppKit

/// The menu bar icon: the app icon's mark (a 270° usage gauge, two thirds
/// full, around a spark) as a template image, so macOS tints it for light,
/// dark and highlighted menu bars.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: 9, y: 8.6)
            let radius: CGFloat = 7.4
            let start = CGFloat.pi * 1.25, sweep = CGFloat.pi * 1.5
            let end = start - sweep * 0.68
            ctx.setLineCap(.round)
            ctx.setLineWidth(2)

            // The track, faint, then the filled part.
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: end, endAngle: start - sweep, clockwise: true)
            ctx.strokePath()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            ctx.strokePath()

            // The spark: eight rounded rays.
            ctx.setLineWidth(1.5)
            let lengths: [CGFloat] = [3.6, 3.0, 3.4, 2.9]
            for i in 0..<8 {
                let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 4
                let len = lengths[i % lengths.count]
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + cos(a) * len, y: center.y + sin(a) * len))
            }
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Claude usage"
        return image
    }()
}
