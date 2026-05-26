import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let outputDir = root.appendingPathComponent("LogoOptions", isDirectory: true)
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
        throw NSError(domain: "LogoOptions", code: 1)
    }
    try data.write(to: url)
}

func iconImage(size: CGFloat, variant: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.055, dy: size * 0.055), xRadius: size * 0.23, yRadius: size * 0.23)
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    let bgColors: [(UInt32, UInt32)] = [
        (0x101317, 0x050608), (0x0e1218, 0x05070a), (0x111416, 0x060707), (0x121216, 0x050507), (0x10151a, 0x050608),
        (0x121318, 0x050608), (0x0f1412, 0x050806), (0x121210, 0x060504), (0x101217, 0x050608), (0x111318, 0x050608)
    ]
    let pair = bgColors[variant - 1]
    NSGradient(colors: [color(pair.0), color(pair.1)])?.draw(in: rect, angle: 270)
    NSGraphicsContext.restoreGraphicsState()

    color(0xffffff, alpha: 0.12).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.058, dy: size * 0.058), xRadius: size * 0.23, yRadius: size * 0.23)
    border.lineWidth = max(1, size * 0.012)
    border.stroke()

    switch variant {
    case 1: drawCrownRing(size)
    case 2: drawTokenHex(size)
    case 3: drawMeterDial(size)
    case 4: drawPromptSpark(size)
    case 5: drawOrbitBars(size)
    case 6: drawMonogramCut(size)
    case 7: drawStackBars(size)
    case 8: drawCoinPulse(size)
    case 9: drawSegmentC(size)
    default: drawWaveCore(size)
    }

    image.unlockFocus()
    return image
}

func arc(center: CGPoint, radius: CGFloat, from: CGFloat, to: CGFloat, width: CGFloat, stroke: NSColor) {
    let p = NSBezierPath()
    p.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
    p.lineWidth = width
    p.lineCapStyle = .round
    stroke.setStroke()
    p.stroke()
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawCrownRing(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.52)
    arc(center: c, radius: s * 0.29, from: 140, to: 406, width: s * 0.095, stroke: color(0x35e06f))
    arc(center: c, radius: s * 0.29, from: 410, to: 447, width: s * 0.095, stroke: color(0xff8a33))
    for (i, h) in [0.12, 0.18, 0.26].enumerated() {
        rounded(NSRect(x: s * (0.39 + CGFloat(i) * 0.07), y: s * (0.53 - h / 2), width: s * 0.027, height: s * h), radius: s * 0.014, fill: .white.withAlphaComponent(0.86))
    }
}

func drawTokenHex(_ s: CGFloat) {
    let p = NSBezierPath()
    let c = CGPoint(x: s * 0.5, y: s * 0.5)
    let r = s * 0.31
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 + .pi / 6
        let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    color(0x42d6ff, alpha: 0.18).setFill()
    p.fill()
    p.lineWidth = s * 0.055
    color(0x42d6ff).setStroke()
    p.stroke()
    rounded(NSRect(x: s * 0.37, y: s * 0.46, width: s * 0.26, height: s * 0.065), radius: s * 0.032, fill: color(0x35e06f))
    rounded(NSRect(x: s * 0.42, y: s * 0.57, width: s * 0.16, height: s * 0.045), radius: s * 0.022, fill: .white.withAlphaComponent(0.82))
}

func drawMeterDial(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.56)
    arc(center: c, radius: s * 0.31, from: 205, to: 335, width: s * 0.09, stroke: color(0x2e3136))
    arc(center: c, radius: s * 0.31, from: 205, to: 293, width: s * 0.09, stroke: color(0x34e26d))
    let needle = NSBezierPath()
    needle.move(to: c)
    needle.line(to: CGPoint(x: s * 0.62, y: s * 0.43))
    needle.lineWidth = s * 0.035
    needle.lineCapStyle = .round
    color(0xff6a3d).setStroke()
    needle.stroke()
    rounded(NSRect(x: s * 0.46, y: s * 0.52, width: s * 0.08, height: s * 0.08), radius: s * 0.04, fill: .white.withAlphaComponent(0.9))
}

func drawPromptSpark(_ s: CGFloat) {
    let box = NSBezierPath(roundedRect: NSRect(x: s * 0.2, y: s * 0.31, width: s * 0.6, height: s * 0.38), xRadius: s * 0.09, yRadius: s * 0.09)
    color(0x1c2229).setFill()
    box.fill()
    color(0x35e06f).setStroke()
    box.lineWidth = s * 0.035
    box.stroke()
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: s * 0.32, y: s * 0.44))
    chevron.line(to: CGPoint(x: s * 0.42, y: s * 0.50))
    chevron.line(to: CGPoint(x: s * 0.32, y: s * 0.56))
    chevron.lineWidth = s * 0.035
    chevron.lineCapStyle = .round
    color(0x42d6ff).setStroke()
    chevron.stroke()
    rounded(NSRect(x: s * 0.49, y: s * 0.53, width: s * 0.2, height: s * 0.032), radius: s * 0.016, fill: .white.withAlphaComponent(0.82))
}

func drawOrbitBars(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.5)
    arc(center: c, radius: s * 0.31, from: 25, to: 265, width: s * 0.045, stroke: color(0x35e06f))
    arc(center: c, radius: s * 0.22, from: 205, to: 500, width: s * 0.045, stroke: color(0x42d6ff, alpha: 0.9))
    rounded(NSRect(x: s * 0.66, y: s * 0.22, width: s * 0.09, height: s * 0.09), radius: s * 0.045, fill: color(0xff8a33))
    for i in 0..<4 {
        rounded(NSRect(x: s * (0.38 + CGFloat(i) * 0.055), y: s * 0.47, width: s * 0.025, height: s * (0.08 + CGFloat(i) * 0.025)), radius: s * 0.012, fill: .white.withAlphaComponent(0.86))
    }
}

func drawMonogramCut(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.51)
    arc(center: c, radius: s * 0.29, from: 55, to: 305, width: s * 0.11, stroke: color(0x35e06f))
    rounded(NSRect(x: s * 0.51, y: s * 0.33, width: s * 0.09, height: s * 0.36), radius: s * 0.045, fill: color(0x111318))
    rounded(NSRect(x: s * 0.45, y: s * 0.33, width: s * 0.23, height: s * 0.075), radius: s * 0.037, fill: .white.withAlphaComponent(0.9))
}

func drawStackBars(_ s: CGFloat) {
    for i in 0..<3 {
        let y = s * (0.34 + CGFloat(i) * 0.12)
        let path = NSBezierPath(roundedRect: NSRect(x: s * 0.29, y: y, width: s * 0.42, height: s * 0.105), xRadius: s * 0.052, yRadius: s * 0.052)
        [color(0x35e06f), color(0x42d6ff), color(0xff8a33)][i].setFill()
        path.fill()
    }
    rounded(NSRect(x: s * 0.36, y: s * 0.3, width: s * 0.07, height: s * 0.45), radius: s * 0.035, fill: color(0x050607, alpha: 0.62))
    rounded(NSRect(x: s * 0.49, y: s * 0.3, width: s * 0.07, height: s * 0.45), radius: s * 0.035, fill: color(0x050607, alpha: 0.62))
}

func drawCoinPulse(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.5)
    color(0x35e06f, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.22, y: s * 0.22, width: s * 0.56, height: s * 0.56)).fill()
    arc(center: c, radius: s * 0.28, from: 0, to: 360, width: s * 0.055, stroke: color(0x35e06f))
    let pulse = NSBezierPath()
    pulse.move(to: CGPoint(x: s * 0.31, y: s * 0.51))
    pulse.line(to: CGPoint(x: s * 0.41, y: s * 0.51))
    pulse.line(to: CGPoint(x: s * 0.46, y: s * 0.39))
    pulse.line(to: CGPoint(x: s * 0.54, y: s * 0.63))
    pulse.line(to: CGPoint(x: s * 0.6, y: s * 0.51))
    pulse.line(to: CGPoint(x: s * 0.7, y: s * 0.51))
    pulse.lineWidth = s * 0.035
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    pulse.stroke()
}

func drawSegmentC(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.5)
    for (start, end, hex) in [(50.0, 134.0, 0x35e06f), (154.0, 238.0, 0x42d6ff), (258.0, 342.0, 0xff8a33)] {
        arc(center: c, radius: s * 0.29, from: CGFloat(start), to: CGFloat(end), width: s * 0.095, stroke: color(UInt32(hex)))
    }
    rounded(NSRect(x: s * 0.44, y: s * 0.44, width: s * 0.12, height: s * 0.12), radius: s * 0.06, fill: .white.withAlphaComponent(0.88))
}

func drawWaveCore(_ s: CGFloat) {
    let c = CGPoint(x: s * 0.5, y: s * 0.5)
    arc(center: c, radius: s * 0.32, from: 125, to: 410, width: s * 0.055, stroke: color(0x35e06f))
    for i in 0..<7 {
        let x = s * (0.31 + CGFloat(i) * 0.063)
        let h = s * (i % 2 == 0 ? 0.16 : 0.28)
        let rect = NSRect(x: x, y: s * 0.5 - h / 2, width: s * 0.026, height: h)
        rounded(rect, radius: s * 0.013, fill: i == 3 ? color(0xff8a33) : .white.withAlphaComponent(0.84))
    }
}

func contactSheet(images: [NSImage]) -> NSImage {
    let cellW: CGFloat = 220
    let cellH: CGFloat = 250
    let cols = 5
    let rows = 2
    let sheet = NSImage(size: NSSize(width: cellW * CGFloat(cols), height: cellH * CGFloat(rows)))
    sheet.lockFocus()
    color(0x0a0b0d).setFill()
    NSRect(x: 0, y: 0, width: sheet.size.width, height: sheet.size.height).fill()

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.58)
    ]

    for i in 0..<images.count {
        let row = i / cols
        let col = i % cols
        let origin = CGPoint(x: CGFloat(col) * cellW, y: CGFloat(rows - 1 - row) * cellH)
        let card = NSRect(x: origin.x + 14, y: origin.y + 14, width: cellW - 28, height: cellH - 28)
        rounded(card, radius: 18, fill: color(0x15171a))
        images[i].draw(in: NSRect(x: origin.x + 46, y: origin.y + 28, width: 128, height: 128))
        ("Option \(i + 1)" as NSString).draw(in: NSRect(x: origin.x + 28, y: origin.y + 166, width: cellW - 56, height: 28), withAttributes: titleAttrs)
        let label = [
            "C Ring", "Token Hex", "Meter Dial", "Prompt Box", "Orbit Bars",
            "Sharp C", "Stack Bars", "Coin Pulse", "Segment Core", "Wave Core"
        ][i]
        (label as NSString).draw(in: NSRect(x: origin.x + 28, y: origin.y + 198, width: cellW - 56, height: 20), withAttributes: subAttrs)
    }
    sheet.unlockFocus()
    return sheet
}

var icons: [NSImage] = []
for index in 1...10 {
    let icon = iconImage(size: 512, variant: index)
    icons.append(icon)
    try writePNG(icon, to: outputDir.appendingPathComponent("option-\(index).png"))
}
try writePNG(contactSheet(images: icons), to: outputDir.appendingPathComponent("logo-options-contact-sheet.png"))
