// Draws the app icon: a usage gauge (a 270° ring, two thirds full, with a
// knob at the reading) around a spark, cream on a warm terracotta tile.
// Writes Resources/AppIcon.icns (and a 1024 px preview next to it).
//
//   swift scripts/make-icon.swift
//
// The menu bar icon is the same mark as a template image, drawn by the app
// (StatusIcon in Sources/ClaudeUsage/StatusIcon.swift).
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A spark: rounded rays of slightly different lengths around a hub.
func spark(center c: CGPoint, length: CGFloat, width: CGFloat, rays: Int, rotation: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let lengths: [CGFloat] = [1, 0.82, 0.94, 0.78, 0.97, 0.85]
    for i in 0..<rays {
        let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(rays)
        let len = length * lengths[i % lengths.count]
        let ray = CGMutablePath()
        ray.move(to: c)
        ray.addLine(to: CGPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len))
        path.addPath(ray.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }
    return path
}

func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // The tile, on Apple's icon grid: 824 pt with a continuous-looking corner.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0xC8603C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let warm = CGGradient(colorsSpace: space, colors: [color(0xF0A07A), color(0xD9714A), color(0xA9442A)] as CFArray,
                          locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(warm, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // A soft glow behind the gauge.
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFE6D2, 0.35), color(0xFFE6D2, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 540), endRadius: 400, options: [])
    // Top sheen.
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    // The gauge: a 270° ring open at the bottom, filled two thirds of the way.
    let center = CGPoint(x: 512, y: 500)
    let radius: CGFloat = 270, ring: CGFloat = 64
    let start = CGFloat.pi * 1.25          // lower left
    let sweep = CGFloat.pi * 1.5
    let reading: CGFloat = 0.68
    let end = start - sweep * reading      // clockwise

    let track = CGMutablePath()
    track.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.saveGState()
    ctx.addPath(track)
    ctx.setLineWidth(ring)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0x5A1E0E, 0.28))
    ctx.strokePath()
    ctx.restoreGState()

    // Ticks inside the ring, every 12.5 %.
    ctx.saveGState()
    ctx.setStrokeColor(color(0xFFF1E6, 0.55))
    ctx.setLineCap(.round)
    for i in 0...8 {
        let a = start - sweep * CGFloat(i) / 8
        let r1 = radius - ring / 2 - 28, r2 = r1 - (i % 2 == 0 ? 30 : 16)
        ctx.setLineWidth(i % 2 == 0 ? 12 : 9)
        ctx.move(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * r2, y: center.y + sin(a) * r2))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // The filled part, cream to white along the ring.
    let fill = CGMutablePath()
    fill.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x6A2410, 0.45))
    ctx.addPath(fill.copy(strokingWithWidth: ring, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    let cream = CGGradient(colorsSpace: space, colors: [color(0xFFD9BF), color(0xFFFFFF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(cream, start: CGPoint(x: 200, y: 300), end: CGPoint(x: 820, y: 700), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // The knob at the reading.
    let knob = CGPoint(x: center.x + cos(end) * radius, y: center.y + sin(end) * radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0x5A1E0E, 0.5))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: knob.x - 46, y: knob.y - 46, width: 92, height: 92))
    ctx.restoreGState()
    ctx.setFillColor(color(0xD9714A))
    ctx.fillEllipse(in: CGRect(x: knob.x - 20, y: knob.y - 20, width: 40, height: 40))

    // The spark in the middle.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x6A2410, 0.45))
    ctx.addPath(spark(center: center, length: 128, width: 30, rays: 12, rotation: .pi / 2))
    ctx.setFillColor(color(0xFFF6EE))
    ctx.fillPath(using: .winding)
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: resources.appendingPathComponent("AppIcon-preview.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote Resources/AppIcon.icns and Resources/AppIcon-preview.png")
