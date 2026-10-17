import SwiftUI
import AppKit
import CoreText

// The same look as BrewDock, Don't Worry and Word Slip: pastel colour blocks,
// bold condensed uppercase titles and small monospaced labels.

enum AppColors {
    // Pastels. Text on them is always `ink`, in light and dark mode.
    static let peach = Color(hex: 0xF6C3B4)
    static let butter = Color(hex: 0xF6E2A4)
    static let periwinkle = Color(hex: 0xC3C7F6)
    static let mint = Color(hex: 0xC2E6D6)
    static let lilac = Color(hex: 0xDCD2F0)
    static let coral = Color(hex: 0xEE9C86)
    static let ink = Color(hex: 0x232428)

    static let pastels = [peach, butter, periwinkle, mint, lilac]

    static let ground = Color(light: 0xE9EFEA, dark: 0x16171A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2B30)
    static let surfaceHover = Color(light: 0xF6F8F6, dark: 0x33353B)
    static let text = Color(light: 0x232428, dark: 0xF2F1EE)
    static let secondaryText = Color(light: 0x5E636C, dark: 0xA9ADB5)
    static let hairline = Color(light: 0xD5DCD7, dark: 0x2E3035)

    /// Round buttons and the selected tab: ink on light, cream on dark
    static let solid = Color(light: 0x232428, dark: 0xF2F1EE)
    static let onSolid = Color(light: 0xFFFFFF, dark: 0x232428)

    static let toggle = Color(hex: 0x4FAE87)
    static let destructive = Color(light: 0xB93A26, dark: 0xF19A85)

    /// A stable pastel for a name, so each one keeps its colour
    static func pastel(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return pastels[sum % pastels.count]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A colour that switches with light and dark mode
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Fonts

/// The bundled fonts: Barlow Condensed for titles and Geist Mono for labels.
enum AppFonts {
    static let display = "BarlowCondensed-Bold"

    enum MonoWeight {
        case regular, medium, semibold

        var fontName: String {
            switch self {
            case .regular: return "GeistMono-Regular"
            case .medium: return "GeistMono-Medium"
            case .semibold: return "GeistMono-SemiBold"
            }
        }
    }

    // Registered on first use, so previews get the fonts too
    static let registered: Void = {
        for name in ["BarlowCondensed-Bold", "GeistMono-Regular", "GeistMono-Medium", "GeistMono-SemiBold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

extension Font {
    /// Bold condensed titles. Use with `.textCase(.uppercase)`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        _ = AppFonts.registered
        return .custom(AppFonts.display, size: size, relativeTo: style)
    }

    /// Small monospaced labels and supporting text
    static func mono(_ size: CGFloat, weight: AppFonts.MonoWeight = .regular, relativeTo style: Font.TextStyle = .footnote) -> Font {
        _ = AppFonts.registered
        return .custom(weight.fontName, size: size, relativeTo: style)
    }
}

