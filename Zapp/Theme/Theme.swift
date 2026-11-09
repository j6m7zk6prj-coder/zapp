import SwiftUI
import UIKit

/// Couleurs de l'app, dérivées des réglages d'apparence (mises à jour en direct).
@MainActor
enum Theme {
    private static var settings: AppSettings { AppSettings.shared }

    static var accent: Color { Color(hex: settings.accentHex) }
    /// Couleur du texte posé sur la couleur d'accent.
    static var onAccent: Color { isLight(settings.accentHex) ? .black : .white }
    static var background: Color { Color(hex: settings.background.base) }
    static var surface: Color { Color(hex: settings.background.surface) }
    static var surfaceHigh: Color { Color(hex: settings.background.surfaceHigh) }
    static let textSecondary = Color.white.opacity(0.62)

    /// Fond des écrans : légère lueur en haut, façon Apple TV.
    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [Color(hex: settings.background.glow), background, background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let liveGradient = LinearGradient(colors: [Color(hex: 0x4569FF), Color(hex: 0x2A44D8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let moviesGradient = LinearGradient(colors: [Color(hex: 0x9B5CF6), Color(hex: 0x6227D9)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let seriesGradient = LinearGradient(colors: [Color(hex: 0xEC3B5E), Color(hex: 0xA3123A)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static let palettes: [(UInt32, UInt32)] = [
        (0x2A9DB5, 0x1E3A8A),
        (0xC0344F, 0x7A1F3D),
        (0xB8333A, 0x7C2D12),
        (0x9333EA, 0x581C87),
        (0x2563EB, 0x1E3A8A),
        (0xC026D3, 0x831843),
        (0x22A447, 0x166534),
        (0x4338CA, 0x312E81),
        (0x84CC16, 0x3F6212),
        (0xD97706, 0x78350F),
        (0x14B8A6, 0x115E59),
    ]

    /// Dégradé stable dérivé d'un nom, utilisé quand il n'y a pas d'image.
    static func gradient(for seed: String) -> LinearGradient {
        let palette = palettes[Int(seed.stableHash % UInt64(palettes.count))]
        return LinearGradient(
            colors: [Color(hex: palette.0), Color(hex: palette.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Couleur dominante stable dérivée d'un nom (teinte des cartes de catégories).
    static func gradientColor(for seed: String) -> Color {
        Color(hex: palettes[Int(seed.stableHash % UInt64(palettes.count))].0)
    }

    static func isLight(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF)
        let g = Double((hex >> 8) & 0xFF)
        let b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.68
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Valeur RGB 0xRRGGBB (pour enregistrer une couleur choisie au ColorPicker).
    var hexValue: UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32(max(0, min(255, (value * 255).rounded())))
        }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }
}
