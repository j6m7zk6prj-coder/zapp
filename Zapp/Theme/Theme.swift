import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0A0D17)
    static let surface = Color(hex: 0x141827)
    static let surfaceHigh = Color(hex: 0x1F2436)
    static let accent = Color(hex: 0x4F6BFF)
    static let textSecondary = Color.white.opacity(0.6)

    static let liveGradient = LinearGradient(colors: [Color(hex: 0x4569FF), Color(hex: 0x2A44D8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let moviesGradient = LinearGradient(colors: [Color(hex: 0x9B5CF6), Color(hex: 0x6227D9)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let seriesGradient = LinearGradient(colors: [Color(hex: 0xEC3B5E), Color(hex: 0xA3123A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let searchGradient = LinearGradient(colors: [Color(hex: 0x262C3F), Color(hex: 0x171B2A)], startPoint: .topLeading, endPoint: .bottomTrailing)

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
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
