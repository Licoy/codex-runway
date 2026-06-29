import AppKit
import CodexRunwayCore

final class StatusBarContentView: NSView {
    private var style = StatusBarDisplayStyle.countdown
    private var metersDetailStyle = StatusBarMetersDetailStyle.remainingPercent
    private var batteryScope = StatusBarBatteryScope.fiveHour
    private var batteryDetailStyle = StatusBarBatteryDetailStyle.countdown
    private var language = ResolvedLanguage.english
    private var text = ""
    private var meters: [QuotaMeter] = []

    var preferredWidth: CGFloat {
        switch style {
        case .countdown:
            return min(180, max(42, textWidth(text, font: countdownFont) + 14))
        case .battery:
            return batteryScope == .both
                ? min(146, max(88, batteryTextWidth + 38))
                : min(150, max(70, batteryTextWidth + 28))
        case .meters:
            return min(156, max(96, meterTextWidth + 52))
        case .rings:
            return 52
        }
    }

    func update(
        style: StatusBarDisplayStyle,
        metersDetailStyle: StatusBarMetersDetailStyle,
        batteryScope: StatusBarBatteryScope,
        batteryDetailStyle: StatusBarBatteryDetailStyle,
        language: ResolvedLanguage,
        text: String,
        meters: [QuotaMeter])
    {
        self.style = style
        self.metersDetailStyle = metersDetailStyle
        self.batteryScope = batteryScope
        self.batteryDetailStyle = batteryDetailStyle
        self.language = language
        self.text = text
        self.meters = meters
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 22)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch style {
        case .countdown:
            drawCountdown()
        case .battery:
            drawBattery()
        case .meters:
            drawMeters()
        case .rings:
            drawRings()
        }
    }

    private func drawCountdown() {
        drawCentered(text, font: countdownFont, rect: bounds, color: .labelColor)
    }

    private func drawBattery() {
        if batteryScope == .both {
            drawSmallBattery(primaryMeter, rect: NSRect(x: 4, y: bounds.midY + 2, width: bounds.width - 8, height: 8))
            drawSmallBattery(weeklyMeter, rect: NSRect(x: 4, y: bounds.midY - 10, width: bounds.width - 8, height: 8))
            return
        }
        let rect = bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()

        let meter = selectedBatteryMeter
        let percent = CGFloat(meter?.remainingPercent ?? 0) / 100
        let fillRect = rect.insetBy(dx: 2, dy: 2)
        let filled = NSRect(x: fillRect.minX, y: fillRect.minY, width: fillRect.width * percent, height: fillRect.height)
        NSBezierPath(roundedRect: filled, xRadius: 4, yRadius: 4).fill(with: meterColor(meter), alpha: 0.85)
        drawCentered(batteryText(for: meter), font: batteryFont, rect: rect, color: .labelColor)
    }

    private func drawSmallBattery(_ meter: QuotaMeter?, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()

        let fillRect = rect.insetBy(dx: 1.5, dy: 1.5)
        let width = fillRect.width * CGFloat(meter?.remainingPercent ?? 0) / 100
        let filled = NSRect(x: fillRect.minX, y: fillRect.minY, width: width, height: fillRect.height)
        NSBezierPath(roundedRect: filled, xRadius: 2.5, yRadius: 2.5).fill(with: meterColor(meter), alpha: 0.85)
        drawCentered(batteryText(for: meter), font: smallBatteryFont, rect: rect, color: .labelColor)
    }

    private func drawMeters() {
        let top = meters.first
        let bottom = meters.dropFirst().first
        drawMeter(top, y: bounds.midY + 4)
        drawMeter(bottom, y: bounds.midY - 7)
        drawMeterText(top: top, bottom: bottom)
    }

    private func drawMeter(_ meter: QuotaMeter?, y: CGFloat) {
        let rect = NSRect(x: 4, y: y, width: min(40, bounds.width * 0.36), height: 5)
        let background = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        background.fill()

        let percent = CGFloat(meter?.remainingPercent ?? 0) / 100
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * percent, height: rect.height)
        NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill(with: meterColor(meter), alpha: 0.95)
    }

    private func drawMeterText(top: QuotaMeter?, bottom: QuotaMeter?) {
        let x = min(48, bounds.width * 0.42)
        let width = max(20, bounds.width - x - 4)
        drawLine(meterCaption(for: top), rect: NSRect(x: x, y: bounds.midY - 1, width: width, height: 10))
        drawLine(meterCaption(for: bottom), rect: NSRect(x: x, y: bounds.midY - 11, width: width, height: 10))
    }

    private func drawRings() {
        drawRing(primaryMeter, rect: NSRect(x: 4, y: 1, width: 20, height: 20))
        drawRing(weeklyMeter, rect: NSRect(x: 28, y: 1, width: 20, height: 20))
    }

    private func drawRing(_ meter: QuotaMeter?, rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - 2
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.5
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        track.stroke()

        if let meter {
            let progress = CGFloat(meter.remainingPercent) / 100
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
            arc.lineWidth = 2.5
            meterColor(meter).setStroke()
            arc.stroke()
        }
        drawCentered(ringText(for: meter), font: ringFont, rect: rect, color: .labelColor)
    }

    private var primaryMeter: QuotaMeter? {
        meters.first
    }

    private var weeklyMeter: QuotaMeter? {
        meters.dropFirst().first
    }

    private var selectedBatteryMeter: QuotaMeter? {
        batteryScope == .weekly ? weeklyMeter : primaryMeter
    }

    private var countdownFont: NSFont {
        .systemFont(ofSize: 14, weight: .semibold)
    }

    private var batteryFont: NSFont {
        .systemFont(ofSize: 10.5, weight: .semibold)
    }

    private var smallBatteryFont: NSFont {
        .systemFont(ofSize: 6.5, weight: .semibold)
    }

    private var meterTextFont: NSFont {
        .systemFont(ofSize: 8.5, weight: .semibold)
    }

    private var ringFont: NSFont {
        .systemFont(ofSize: 6, weight: .bold)
    }

    private var batteryTextWidth: CGFloat {
        batteryScope == .both
            ? [primaryMeter, weeklyMeter].map { textWidth(batteryText(for: $0), font: smallBatteryFont) }.max() ?? 0
            : textWidth(batteryText(for: selectedBatteryMeter), font: batteryFont)
    }

    private var meterTextWidth: CGFloat {
        [meters.first, meters.dropFirst().first]
            .map { textWidth(meterCaption(for: $0), font: meterTextFont) }
            .max() ?? 0
    }

    private func meterCaption(for meter: QuotaMeter?) -> String {
        guard let meter else { return "--" }
        return "\(meter.title) \(meterDetail(for: meter))"
    }

    private func meterDetail(for meter: QuotaMeter) -> String {
        switch metersDetailStyle {
        case .remainingPercent:
            return "\(meter.remainingPercent)%"
        case .resetTime:
            return meter.resetsAt.map { ResetLabelFormatter.shortLabel(for: $0, language: language) } ?? "--"
        }
    }

    private func batteryText(for meter: QuotaMeter?) -> String {
        guard let meter else { return "--" }
        switch batteryDetailStyle {
        case .countdown:
            return meter.resetsAt.map { DurationFormatter.localized($0.timeIntervalSince(Date()), language: language, includeSeconds: false) } ?? "--"
        case .remainingPercent:
            return "\(meter.remainingPercent)%"
        }
    }

    private func ringText(for meter: QuotaMeter?) -> String {
        meter.map { "\($0.remainingPercent)" } ?? "--"
    }

    private func meterColor(_ meter: QuotaMeter?) -> NSColor {
        switch meter?.health {
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        case nil:
            return .tertiaryLabelColor
        }
    }

    private func drawCentered(_ text: String, font: NSFont, rect: NSRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let size = text.size(withAttributes: attributes)
        let y = rect.midY - size.height / 2
        text.draw(in: NSRect(x: rect.minX, y: y, width: rect.width, height: size.height), withAttributes: attributes)
    }

    private func drawLine(_ text: String, rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: meterTextFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        text.size(withAttributes: [.font: font]).width
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor, alpha: CGFloat) {
        color.withAlphaComponent(alpha).setFill()
        fill()
    }
}
