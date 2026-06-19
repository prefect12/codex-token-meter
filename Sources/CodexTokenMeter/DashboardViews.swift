import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Dashboard Views

final class RingView: NSView {
    var percent: Double = 0 { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var subtitle: String = "" { didSet { needsDisplay = true } }
    var color: NSColor = NSColor.systemGreen { didSet { needsDisplay = true } }
    fileprivate var resetTooltip: String? {
        didSet { updateTooltip() }
    }
    fileprivate var remainingComparison: RingRemainingComparison? {
        didSet {
            needsDisplay = true
            updateTooltip()
        }
    }

    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? {
        "\(Int(round(percent)))%, \(subtitle)"
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        let labelReserve: CGFloat = 20
        let diameter = min(bounds.width, bounds.height - labelReserve)
        let rect = NSRect(x: bounds.midX - diameter / 2, y: bounds.minY, width: diameter, height: diameter)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2 - 8
        let lineWidth: CGFloat = 8
        let start = -CGFloat.pi * 0.82
        let end = CGFloat.pi * 0.82

        drawArc(center: center, radius: radius, lineWidth: lineWidth, start: start, end: end, percent: 100, color: NSColor.white.withAlphaComponent(0.10))
        drawArc(center: center, radius: radius, lineWidth: lineWidth, start: start, end: end, percent: percent, color: color)

        if let remainingComparison {
            drawRemainingComparison(
                remainingComparison,
                center: center,
                radius: radius,
                lineWidth: lineWidth,
                start: start,
                end: end
            )
        } else {
            let pText = "\(Int(round(percent)))%"
            drawCenteredAt(pText, center: center, font: meterNumberFont(ofSize: 23), color: .white)
        }
        drawCentered(title, rect: NSRect(x: bounds.minX, y: rect.maxY + 2, width: bounds.width, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.86))
        drawCentered(subtitle, rect: NSRect(x: bounds.minX, y: rect.maxY + 20, width: bounds.width, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
    }

    private func drawArc(center: CGPoint, radius: CGFloat, lineWidth: CGFloat, start: CGFloat, end: CGFloat, percent: Double, color: NSColor) {
        let clamped = max(0, min(100, percent)) / 100
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: start * 180 / .pi,
            endAngle: (start + (end - start) * CGFloat(clamped)) * 180 / .pi,
            clockwise: false
        )
        path.stroke()
    }

    private func drawRemainingComparison(
        _ comparison: RingRemainingComparison,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) {
        let markerColor = expectedRemainingMarkerColor(
            expected: comparison.expectedRemainingPercent,
            actual: comparison.actualRemainingPercent
        )
        drawExpectedRemainingMarker(
            percent: comparison.expectedRemainingPercent,
            center: center,
            radius: radius,
            lineWidth: lineWidth,
            start: start,
            end: end,
            color: markerColor
        )
        drawComparisonValue(
            value: "\(Int(round(comparison.actualRemainingPercent)))%",
            center: center,
            fontSize: 23,
            maxWidth: 76,
            valueColor: .white
        )
    }

    private func drawExpectedRemainingMarker(percent: Double, center: CGPoint, radius: CGFloat, lineWidth: CGFloat, start: CGFloat, end: CGFloat, color: NSColor) {
        let clamped = max(0, min(100, percent)) / 100
        let angle = start + (end - start) * CGFloat(clamped)
        let markerLineWidth = max(2.4, lineWidth * 0.32)
        let markerCenter = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
        let radial = CGPoint(x: cos(angle), y: sin(angle))
        let markerLength = max(15, lineWidth * 1.9)
        let halfLength = markerLength / 2
        let startPoint = CGPoint(
            x: markerCenter.x - radial.x * halfLength,
            y: markerCenter.y - radial.y * halfLength
        )
        let endPoint = CGPoint(
            x: markerCenter.x + radial.x * halfLength,
            y: markerCenter.y + radial.y * halfLength
        )

        let marker = NSBezierPath()
        marker.lineWidth = markerLineWidth
        marker.lineCapStyle = .round
        marker.move(to: startPoint)
        marker.line(to: endPoint)
        color.setStroke()
        marker.stroke()
    }

    private func expectedRemainingMarkerColor(expected: Double, actual: Double) -> NSColor {
        if actual >= expected {
            return NSColor(calibratedRed: 0.56, green: 1.0, blue: 0.16, alpha: 0.98)
        }
        return NSColor.systemYellow.withAlphaComponent(0.98)
    }

    private func drawComparisonValue(value: String, center: CGPoint, fontSize: CGFloat, maxWidth: CGFloat, valueColor: NSColor) {
        var valueFontSize = fontSize
        var valueFont = meterNumberFont(ofSize: valueFontSize)
        var valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: valueColor
        ]
        var valueSize = (value as NSString).size(withAttributes: valueAttributes)
        while valueSize.width > maxWidth, valueFontSize > 12 {
            valueFontSize -= 0.5
            valueFont = meterNumberFont(ofSize: valueFontSize)
            valueAttributes = [.font: valueFont, .foregroundColor: valueColor]
            valueSize = (value as NSString).size(withAttributes: valueAttributes)
        }
        let rowHeight = valueSize.height
        let valueY = center.y - ceil(valueSize.height) / 2 - 0.5
        (value as NSString).draw(
            in: NSRect(x: center.x - ceil(valueSize.width) / 2, y: valueY, width: ceil(valueSize.width), height: ceil(rowHeight)),
            withAttributes: valueAttributes
        )
    }

    private func updateTooltip() {
        guard remainingComparison != nil || resetTooltip != nil else {
            toolTip = nil
            return
        }
        var lines: [String] = []
        if let comparison = remainingComparison {
            let statusText: String
            switch comparison.status {
            case .ahead:
                statusText = "实际剩余低于预计，用得偏快"
            case .behind:
                statusText = "实际剩余高于预计，用得较少"
            }
            lines.append("圈内数字：实际剩余 \(Int(round(comparison.actualRemainingPercent)))%")
            lines.append("彩色标记：预计剩余 \(Int(round(comparison.expectedRemainingPercent)))%")
            lines.append(statusText)
        }
        if let resetTooltip {
            lines.append("重置：\(resetTooltip)")
        }
        toolTip = lines.joined(separator: "\n")
    }

    private func meterNumberFont(ofSize size: CGFloat) -> NSFont {
        for name in ["DIN Alternate", "DIN Condensed", "Avenir Next Condensed Heavy", "Menlo-Bold"] {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private func drawCenteredAt(_ text: String, center: CGPoint, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2 - 1,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
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
}

final class QuotaBulletView: NSView {
    var actualRemainingPercent: Double = 0 { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var subtitle: String = "" { didSet { needsDisplay = true } }
    var color: NSColor = NSColor.systemGreen { didSet { needsDisplay = true } }
    fileprivate var resetTooltip: String? {
        didSet { updateTooltip() }
    }
    fileprivate var remainingComparison: RingRemainingComparison? {
        didSet {
            needsDisplay = true
            updateTooltip()
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        let valueFont = meterNumberFont(ofSize: 16)
        let value = "\(Int(round(actualRemainingPercent)))%"
        let valueWidth = max(48, measuredTextWidth(value, font: valueFont) + 4)
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleWidth = min(bounds.width - valueWidth - 16, measuredTextWidth(title, font: titleFont) + 2)
        drawText(title, rect: NSRect(x: bounds.minX, y: bounds.minY + 1, width: titleWidth, height: 16), font: titleFont, color: NSColor.white.withAlphaComponent(0.86))
        drawText(subtitle, rect: NSRect(x: bounds.minX + titleWidth + 7, y: bounds.minY + 1, width: max(0, bounds.width - titleWidth - valueWidth - 18), height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        drawRight(value, rect: NSRect(x: bounds.maxX - valueWidth, y: bounds.minY - 2, width: valueWidth, height: 20), font: valueFont, color: color.withAlphaComponent(0.96))

        let bar = NSRect(x: bounds.minX, y: bounds.minY + 24, width: bounds.width, height: 10)
        drawTrack(in: bar)

        let actualRatio = CGFloat(max(0, min(100, actualRemainingPercent)) / 100)
        let fillWidth = max(actualRatio <= 0 ? 0 : 4, bar.width * actualRatio)
        if fillWidth > 0 {
            let fill = NSRect(x: bar.minX, y: bar.minY, width: min(bar.width, fillWidth), height: bar.height)
            color.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 5, yRadius: 5).fill()
        }

        if let comparison = remainingComparison {
            drawExpectedMarker(comparison: comparison, bar: bar)
        }
    }

    private func drawTrack(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.11).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        NSColor.white.withAlphaComponent(0.05).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
    }

    private func drawExpectedMarker(comparison: RingRemainingComparison, bar: NSRect) {
        let expected = max(0, min(100, comparison.expectedRemainingPercent))
        let x = bar.minX + bar.width * CGFloat(expected / 100)
        let markerColor = expectedRemainingMarkerColor(
            expected: comparison.expectedRemainingPercent,
            actual: comparison.actualRemainingPercent
        )
        let markerRect = NSRect(x: x - 1.5, y: bar.minY - 5, width: 3, height: bar.height + 10)
        markerColor.setFill()
        NSBezierPath(roundedRect: markerRect, xRadius: 2, yRadius: 2).fill()
    }

    private func updateTooltip() {
        guard remainingComparison != nil || resetTooltip != nil else {
            toolTip = nil
            return
        }
        var lines: [String] = []
        if let comparison = remainingComparison {
            let statusText: String
            switch comparison.status {
            case .ahead:
                statusText = "实际剩余低于预计，用得偏快"
            case .behind:
                statusText = "实际剩余高于预计，用得较少"
            }
            lines.append("填充条：实际剩余 \(Int(round(comparison.actualRemainingPercent)))%")
            lines.append("竖标线：预计剩余 \(Int(round(comparison.expectedRemainingPercent)))%")
            lines.append(statusText)
        }
        if let resetTooltip {
            lines.append("重置：\(resetTooltip)")
        }
        toolTip = lines.joined(separator: "\n")
    }

    private func expectedRemainingMarkerColor(expected: Double, actual: Double) -> NSColor {
        if actual >= expected {
            return NSColor(calibratedRed: 0.56, green: 1.0, blue: 0.16, alpha: 0.98)
        }
        return NSColor.systemYellow.withAlphaComponent(0.98)
    }

    private func meterNumberFont(ofSize size: CGFloat) -> NSFont {
        for name in ["DIN Alternate", "DIN Condensed", "Avenir Next Condensed Heavy", "Menlo-Bold"] {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawRight(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

final class UsageChartView: NSView {
    var selectedWindow: WindowOption = .week { didSet { needsDisplay = true } }
    var days: [DayUsage] = [] { didSet { hoveredIndex = nil; needsDisplay = true } }
    var hours: [HourUsage] = [] { didSet { hoveredIndex = nil; needsDisplay = true } }
    var weeklyQuotaUsedPercent: Double? { didSet { needsDisplay = true } }
    var weeklyQuotaReferenceTotal: Int64? { didSet { needsDisplay = true } }
    var costEstimator: CostEstimator? { didSet { needsDisplay = true } }
    var apiEstimate: APICostEstimate? { didSet { needsDisplay = true } }
    private var hoveredIndex: Int?
    private var hoverPoint: CGPoint?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if selectedWindow == .day {
            updateHourlyHover(at: point)
        } else {
            updateDailyHover(at: point)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        hoverPoint = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.06).setFill()
        bounds.fill()

        if selectedWindow == .day {
            drawHourlyBars()
        } else {
            drawDailyBars()
        }
        drawHoverTooltip()
    }

    private func drawHourlyBars() {
        guard !hours.isEmpty else { return }
        let plot = bounds.insetBy(dx: 12, dy: 10)
        let labelHeight: CGFloat = 16
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        let series = continuousHours()
        let maxTotal = max(series.map { $0.usage.total }.max() ?? 1, 1)
        let gap: CGFloat = 4
        let width = max(4, (chart.width - gap * CGFloat(series.count - 1)) / CGFloat(max(series.count, 1)))

        for (index, hour) in series.enumerated() {
            let x = chart.minX + CGFloat(index) * (width + gap)
            let ratio = CGFloat(Double(hour.usage.total) / Double(maxTotal))
            let height = hour.usage.total > 0 ? max(3, chart.height * ratio) : 2
            let bar = NSRect(x: x, y: chart.maxY - height, width: width, height: height)
            let isHovered = hoveredIndex == index
            (isHovered ? NSColor.systemGreen : NSColor.systemGreen.withAlphaComponent(hour.usage.total > 0 ? 0.78 : 0.20)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
            if isHovered {
                NSColor.white.withAlphaComponent(0.55).setStroke()
                let outline = NSBezierPath(roundedRect: bar.insetBy(dx: -1, dy: -1), xRadius: 3.5, yRadius: 3.5)
                outline.lineWidth = 1
                outline.stroke()
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        let labels = [(0, series.first?.hour), (series.count / 2, series.indices.contains(series.count / 2) ? series[series.count / 2].hour : nil), (max(0, series.count - 1), series.last?.hour)]
        for (index, date) in labels {
            guard let date else { continue }
            let x = chart.minX + CGFloat(index) * (width + gap) + width / 2
            drawLabel(formatter.string(from: date), rect: NSRect(x: x - 28, y: plot.maxY - labelHeight + 2, width: 56, height: labelHeight))
        }
    }

    private func drawDailyBars() {
        guard !days.isEmpty else { return }
        let maxTotal: Int64 = max(days.map { $0.usage.total }.max() ?? 1, 1)
        let minNonZero: Int64 = days.map { $0.usage.total }.filter { $0 > 0 }.min() ?? maxTotal
        let gap: CGFloat = days.count > 14 ? 3 : 6
        let labelHeight: CGFloat = 16
        let plot = bounds.insetBy(dx: 10, dy: 8)
        let width = max(3, (plot.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count))
        let labelIndexes = labelIndexesForDailyBars()

        for (index, day) in days.enumerated() {
            let x = plot.minX + CGFloat(index) * (width + gap)
            let ratio = dailyBarRatio(total: day.usage.total, maxTotal: maxTotal, minNonZero: minNonZero)
            let h = max(4, (plot.height - labelHeight) * ratio)
            let bar = NSRect(x: x, y: plot.maxY - labelHeight - h, width: width, height: h)
            let isHovered = hoveredIndex == index
            (isHovered ? NSColor.systemGreen : NSColor.systemGreen.withAlphaComponent(0.78)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            if isHovered {
                NSColor.white.withAlphaComponent(0.55).setStroke()
                let outline = NSBezierPath(roundedRect: bar.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
                outline.lineWidth = 1
                outline.stroke()
            }

            if labelIndexes.contains(index) {
                let label = selectedWindow == .month ? compactDayLabel(day.day) : String(day.day.suffix(5))
                drawLabel(label, rect: NSRect(x: x - 22, y: plot.maxY - labelHeight + 2, width: width + 44, height: labelHeight))
            }
        }
    }

    private func dailyBarRatio(total: Int64, maxTotal: Int64, minNonZero: Int64) -> CGFloat {
        guard total > 0, maxTotal > 0 else { return 0 }
        let linear = Double(total) / Double(maxTotal)
        let needsCompression = selectedWindow == .month && maxTotal / max(minNonZero, 1) > 80
        if needsCompression {
            return CGFloat(pow(linear, 0.35))
        }
        return CGFloat(linear)
    }

    private func updateDailyHover(at point: CGPoint) {
        guard !days.isEmpty else { return clearHoverIfNeeded() }
        let gap: CGFloat = days.count > 14 ? 3 : 6
        let labelHeight: CGFloat = 16
        let plot = bounds.insetBy(dx: 10, dy: 8)
        let width = max(3, (plot.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count))
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        guard chart.insetBy(dx: -4, dy: 0).contains(point) else { return clearHoverIfNeeded() }

        let raw = Int((point.x - plot.minX) / (width + gap))
        let index = min(max(raw, 0), days.count - 1)
        let x = plot.minX + CGFloat(index) * (width + gap)
        let hitRect = NSRect(x: x - max(4, gap / 2), y: chart.minY, width: width + max(8, gap), height: chart.height)
        if hitRect.contains(point) {
            hoveredIndex = index
            hoverPoint = point
        } else {
            hoveredIndex = nil
            hoverPoint = nil
        }
        needsDisplay = true
    }

    private func updateHourlyHover(at point: CGPoint) {
        let series = continuousHours()
        guard !series.isEmpty else { return clearHoverIfNeeded() }
        let plot = bounds.insetBy(dx: 12, dy: 10)
        let labelHeight: CGFloat = 16
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        guard chart.insetBy(dx: -4, dy: 0).contains(point) else { return clearHoverIfNeeded() }

        let gap: CGFloat = 4
        let width = max(4, (chart.width - gap * CGFloat(series.count - 1)) / CGFloat(max(series.count, 1)))
        let raw = Int((point.x - chart.minX) / (width + gap))
        let index = min(max(raw, 0), series.count - 1)
        let x = chart.minX + CGFloat(index) * (width + gap)
        let hitRect = NSRect(x: x - max(3, gap / 2), y: chart.minY, width: width + max(6, gap), height: chart.height)
        if hitRect.contains(point) {
            hoveredIndex = index
            hoverPoint = point
        } else {
            hoveredIndex = nil
            hoverPoint = nil
        }
        needsDisplay = true
    }

    private func clearHoverIfNeeded() {
        if hoveredIndex != nil || hoverPoint != nil {
            hoveredIndex = nil
            hoverPoint = nil
            needsDisplay = true
        }
    }

    private func continuousHours() -> [HourUsage] {
        guard selectedWindow == .day else { return hours }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard let last = hours.last?.hour else { return hours }
        let start = calendar.date(byAdding: .hour, value: -23, to: last) ?? last
        let byHour = Dictionary(uniqueKeysWithValues: hours.map { ($0.hour, $0) })
        return (0..<24).map { offset in
            let date = calendar.date(byAdding: .hour, value: offset, to: start) ?? start
            return byHour[date] ?? HourUsage(hour: date, usage: Usage(), turns: 0)
        }
    }

    private func labelIndexesForDailyBars() -> Set<Int> {
        guard !days.isEmpty else { return [] }
        if selectedWindow == .week {
            return Set(days.indices)
        }
        let count = days.count
        let candidates = [0, count / 4, count / 2, count * 3 / 4, count - 1]
        return Set(candidates.filter { $0 >= 0 && $0 < count })
    }

    private func compactDayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    private func drawHoverTooltip() {
        guard let hoveredIndex, let hoverPoint else { return }
        let title: String
        let usage: Usage

        if selectedWindow == .day {
            let series = continuousHours()
            guard series.indices.contains(hoveredIndex) else { return }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "MM/dd HH:mm"
            title = formatter.string(from: series[hoveredIndex].hour)
            usage = series[hoveredIndex].usage
        } else {
            guard days.indices.contains(hoveredIndex) else { return }
            title = days[hoveredIndex].day
            usage = days[hoveredIndex].usage
        }

        var lines = [
            title,
            "\(t(.input))       \(compact(usage.input))",
            "\(t(.output))      \(compact(usage.output))",
            "\(t(.cached))      \(compact(usage.cachedInput))",
            "\(t(.fresh))       \(compact(usage.freshInput))"
        ]
        if let weeklyQuotaPercent = stableWeeklyQuotaShare(for: usage) ?? weeklyQuotaShare(for: usage) {
            lines.append("\(t(.weeklyQuotaShare))   \(String(format: "%.1f%%", weeklyQuotaPercent))")
        } else if let visibleWeekPercent = visibleWeekShare(for: usage) {
            lines.append("\(t(.visibleWeekShare)) \(String(format: "%.1f%%", visibleWeekPercent))")
        }
        if let costEstimator {
            if selectedWindow == .day {
                lines.append("\(t(.dayValue))  \(displayMoney(costEstimator.value(for: usage)))")
            } else {
                lines.append("\(t(.dayValue))  \(displayMoney(costEstimator.tokenValue(forDayKey: title, usage: usage)))")
            }
        }
        if let apiEquivalentUSD = apiEquivalentUSD(for: title, usage: usage) {
            lines.append("\(t(.apiEquivalent))  \(displayAPIMoney(apiEquivalentUSD))")
        }

        let width: CGFloat = 244
        let height = CGFloat(18 + lines.count * 16)
        var origin = CGPoint(x: hoverPoint.x + 12, y: hoverPoint.y - height - 8)
        if origin.x + width > bounds.maxX - 8 {
            origin.x = hoverPoint.x - width - 12
        }
        if origin.y < bounds.minY + 8 {
            origin.y = hoverPoint.y + 14
        }
        origin.x = max(bounds.minX + 8, min(origin.x, bounds.maxX - width - 8))
        origin.y = max(bounds.minY + 8, min(origin.y, bounds.maxY - height - 8))

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.025, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        for (index, line) in lines.enumerated() {
            let isTitle = index == 0
            let textRect = NSRect(x: rect.minX + 10, y: rect.minY + 8 + CGFloat(index) * 16, width: rect.width - 20, height: 15)
            (line as NSString).draw(
                in: textRect,
                withAttributes: [
                    .font: isTitle ? NSFont.systemFont(ofSize: 11, weight: .bold) : NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: isTitle ? NSColor.white.withAlphaComponent(0.9) : NSColor.white.withAlphaComponent(0.62)
                ]
            )
        }
    }

    private func weeklyQuotaShare(for usage: Usage) -> Double? {
        guard selectedWindow != .day,
              let weeklyQuotaUsedPercent,
              weeklyQuotaUsedPercent > 0 else {
            return nil
        }
        let referenceTotal = weeklyQuotaReferenceTotal ?? recentWeekTotal()
        guard usage.total > 0, referenceTotal > 0 else { return nil }
        let shareOfVisibleWeek = Double(usage.total) / Double(referenceTotal)
        return shareOfVisibleWeek * weeklyQuotaUsedPercent
    }

    private func stableWeeklyQuotaShare(for usage: Usage) -> Double? {
        guard selectedWindow != .day,
              usage.total > 0,
              let costEstimator else {
            return nil
        }
        return costEstimator.quotaPercent(for: usage)
    }

    private func visibleWeekShare(for usage: Usage) -> Double? {
        guard selectedWindow == .week else { return nil }
        let visibleTotal = days.reduce(Int64(0)) { $0 + $1.usage.total }
        guard usage.total > 0, visibleTotal > 0 else { return nil }
        return Double(usage.total) / Double(visibleTotal) * 100
    }

    private func apiEquivalentUSD(for title: String, usage: Usage) -> Double? {
        guard usage.total > 0 else { return nil }
        if selectedWindow == .day {
            guard let apiEstimate,
                  apiEstimate.hasPricedUsage,
                  apiEstimate.totalTokens > 0 else {
                return nil
            }
            return apiEstimate.usdValue * Double(usage.total) / Double(apiEstimate.totalTokens)
        }
        guard let day = days.first(where: { $0.day == title }) else { return nil }
        let estimate = APICostEstimator.estimate(day: day)
        return estimate.hasPricedUsage ? estimate.usdValue : nil
    }

    private func recentWeekTotal() -> Int64 {
        if selectedWindow == .week {
            return days.reduce(Int64(0)) { $0 + $1.usage.total }
        }
        return days.suffix(7).reduce(Int64(0)) { $0 + $1.usage.total }
    }

    private func drawLabel(_ label: String, rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (label as NSString).draw(
            in: rect,
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.42), .paragraphStyle: paragraph]
        )
    }
}

final class CodexStatusChipView: NSView {
    var snapshot: CodexServiceStatusSnapshot? { didSet { needsDisplay = true } }

    private let chipFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds

        let text = statusText
        let dotColor = statusColor
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 4, y: rect.midY - 3, width: 6, height: 6)).fill()
        drawText(
            text,
            rect: NSRect(x: rect.minX + 16, y: rect.minY + 4, width: rect.width - 18, height: rect.height - 8),
            font: chipFont,
            color: NSColor.white.withAlphaComponent(0.82)
        )
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private var statusText: String {
        let label = snapshot.map { localizedCodexStatus($0.overallStatus) } ?? t(.codexStatusUnavailable)
        return "Codex \(label)"
    }

    private var statusColor: NSColor {
        snapshot.map { codexStatusColor($0.overallStatus) } ?? NSColor.white.withAlphaComponent(0.42)
    }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let textWidth = (statusText as NSString).size(withAttributes: [
            .font: chipFont
        ]).width
        return min(maxWidth, ceil(textWidth) + 22)
    }
}

final class DashboardView: NSView {
    static let idealSize = NSSize(width: 430, height: 610)

    private var state = DashboardState()
    private let logoImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Codex Token Meter")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "")
    private let refreshLabel = NSTextField(labelWithString: "")
    private let costLabel = NSTextField(labelWithString: "")
    private let quotaSegment = NSSegmentedControl(labels: QuotaViewOption.allCases.map { $0.shortTitle }, trackingMode: .selectOne, target: nil, action: nil)
    private let segment = NSSegmentedControl(labels: WindowOption.allCases.map { $0.shortTitle }, trackingMode: .selectOne, target: nil, action: nil)
    private let primaryRing = RingView()
    private let weeklyRing = RingView()
    private let cacheRing = RingView()
    private let primaryBullet = QuotaBulletView()
    private let weeklyBullet = QuotaBulletView()
    private let cacheBullet = QuotaBulletView()
    private let dayChart = UsageChartView()
    private let serviceStatusView = CodexStatusChipView()
    private let sessionsLabel = NSTextField(labelWithString: "")
    private let buttonsStack = NSStackView()
    private var buttonsByKey: [L10nKey: NSButton] = [:]

    var onWindowChanged: ((WindowOption) -> Void)?
    var onQuotaChanged: ((QuotaViewOption) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenDetails: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenCodexStatus: (() -> Void)?
    var onQuit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.idealSize }

    func update(_ state: DashboardState) {
        self.state = state
        let report = state.report
        let totalReport = state.selectedQuota == .all ? (state.profileReport ?? report) : report
        applyLanguage()
        titleLabel.stringValue = "Codex Token Meter"
        let displayLimit = selectedLimit(from: state.liveLimits, quota: state.selectedQuota)
        subtitleLabel.stringValue = state.selectedQuota.fallbackTitle
        totalLabel.stringValue = compactDashboardTotal(totalReport.usage.total)
        detailLabel.stringValue = state.profileReport != nil && state.selectedQuota == .all
            ? "\(state.selectedWindow.title) · \(t(.profileAPISource))"
            : state.selectedWindow.title
        usageLabel.stringValue = "\(compactDashboardMetric(report.usage.input)) \(t(.inShort))  |  \(compactDashboardMetric(report.usage.output)) \(t(.outShort))"
        refreshLabel.stringValue = state.isLoading ? t(.refreshing) : "\(t(.updated)) \(relative(report.scannedAt))  |  \(t(.next)) \(relative(state.nextRefreshAt))"
        let apiEstimate = APICostEstimator.estimate(report: report)
        let externalAPI = ExternalAPICostStore.read()

        quotaSegment.selectedSegment = QuotaViewOption.allCases.firstIndex(of: state.selectedQuota) ?? 0
        segment.selectedSegment = WindowOption.allCases.firstIndex(of: state.selectedWindow) ?? 1

        let primary = displayLimit?.primary
        let weekly = displayLimit?.secondary
        let primaryComparison = remainingComparison(for: primary)
        let weeklyComparison = remainingComparison(for: weekly)
        let quotaStyle = QuotaDisplayStyle.current
        primaryRing.percent = primary?.remainingPercent ?? 0
        primaryRing.title = t(.fiveHourLeft)
        primaryRing.subtitle = primary.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.liveLimitUnavailable)
        primaryRing.color = colorForRemaining(percent: primaryRing.percent)
        primaryRing.resetTooltip = primary?.resetsAt.map { relative($0) }
        primaryRing.remainingComparison = primaryComparison
        primaryRing.isHidden = quotaStyle != .rings

        primaryBullet.actualRemainingPercent = primary?.remainingPercent ?? 0
        primaryBullet.title = t(.fiveHourLeft)
        primaryBullet.subtitle = primary.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.liveLimitUnavailable)
        primaryBullet.color = colorForRemaining(percent: primaryBullet.actualRemainingPercent)
        primaryBullet.resetTooltip = primary?.resetsAt.map { relative($0) }
        primaryBullet.remainingComparison = primaryComparison
        primaryBullet.isHidden = quotaStyle != .bullet

        weeklyRing.percent = weekly?.remainingPercent ?? 0
        weeklyRing.title = t(.weeklyLeft)
        weeklyRing.subtitle = weekly.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.usageWindow)
        weeklyRing.color = colorForRemaining(percent: weeklyRing.percent)
        weeklyRing.resetTooltip = weekly?.resetsAt.map { relative($0) }
        weeklyRing.remainingComparison = weeklyComparison
        weeklyRing.isHidden = quotaStyle != .rings

        weeklyBullet.actualRemainingPercent = weekly?.remainingPercent ?? 0
        weeklyBullet.title = t(.weeklyLeft)
        weeklyBullet.subtitle = weekly.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.usageWindow)
        weeklyBullet.color = colorForRemaining(percent: weeklyBullet.actualRemainingPercent)
        weeklyBullet.resetTooltip = weekly?.resetsAt.map { relative($0) }
        weeklyBullet.remainingComparison = weeklyComparison
        weeklyBullet.isHidden = quotaStyle != .bullet

        cacheRing.percent = report.usage.cachePercent
        cacheRing.title = t(.cacheHit)
        cacheRing.subtitle = "\(compact(report.usage.freshInput)) \(t(.fresh).lowercased())"
        cacheRing.color = NSColor.systemTeal
        cacheRing.resetTooltip = nil
        cacheRing.remainingComparison = nil
        cacheRing.isHidden = quotaStyle == .bullet

        cacheBullet.actualRemainingPercent = report.usage.cachePercent
        cacheBullet.title = t(.cacheHit)
        cacheBullet.subtitle = "\(compact(report.usage.freshInput)) \(t(.fresh).lowercased())"
        cacheBullet.color = NSColor.systemTeal
        cacheBullet.resetTooltip = nil
        cacheBullet.remainingComparison = nil
        cacheBullet.isHidden = quotaStyle != .bullet

        dayChart.selectedWindow = state.selectedWindow
        dayChart.days = report.byDay
        dayChart.hours = report.byHour
        dayChart.weeklyQuotaUsedPercent = state.selectedWindow == .day ? nil : weekly?.usedPercent
        dayChart.weeklyQuotaReferenceTotal = state.selectedWindow == .day ? nil : report.byDay.suffix(7).reduce(Int64(0)) { $0 + $1.usage.total }
        dayChart.costEstimator = state.selectedWindow == .day ? nil : CostEstimator(report: report, limit: displayLimit)
        dayChart.apiEstimate = apiEstimate
        serviceStatusView.snapshot = state.serviceStatus
        serviceStatusView.isHidden = !AppSettings.showCodexStatusEnabled
        sessionsLabel.stringValue = "\(t(.sessions)) \(report.sessions)   \(t(.turns)) \(report.turns)   \(t(.events)) \(report.events)"
        var costParts: [String] = []
        if apiEstimate.hasPricedUsage {
            let coverage = apiEstimate.coveragePercent < 99.5 ? " \(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : ""
            costParts.append("\(t(.apiEquivalent)) \(displayAPIMoney(apiEstimate.usdValue))\(coverage)")
        }
        if let externalAPI, externalAPI.hasData {
            costParts.append("\(t(.externalAPICost)) \(displayAPIMoney(externalAPI.usdValue))")
        }
        if !costParts.isEmpty {
            costLabel.stringValue = costParts.joined(separator: "  |  ")
        } else {
            costLabel.stringValue = ""
        }
        updateAccessibilityLabels(report: report, totalReport: totalReport)
        needsLayout = true
        needsDisplay = true
    }

    func applyLanguage() {
        for (index, option) in QuotaViewOption.allCases.enumerated() {
            quotaSegment.setLabel(option.shortTitle, forSegment: index)
        }
        for (index, option) in WindowOption.allCases.enumerated() {
            segment.setLabel(option.shortTitle, forSegment: index)
        }
        for key in [L10nKey.refresh, .details, .settings, .quit] {
            guard let button = buttonsByKey[key] else { continue }
            button.title = t(key)
            button.toolTip = t(key)
            button.image = symbolImage(for: key)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let card = bounds.insetBy(dx: 8, dy: 8)
        NSColor(calibratedWhite: 0.045, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: card, xRadius: 26, yRadius: 26).fill()
        NSColor.white.withAlphaComponent(0.09).setStroke()
        let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 26, yRadius: 26)
        border.lineWidth = 1
        border.stroke()
    }

    override func layout() {
        super.layout()
        let layoutBounds = NSRect(origin: .zero, size: NSSize(width: max(bounds.width, Self.idealSize.width), height: max(bounds.height, Self.idealSize.height)))
        let content = layoutBounds.insetBy(dx: 28, dy: 24)
        let totalWidth: CGFloat = 132
        let totalX = content.maxX - totalWidth
        let titleX = content.minX + 28
        logoImageView.frame = NSRect(x: content.minX, y: content.minY + 2, width: 22, height: 22)
        titleLabel.frame = NSRect(x: titleX, y: content.minY, width: max(132, totalX - titleX - 12), height: 28)
        subtitleLabel.frame = NSRect(x: titleX, y: content.minY + 30, width: max(132, totalX - titleX - 12), height: 18)
        totalLabel.frame = NSRect(x: totalX, y: content.minY, width: totalWidth, height: 36)
        detailLabel.frame = NSRect(x: content.maxX - 172, y: content.minY + 37, width: 162, height: 16)
        quotaSegment.frame = NSRect(x: content.minX, y: content.minY + 52, width: 216, height: 24)
        usageLabel.frame = NSRect(x: content.minX + 228, y: content.minY + 55, width: content.width - 228, height: 16)
        segment.frame = NSRect(x: content.minX, y: content.minY + 82, width: content.width, height: 30)

        let ringY = content.minY + 132
        let ringW = (content.width - 24) / 3
        if QuotaDisplayStyle.current == .bullet {
            let rowH: CGFloat = 40
            let rowGap: CGFloat = 8
            primaryRing.frame = .zero
            weeklyRing.frame = .zero
            cacheRing.frame = .zero
            primaryBullet.frame = NSRect(x: content.minX, y: ringY + 2, width: content.width, height: rowH)
            weeklyBullet.frame = NSRect(x: content.minX, y: ringY + 2 + rowH + rowGap, width: content.width, height: rowH)
            cacheBullet.frame = NSRect(x: content.minX, y: ringY + 2 + (rowH + rowGap) * 2, width: content.width, height: rowH)
        } else {
            primaryRing.frame = NSRect(x: content.minX, y: ringY, width: ringW, height: 136)
            weeklyRing.frame = NSRect(x: content.minX + ringW + 12, y: ringY, width: ringW, height: 136)
            primaryBullet.frame = .zero
            weeklyBullet.frame = .zero
            cacheBullet.frame = .zero
            cacheRing.frame = NSRect(x: content.minX + (ringW + 12) * 2, y: ringY, width: ringW, height: 136)
        }

        let statsY = ringY + 154
        buttonsStack.frame = NSRect(x: content.minX, y: content.maxY - 36, width: content.width, height: 28)
        let showsStatus = AppSettings.showCodexStatusEnabled
        let chipGap: CGFloat = 10
        let maxChipWidth = min(136, max(108, content.width * 0.36))
        let chipWidth = showsStatus ? serviceStatusView.preferredWidth(maxWidth: maxChipWidth) : 0
        let infoWidth = showsStatus ? max(120, content.width - chipWidth - chipGap) : content.width
        refreshLabel.frame = NSRect(x: content.minX, y: buttonsStack.frame.minY - 24, width: infoWidth, height: 18)
        costLabel.frame = NSRect(x: content.minX, y: refreshLabel.frame.minY - 20, width: infoWidth, height: 16)
        sessionsLabel.frame = NSRect(x: content.minX, y: costLabel.frame.minY - 22, width: infoWidth, height: 18)
        if showsStatus {
            let chipHeight: CGFloat = 24
            let chipX = content.maxX - chipWidth
            let chipY = sessionsLabel.frame.minY + max(0, (refreshLabel.frame.maxY - sessionsLabel.frame.minY - chipHeight) / 2)
            serviceStatusView.frame = NSRect(x: chipX, y: chipY, width: chipWidth, height: chipHeight)
        } else {
            serviceStatusView.frame = .zero
        }
        let chartBottom = sessionsLabel.frame.minY
        dayChart.frame = NSRect(x: content.minX, y: statsY, width: content.width, height: max(72, chartBottom - statsY - 12))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !serviceStatusView.isHidden,
           serviceStatusView.frame.insetBy(dx: -2, dy: -2).contains(point) {
            onOpenCodexStatus?()
            return
        }
        super.mouseDown(with: event)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        logoImageView.image = NSImage(named: "LogoHeader")
        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoImageView)

        [titleLabel, subtitleLabel, totalLabel, detailLabel, usageLabel, refreshLabel, sessionsLabel, costLabel].forEach {
            $0.isBezeled = false
            $0.drawsBackground = false
            $0.isEditable = false
            $0.isSelectable = false
            addSubview($0)
        }

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.usesSingleLineMode = true
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        subtitleLabel.usesSingleLineMode = true
        subtitleLabel.lineBreakMode = .byTruncatingTail
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        totalLabel.alignment = .right
        totalLabel.textColor = NSColor.systemGreen
        totalLabel.usesSingleLineMode = true
        totalLabel.lineBreakMode = .byTruncatingHead
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        detailLabel.alignment = .right
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        detailLabel.usesSingleLineMode = true
        detailLabel.lineBreakMode = .byTruncatingTail
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        usageLabel.alignment = .right
        usageLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        usageLabel.usesSingleLineMode = true
        usageLabel.lineBreakMode = .byTruncatingMiddle
        refreshLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        refreshLabel.textColor = NSColor.white.withAlphaComponent(0.50)
        refreshLabel.usesSingleLineMode = true
        refreshLabel.lineBreakMode = .byTruncatingMiddle
        sessionsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sessionsLabel.textColor = NSColor.white.withAlphaComponent(0.56)
        sessionsLabel.usesSingleLineMode = true
        sessionsLabel.lineBreakMode = .byTruncatingTail
        costLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        costLabel.textColor = NSColor.systemTeal.withAlphaComponent(0.88)
        costLabel.usesSingleLineMode = true
        costLabel.lineBreakMode = .byTruncatingTail

        quotaSegment.target = self
        quotaSegment.action = #selector(quotaSegmentChanged)
        quotaSegment.segmentStyle = .rounded
        addSubview(quotaSegment)

        segment.target = self
        segment.action = #selector(segmentChanged)
        segment.segmentStyle = .rounded
        segment.toolTip = t(.usageWindow)
        addSubview(segment)

        [primaryRing, weeklyRing, primaryBullet, weeklyBullet, cacheBullet, cacheRing, dayChart, serviceStatusView].forEach { addSubview($0) }
        serviceStatusView.toolTip = "Open OpenAI Status"

        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually
        addSubview(buttonsStack)
        addButton(.refresh, action: #selector(refreshTapped))
        addButton(.details, action: #selector(detailsTapped))
        addButton(.settings, action: #selector(settingsTapped))
        addButton(.quit, action: #selector(quitTapped))
        applyLanguage()
    }

    private func addButton(_ titleKey: L10nKey, action: Selector) {
        let button = NSButton(title: t(titleKey), target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.image = symbolImage(for: titleKey)
        button.imagePosition = .imageLeading
        button.toolTip = t(titleKey)
        buttonsByKey[titleKey] = button
        buttonsStack.addArrangedSubview(button)
    }

    private func symbolImage(for key: L10nKey) -> NSImage? {
        let name: String
        switch key {
        case .refresh:
            name = "arrow.clockwise"
        case .details:
            name = "chart.bar"
        case .settings:
            name = "gearshape"
        case .logs:
            name = "folder"
        case .quit:
            name = "power"
        default:
            return nil
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: t(key))
        image?.isTemplate = true
        return image
    }

    private func updateAccessibilityLabels(report: TokenReport, totalReport: TokenReport) {
        titleLabel.setAccessibilityLabel("Codex Token Meter")
        subtitleLabel.setAccessibilityLabel(subtitleLabel.stringValue)
        totalLabel.setAccessibilityLabel("\(t(.total)) \(compactDashboardTotal(totalReport.usage.total))")
        usageLabel.setAccessibilityLabel("\(t(.input)) \(compactDashboardMetric(report.usage.input)), \(t(.output)) \(compactDashboardMetric(report.usage.output))")
        sessionsLabel.setAccessibilityLabel(sessionsLabel.stringValue)
        refreshLabel.setAccessibilityLabel(refreshLabel.stringValue)
        quotaSegment.setAccessibilityLabel(t(.quotaViews))
        segment.setAccessibilityLabel(t(.usageWindow))
    }

    private func shortenedLimitName(_ value: String) -> String {
        if value.count <= 31 {
            return value
        }
        if let openParen = value.firstIndex(of: "(") {
            let prefix = String(value[..<openParen]).trimmingCharacters(in: .whitespaces)
            if prefix.count <= 28 {
                return prefix
            }
        }
        return String(value.prefix(28)) + "..."
    }

    private func selectedLimit(from limits: [LiveRateLimit], quota: QuotaViewOption) -> LiveRateLimit? {
        if let exact = limits.first(where: { $0.id == quota.liveLimitID }) {
            return exact
        }
        if quota == .spark {
            return limits.first { $0.id != QuotaViewOption.all.liveLimitID }
        }
        return nil
    }

    private func displayName(for limit: LiveRateLimit) -> String {
        limit.id == "codex" ? "Codex quota" : shortenedLimitName(limit.name)
    }

    @objc private func segmentChanged() {
        let index = segment.selectedSegment
        guard index >= 0, index < WindowOption.allCases.count else { return }
        onWindowChanged?(WindowOption.allCases[index])
    }

    @objc private func quotaSegmentChanged() {
        let index = quotaSegment.selectedSegment
        guard index >= 0, index < QuotaViewOption.allCases.count else { return }
        onQuotaChanged?(QuotaViewOption.allCases[index])
    }

    @objc private func refreshTapped() { onRefresh?() }
    @objc private func detailsTapped() { onOpenDetails?() }
    @objc private func settingsTapped() { onOpenSettings?() }
    @objc private func quitTapped() { onQuit?() }

    private func colorFor(percent: Double) -> NSColor {
        if percent >= 85 { return .systemRed }
        if percent >= 65 { return .systemOrange }
        return .systemGreen
    }

    private func colorForRemaining(percent: Double) -> NSColor {
        if percent <= 15 { return .systemRed }
        if percent <= 35 { return .systemOrange }
        return .systemGreen
    }

    private func remainingComparison(for window: RateWindow?) -> RingRemainingComparison? {
        guard let window,
              let comparison = paceComparison(for: window) else {
            return nil
        }
        return RingRemainingComparison(
            expectedRemainingPercent: max(0, min(100, 100 - comparison.progressPercent)),
            actualRemainingPercent: window.remainingPercent,
            status: comparison.status
        )
    }
}

final class DashboardViewController: NSViewController {
    let dashboardView = DashboardView(frame: NSRect(origin: .zero, size: DashboardView.idealSize))

    override func loadView() {
        dashboardView.frame = NSRect(origin: .zero, size: DashboardView.idealSize)
        view = dashboardView
        preferredContentSize = DashboardView.idealSize
    }
}

