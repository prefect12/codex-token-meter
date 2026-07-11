import Cocoa

extension UsageDetailsView {
    func drawInputFieldBackground(_ rect: NSRect) {
        guard selectedSection == .costs, !rect.isEmpty else { return }
        inputSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let focused = costAmountField.currentEditor() != nil && rect == costAmountField.frame
            || paymentStartDayField.currentEditor() != nil && rect == paymentStartDayField.frame
        (focused ? accentBlue.withAlphaComponent(0.72) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    func drawSmallButton(_ title: String, rect: NSRect, emphasized: Bool = false) {
        (emphasized ? accentBlue.withAlphaComponent(0.72) : NSColor.white.withAlphaComponent(0.12)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        (emphasized ? accentTeal.withAlphaComponent(0.34) : NSColor.white.withAlphaComponent(0.09)).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 6, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(emphasized ? 0.96 : 0.78))
    }

    func drawInfoMark(rect: NSRect, highlighted: Bool) {
        (highlighted ? accentTeal.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.10)).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        (highlighted ? accentTeal.withAlphaComponent(0.74) : NSColor.white.withAlphaComponent(0.18)).setStroke()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).stroke()
        drawCentered("?", rect: rect.offsetBy(dx: 0, dy: -0.5), font: .systemFont(ofSize: 10, weight: .bold), color: highlighted ? accentTeal : NSColor.white.withAlphaComponent(0.58))
    }

    func drawSelectablePill(_ title: String, rect: NSRect, selected: Bool) {
        if selected {
            accentBlue.withAlphaComponent(0.72).setFill()
        } else {
            inputSurfaceColor.withAlphaComponent(0.82).setFill()
        }
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (selected ? accentTeal.withAlphaComponent(0.38) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
    }

    func contributionColor(_ intensity: Double) -> NSColor {
        if intensity <= 0 { return NSColor.white.withAlphaComponent(0.08) }
        if intensity < 0.25 { return accentTeal.withAlphaComponent(0.30) }
        if intensity < 0.50 { return accentTeal.withAlphaComponent(0.52) }
        if intensity < 0.75 { return accentTeal.withAlphaComponent(0.74) }
        return accentTeal
    }

    func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    func drawTruncatedText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    func drawMultilineText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    func fillDonut(in outerRect: NSRect, thickness: CGFloat, color: NSColor) {
        let innerRect = outerRect.insetBy(dx: thickness, dy: thickness)
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendOval(in: outerRect)
        path.appendOval(in: innerRect)
        color.setFill()
        path.fill()
    }

    func fillDonutSegment(center: CGPoint, outerRadius: CGFloat, thickness: CGFloat, startAngle: CGFloat, endAngle: CGFloat, color: NSColor) {
        let innerRadius = max(0, outerRadius - thickness)
        let path = NSBezierPath()
        let startDegrees = startAngle * 180 / .pi
        let endDegrees = endAngle * 180 / .pi
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: startDegrees, endAngle: endDegrees, clockwise: false)
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: endDegrees, endAngle: startDegrees, clockwise: true)
        path.close()
        color.setFill()
        path.fill()
    }

    func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - ceil(size.height) / 2,
            width: rect.width,
            height: ceil(size.height)
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    func drawRight(_ text: String, rect: NSRect, color: NSColor, font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
