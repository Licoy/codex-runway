import AppKit
import SwiftUI

/// Semantic capsule-tag tints shared by subscription badges, expiry chips, and status pills.
enum RunwayTagTone: Equatable {
    case neutral
    case gray
    case blue
    case purple
    case orange
    case yellow
    case green
    case red
    case teal
    case indigo
    case cyan
}

/// Resolved light/dark-safe colors for a capsule tag.
struct RunwayTagColors: Equatable {
    var foreground: Color
    var background: Color
    var stroke: Color

    static func resolve(_ tone: RunwayTagTone, colorScheme: ColorScheme) -> RunwayTagColors {
        let light = colorScheme == .light
        switch tone {
        case .neutral:
            // Soft chip: dark text on gray fill (not tint-on-tint).
            return RunwayTagColors(
                foreground: Color(nsColor: light ? .labelColor : .secondaryLabelColor),
                background: light
                    ? Color.black.opacity(0.08)
                    : Color.white.opacity(0.14),
                stroke: Color(nsColor: .separatorColor).opacity(light ? 0.95 : 0.65))
        case .yellow:
            // Pure systemYellow text washes out; orange stays readable for warnings.
            let tint = Color(nsColor: light ? .systemOrange : .systemYellow)
            return tinted(tint, light: light)
        default:
            return tinted(baseTint(tone), light: light)
        }
    }

    private static func tinted(_ tint: Color, light: Bool) -> RunwayTagColors {
        if light {
            // Light: solid-ish fill + white label — avoids same-hue text/background muddiness.
            return RunwayTagColors(
                foreground: .white,
                background: tint.opacity(0.92),
                stroke: tint.opacity(0.55))
        }
        return RunwayTagColors(
            foreground: tint,
            background: tint.opacity(0.24),
            stroke: tint.opacity(0.45))
    }

    private static func baseTint(_ tone: RunwayTagTone) -> Color {
        switch tone {
        case .neutral:
            return Color(nsColor: .secondaryLabelColor)
        case .gray:
            return Color(nsColor: .systemGray)
        case .blue:
            return Color(nsColor: .systemBlue)
        case .purple:
            return Color(nsColor: .systemPurple)
        case .orange:
            return Color(nsColor: .systemOrange)
        case .yellow:
            return Color(nsColor: .systemYellow)
        case .green:
            return Color(nsColor: .systemGreen)
        case .red:
            return Color(nsColor: .systemRed)
        case .teal:
            return Color(nsColor: .systemTeal)
        case .indigo:
            return Color(nsColor: .systemIndigo)
        case .cyan:
            return Color(nsColor: .systemCyan)
        }
    }
}

/// Compact capsule label used for plan tiers, subscription expiry, and credit status.
struct RunwayTag<Content: View>: View {
    var tone: RunwayTagTone
    var font: Font = .caption2.weight(.semibold)
    var horizontalPadding: CGFloat = 7
    var verticalPadding: CGFloat = 3
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = RunwayTagColors.resolve(tone, colorScheme: colorScheme)
        content()
            .font(font)
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(colors.background, in: Capsule())
            .overlay(Capsule().strokeBorder(colors.stroke, lineWidth: colorScheme == .light ? 1.0 : 0.8))
            .lineLimit(1)
    }
}

extension RunwayTag where Content == Text {
    init(
        _ title: String,
        tone: RunwayTagTone,
        font: Font = .caption2.weight(.semibold),
        horizontalPadding: CGFloat = 7,
        verticalPadding: CGFloat = 3)
    {
        self.tone = tone
        self.font = font
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = { Text(title) }
    }
}
