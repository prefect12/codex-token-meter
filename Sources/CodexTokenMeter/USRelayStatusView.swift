import Cocoa

extension USRelaySnapshot {
    var color: NSColor {
        switch state {
        case .open: return .systemGreen
        case .closed: return .systemOrange
        case .night: return .systemRed
        case .unavailable: return .systemGray
        }
    }

    private var chinese: Bool {
        AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese
    }

    var label: String {
        switch state {
        case .open: return chinese ? "VPS · 纽约工作时间 · 可调用" : "VPS · NY working hours · calls allowed"
        case .closed: return chinese ? "VPS · 纽约非工作时间 · 仅提醒" : "VPS · NY outside working hours · reminder only"
        case .night: return chinese ? "VPS · 纽约深夜 · 仅提醒" : "VPS · NY nighttime · reminder only"
        case .unavailable: return chinese ? "纽约时段配置异常 · 请检查转接入口" : "NY schedule unavailable · check relay"
        }
    }

    var tooltip: String {
        let window = chinese ? "纽约周一至周五 09:00–18:00（自动夏令时）" : "New York Mon–Fri 09:00–18:00 (automatic DST)"
        let legend = chinese ? "绿：工作时间；橙：时段外；红：深夜；灰：配置异常。" : "Green: open; orange: closed; red: night; gray: unavailable."
        let boundary = chinese ? "颜色仅提醒，不阻止调用或结束会话；CC 登录状态请在转接入口检查。" : "Colors are reminders only; calls and sessions remain available. Check Claude Code authentication in the relay."
        let routing = chinese ? "Claude 调用与额度查询来自美国 VPS。仅同步用量数字，不同步对话正文或登录密钥。" : "Claude calls and quota checks originate on the US VPS. Only accounting is synchronized; no dialogue or credentials."
        return [label, clock, window, legend, boundary, routing].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

final class USRelayStatusView: NSView {
    var snapshot: USRelaySnapshot? { didSet { updateAccessibility(); needsDisplay = true } }
    override var isFlipped: Bool { true }

    private func updateAccessibility() {
        toolTip = snapshot?.tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(snapshot?.tooltip)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let snapshot else { return }
        snapshot.color.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        snapshot.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 9, y: 10, width: 7, height: 7)).fill()
        let clockAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62)]
        let clockWidth = (snapshot.clock as NSString).size(withAttributes: clockAttributes).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (snapshot.label as NSString).draw(in: NSRect(x: 23, y: 6, width: bounds.width - clockWidth - 38, height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: snapshot.color,
                .paragraphStyle: paragraph])
        (snapshot.clock as NSString).draw(at: NSPoint(x: bounds.width - clockWidth - 9, y: 8), withAttributes: clockAttributes)
    }
}
