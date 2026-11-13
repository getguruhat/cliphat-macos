import AppKit
import SwiftUI

/// The GuruHat palette shared with ServerHat: a grey page, white (or near-black) cards that
/// stand out from it, vivid accents, light or dark with the system appearance.
enum Theme {
    static let page = dynamic(rgb(0.953, 0.957, 0.969), rgb(0.078, 0.078, 0.086))
    static let card = dynamic(.white, rgb(0.118, 0.122, 0.133))
    static let accent = dynamic(rgb(0.263, 0.384, 1.0), rgb(0.322, 0.435, 1.0))
    static let green = dynamic(rgb(0.086, 0.678, 0.369), rgb(0.263, 0.812, 0.494))
    static let red = dynamic(rgb(0.882, 0.227, 0.227), rgb(0.937, 0.333, 0.333))
    static let orange = dynamic(rgb(0.961, 0.502, 0.098), rgb(1.0, 0.616, 0.263))
    static let text = dynamic(rgb(0.102, 0.110, 0.137), rgb(0.961, 0.965, 0.973))
    static let secondary = dynamic(rgb(0.420, 0.443, 0.494), rgb(0.616, 0.635, 0.678))
    static let stroke = dynamic(NSColor.black.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0.09))
    static let control = dynamic(rgb(0.937, 0.941, 0.953), rgb(0.180, 0.184, 0.200))

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// A small tinted capsule, for secondary actions.
struct TintButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.2 : 0.12)))
            .contentShape(Capsule())
    }
}

/// A round icon button on a soft grey fill.
struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    var fill: Color = Theme.control
    var foreground: Color = Theme.secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(Circle())
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }
}
