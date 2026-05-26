import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Logo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokeRounded(_ rect: NSRect, radius: CGFloat, stroke: NSColor, width: CGFloat) {
    stroke.setStroke()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

func arc(center: CGPoint, radius: CGFloat, from: CGFloat, to: CGFloat, width: CGFloat, stroke: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
    path.lineWidth = width
    path.lineCapStyle = .round
    stroke.setStroke()
    path.stroke()
}

func drawPrompt(size: CGFloat, monochrome: Bool) {
    let stroke = monochrome ? NSColor.black : NSColor.white.withAlphaComponent(0.92)
    let x = size * 0.36
    let y = size * 0.41
    let unit = size * 0.055

    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: x, y: y))
    chevron.line(to: CGPoint(x: x + unit, y: y + unit * 1.55))
    chevron.line(to: CGPoint(x: x, y: y + unit * 3.1))
    chevron.lineWidth = size * 0.035
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    stroke.setStroke()
    chevron.stroke()

    rounded(
        NSRect(x: x + unit * 2.45, y: y + unit * 2.18, width: size * 0.18, height: size * 0.04),
        radius: size * 0.02,
        fill: stroke
    )
}

func drawOrbitalMark(size: CGFloat, monochrome: Bool) {
    let center = CGPoint(x: size * 0.5, y: size * 0.52)
    let main = monochrome ? NSColor.black : color(0x95b3ff)
    let accent = monochrome ? NSColor.black : color(0xb7a3ff)
    let faint = monochrome ? NSColor.black.withAlphaComponent(0.22) : color(0xffffff, alpha: 0.10)

    arc(center: center, radius: size * 0.31, from: 42, to: 318, width: size * 0.075, stroke: main)
    arc(center: center, radius: size * 0.31, from: 320, to: 383, width: size * 0.075, stroke: accent)
    arc(center: center, radius: size * 0.22, from: 210, to: 505, width: size * 0.018, stroke: faint)
    drawPrompt(size: size, monochrome: monochrome)
}

func logoImage(size: CGFloat, background: Bool, monochrome: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    if background {
        let tile = rect.insetBy(dx: size * 0.055, dy: size * 0.055)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: size * 0.23, yRadius: size * 0.23)
        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        NSGradient(colors: [color(0x151923), color(0x050609)])?.draw(in: tile, angle: 270)
        color(0x93b0ff, alpha: 0.12).setFill()
        NSBezierPath(ovalIn: NSRect(x: size * 0.16, y: size * 0.16, width: size * 0.66, height: size * 0.66)).fill()
        NSGraphicsContext.restoreGraphicsState()

        strokeRounded(
            tile.insetBy(dx: size * 0.006, dy: size * 0.006),
            radius: size * 0.23,
            stroke: color(0xffffff, alpha: 0.12),
            width: max(1, size * 0.01)
        )
    }

    drawOrbitalMark(size: size, monochrome: monochrome)
    image.unlockFocus()
    return image
}

try writePNG(logoImage(size: 256, background: true, monochrome: false), to: resources.appendingPathComponent("LogoHeader.png"))
try writePNG(logoImage(size: 36, background: false, monochrome: true), to: resources.appendingPathComponent("StatusIconTemplate.png"))

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    try writePNG(logoImage(size: size, background: true, monochrome: false), to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "Logo", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

