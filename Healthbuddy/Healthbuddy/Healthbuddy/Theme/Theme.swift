import SwiftUI
import UIKit

/// Design tokens for the "Mellow" look, taken from the Figma Community file
/// "Mental wellness mobile app (Free UI/UX design)".
///
/// The template ships as flattened bitmaps with no Figma variables, so the hex values below were
/// sampled directly from its screens. Pastel brand fills stay the same in light and dark mode;
/// only the ground, surface, and text colors adapt.
enum Theme {
    // MARK: - Brand fills (fixed)
    /// Deep navy from the cover art and onboarding progress bar.
    static let navy       = Color(hex: 0x000C56)
    /// Floating tab bar, active dots, primary actions.
    static let indigo     = Color(hex: 0x3B41EF)
    static let yellow     = Color(hex: 0xF5D149)
    static let teal       = Color(hex: 0x7EC6C3)
    static let coral      = Color(hex: 0xE57573)
    static let periwinkle = Color(hex: 0x8595EC)
    static let pink       = Color(hex: 0xFBA0FF)
    /// Inactive dots and other quiet accents.
    static let lavender   = Color(hex: 0xBDC4E0)
    static let sky        = Color(hex: 0xA4DCF5)
    /// Soft lime card behind the mood row.
    static let lime       = Color(hex: 0xF5FCDA)
    /// Mood-circle green.
    static let sage       = Color(hex: 0xCBDCAE)
    /// Text on any pastel fill. Fixed dark so it stays readable in dark mode too.
    static let onPastel   = Color(hex: 0x1B1B1B)

    // MARK: - Adaptive
    static let background    = Color(light: 0xFFFFFF, dark: 0x0B0D1E)
    static let surface       = Color(light: 0xFFFFFF, dark: 0x1A1D33)
    static let ink           = Color(light: 0x1B1B1B, dark: 0xF2F2F7)
    static let inkSecondary  = Color(light: 0x5C5C66, dark: 0xA9ABBD)
    static let separator     = Color(light: 0xE6E8F2, dark: 0x2A2E4A)
    /// Text links such as "See all".
    static let link          = Color(light: 0x2104E1, dark: 0x9EA2FF)

    // MARK: - Shape
    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 24
    static let screenPadding: CGFloat = 20

    // MARK: - Type
    // The template uses Poppins. SF Rounded is the closest system face and keeps Dynamic Type.
    static let greeting = Font.system(.title, design: .rounded, weight: .medium)
    static let lead     = Font.system(.title3, design: .rounded)
    static let section  = Font.system(.subheadline, design: .rounded)
    static let label    = Font.system(.subheadline, design: .rounded, weight: .semibold)
    static let caption  = Font.system(.caption, design: .rounded)
}

// MARK: - Color helpers
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
