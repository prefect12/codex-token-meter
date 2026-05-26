import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let outputDir = root.appendingPathComponent("CodexStyleLogoOptions", isDirectory: true)
try? FileManager.default.removeItem(at: outputDir)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

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
        throw NSError(domain: "CodexStyleLogoOptions", code: 1)
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

func cloudPath(size s: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendOval(in: NSRect(x: s * 0.20, y: s * 0.35, width: s * 0.32, height: s * 0.32))
    path.appendOval(in: NSRect(x: s * 0.33, y: s * 0.24, width: s * 0.38, height: s * 0.38))
    path.appendOval(in: NSRect(x: s * 0.51, y: s * 0.31, width: s * 0.31, height: s * 0.31))
    path.appendOval(in: NSRect(x: s * 0.24, y: s * 0.49, width: s * 0.31, height: s * 0.29))
    path.appendOval(in: NSRect(x: s * 0.43, y: s * 0.51, width: s * 0.36, height: s * 0.30))
    return path
}

func drawTile(size s: CGFloat, dark: Bool = false) {
    let tile = NSRect(x: s * 0.055, y: s * 0.055, width: s * 0.89, height: s * 0.89)
    NSGraphicsContext.saveGraphicsState()
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.22, yRadius: s * 0.22)
    tilePath.addClip()
    if dark {
        NSGradient(colors: [color(0x161921), color(0x050609)])?.draw(in: tile, angle: 270)
    } else {
        NSGradient(colors: [color(0xffffff), color(0xf1f3f8)])?.draw(in: tile, angle: 270)
    }
    NSGraphicsContext.restoreGraphicsState()
    strokeRounded(tile.insetBy(dx: s * 0.006, dy: s * 0.006), radius: s * 0.22, stroke: dark ? color(0xffffff, alpha: 0.12) : color(0x000000, alpha: 0.10), width: max(1, s * 0.01))
}

func fillCloud(size s: CGFloat, dark: Bool = false) {
    let cloud = cloudPath(size: s)
    NSGraphicsContext.saveGraphicsState()
    cloud.addClip()
    NSGradient(colors: dark ? [color(0x8bd0ff), color(0x4060ff), color(0x9c7cff)] : [color(0xbda5ff), color(0x4a72ff), color(0x231cff)])?.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: 255)
    NSGraphicsContext.restoreGraphicsState()
    color(0xffffff, alpha: dark ? 0.20 : 0.28).setStroke()
    cloud.lineWidth = s * 0.018
    cloud.stroke()
}

func drawPrompt(size s: CGFloat, x: CGFloat, y: CGFloat, scale: CGFloat = 1, dark: Bool = false) {
    let w = s * 0.055 * scale
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: x, y: y))
    chevron.line(to: CGPoint(x: x + w, y: y + w * 1.55))
    chevron.line(to: CGPoint(x: x, y: y + w * 3.1))
    chevron.lineWidth = s * 0.035 * scale
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    (dark ? color(0x07111f, alpha: 0.92) : color(0xffffff, alpha: 0.92)).setStroke()
    chevron.stroke()
    rounded(NSRect(x: x + w * 2.45, y: y + w * 2.18, width: s * 0.18 * scale, height: s * 0.04 * scale), radius: s * 0.02 * scale, fill: dark ? color(0x07111f, alpha: 0.88) : color(0xffffff, alpha: 0.88))
}

func drawBars(size s: CGFloat, color barColor: NSColor = .white, x: CGFloat = 0.41, y: CGFloat = 0.50) {
    for (index, h) in [0.09, 0.15, 0.22].enumerated() {
        rounded(NSRect(x: s * (x + CGFloat(index) * 0.055), y: s * (y - CGFloat(h) / 2), width: s * 0.026, height: s * CGFloat(h)), radius: s * 0.013, fill: barColor.withAlphaComponent(0.90))
    }
}

func iconImage(size s: CGFloat, variant: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    switch variant {
    case 1:
        drawTile(size: s)
        fillCloud(size: s)
        drawPrompt(size: s, x: s * 0.36, y: s * 0.41)
        arc(center: CGPoint(x: s * 0.62, y: s * 0.62), radius: s * 0.19, from: 210, to: 330, width: s * 0.045, stroke: color(0x27d86c))
    case 2:
        drawTile(size: s)
        fillCloud(size: s)
        drawBars(size: s)
        arc(center: CGPoint(x: s * 0.50, y: s * 0.55), radius: s * 0.31, from: 122, to: 412, width: s * 0.035, stroke: color(0xffffff, alpha: 0.72))
    case 3:
        drawTile(size: s)
        fillCloud(size: s)
        arc(center: CGPoint(x: s * 0.50, y: s * 0.56), radius: s * 0.24, from: 202, to: 326, width: s * 0.075, stroke: color(0xffffff, alpha: 0.58))
        arc(center: CGPoint(x: s * 0.50, y: s * 0.56), radius: s * 0.24, from: 202, to: 286, width: s * 0.075, stroke: color(0x5cff94))
        drawPrompt(size: s, x: s * 0.36, y: s * 0.43, scale: 0.72)
    case 4:
        drawTile(size: s, dark: true)
        fillCloud(size: s, dark: true)
        drawPrompt(size: s, x: s * 0.36, y: s * 0.41)
        rounded(NSRect(x: s * 0.65, y: s * 0.29, width: s * 0.10, height: s * 0.10), radius: s * 0.05, fill: color(0x5cff94))
    case 5:
        drawTile(size: s)
        arc(center: CGPoint(x: s * 0.50, y: s * 0.52), radius: s * 0.32, from: 112, to: 430, width: s * 0.055, stroke: color(0x496dff))
        fillCloud(size: s)
        drawBars(size: s, color: color(0xffffff), x: 0.38, y: 0.55)
    case 6:
        drawTile(size: s, dark: true)
        let c = CGPoint(x: s * 0.50, y: s * 0.52)
        arc(center: c, radius: s * 0.31, from: 42, to: 318, width: s * 0.075, stroke: color(0x88a9ff))
        arc(center: c, radius: s * 0.31, from: 320, to: 383, width: s * 0.075, stroke: color(0xb8a0ff))
        drawPrompt(size: s, x: s * 0.37, y: s * 0.40)
    case 7:
        drawTile(size: s)
        fillCloud(size: s)
        for i in 0..<3 {
            rounded(NSRect(x: s * 0.35, y: s * (0.45 + CGFloat(i) * 0.075), width: s * 0.30, height: s * 0.048), radius: s * 0.024, fill: [color(0xffffff), color(0xccd8ff), color(0x5cff94)][i].withAlphaComponent(0.92))
        }
    case 8:
        drawTile(size: s)
        fillCloud(size: s)
        let pulse = NSBezierPath()
        pulse.move(to: CGPoint(x: s * 0.30, y: s * 0.55))
        pulse.line(to: CGPoint(x: s * 0.41, y: s * 0.55))
        pulse.line(to: CGPoint(x: s * 0.47, y: s * 0.43))
        pulse.line(to: CGPoint(x: s * 0.55, y: s * 0.66))
        pulse.line(to: CGPoint(x: s * 0.61, y: s * 0.55))
        pulse.line(to: CGPoint(x: s * 0.73, y: s * 0.55))
        pulse.lineWidth = s * 0.035
        pulse.lineCapStyle = .round
        pulse.lineJoinStyle = .round
        color(0xffffff, alpha: 0.92).setStroke()
        pulse.stroke()
    case 9:
        drawTile(size: s, dark: true)
        fillCloud(size: s, dark: true)
        arc(center: CGPoint(x: s * 0.50, y: s * 0.54), radius: s * 0.25, from: 200, to: 310, width: s * 0.07, stroke: color(0x5cff94))
        rounded(NSRect(x: s * 0.59, y: s * 0.47, width: s * 0.18, height: s * 0.045), radius: s * 0.022, fill: color(0x07111f, alpha: 0.82))
    default:
        drawTile(size: s)
        let p = NSBezierPath()
        p.appendOval(in: NSRect(x: s * 0.23, y: s * 0.25, width: s * 0.54, height: s * 0.54))
        NSGraphicsContext.saveGraphicsState()
        p.addClip()
        NSGradient(colors: [color(0xbca4ff), color(0x406dff), color(0x241dff)])?.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: 255)
        NSGraphicsContext.restoreGraphicsState()
        drawPrompt(size: s, x: s * 0.36, y: s * 0.41)
        arc(center: CGPoint(x: s * 0.50, y: s * 0.52), radius: s * 0.31, from: 18, to: 92, width: s * 0.04, stroke: color(0x5cff94))
    }

    image.unlockFocus()
    return image
}

func contactSheet(images: [NSImage]) -> NSImage {
    let cellW: CGFloat = 230
    let cellH: CGFloat = 260
    let cols = 5
    let rows = 2
    let sheet = NSImage(size: NSSize(width: cellW * CGFloat(cols), height: cellH * CGFloat(rows)))
    sheet.lockFocus()
    color(0x0b0c10).setFill()
    NSRect(x: 0, y: 0, width: sheet.size.width, height: sheet.size.height).fill()

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 23, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.58)
    ]
    let labels = [
        "Cloud Prompt", "Cloud Meter", "Quota Dial", "Dark Codex", "Ring Cloud",
        "Orbital Prompt", "Token Stack", "Pulse Cloud", "Compact Meter", "Round Codex"
    ]

    for i in 0..<images.count {
        let row = i / cols
        let col = i % cols
        let origin = CGPoint(x: CGFloat(col) * cellW, y: CGFloat(rows - 1 - row) * cellH)
        let card = NSRect(x: origin.x + 14, y: origin.y + 14, width: cellW - 28, height: cellH - 28)
        rounded(card, radius: 20, fill: color(0x1b1d22))
        images[i].draw(in: NSRect(x: origin.x + 51, y: origin.y + 30, width: 128, height: 128))
        ("Option \(i + 1)" as NSString).draw(in: NSRect(x: origin.x + 28, y: origin.y + 170, width: cellW - 56, height: 28), withAttributes: titleAttrs)
        (labels[i] as NSString).draw(in: NSRect(x: origin.x + 28, y: origin.y + 202, width: cellW - 56, height: 20), withAttributes: subAttrs)
    }
    sheet.unlockFocus()
    return sheet
}

var icons: [NSImage] = []
for index in 1...10 {
    let icon = iconImage(size: 1024, variant: index)
    icons.append(icon)
    try writePNG(icon, to: outputDir.appendingPathComponent("codex-style-option-\(index).png"))
}
try writePNG(contactSheet(images: icons), to: outputDir.appendingPathComponent("codex-style-logo-options.png"))

