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
            // Avoid secondaryLabel as fill source — near-invisible in light mode.
            return RunwayTagColors(
                foreground: Color(nsColor: .secondaryLabelColor),
                background: light
                    ? Color.black.opacity(0.06)
                    : Color.white.opacity(0.12),
                stroke: Color(nsColor: .separatorColor).opacity(light ? 0.85 : 0.55))
        case .yellow:
            // Pure systemYellow text washes out on light backgrounds; use orange for labels.
            let tint = Color(nsColor: light ? .systemOrange : .systemYellow)
            return tinted(tint, light: light)
        default:
            return tinted(baseTint(tone), light: light)
        }
    }

    private static func tinted(_ tint: Color, light: Bool) -> RunwayTagColors {
        RunwayTagColors(
            foreground: tint,
            // Slightly stronger fill in dark mode so chips don't disappear on dark panels.
            background: tint.opacity(light ? 0.12 : 0.22),
            stroke: tint.opacity(light ? 0.34 : 0.42))
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
            .overlay(Capsule().strokeBorder(colors.stroke, lineWidth: 0.7))
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
