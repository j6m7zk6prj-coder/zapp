import SwiftUI
import Observation

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case night, oled, graphite, ocean, plum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return "Nuit"
        case .oled: return "Noir"
        case .graphite: return "Graphite"
        case .ocean: return "Océan"
        case .plum: return "Prune"
        }
    }

    var base: UInt32 {
        switch self {
        case .night: return 0x0A0D17
        case .oled: return 0x000000
        case .graphite: return 0x141518
        case .ocean: return 0x05161F
        case .plum: return 0x130A1C
        }
    }

    var surface: UInt32 {
        switch self {
        case .night: return 0x141827
        case .oled: return 0x111113
        case .graphite: return 0x202126
        case .ocean: return 0x0C2430
        case .plum: return 0x21132D
        }
    }

    var surfaceHigh: UInt32 {
        switch self {
        case .night: return 0x1F2436
        case .oled: return 0x1C1C1F
        case .graphite: return 0x2C2E35
        case .ocean: return 0x143443
        case .plum: return 0x2F1C40
        }
    }

    /// Lueur en haut de l'écran.
    var glow: UInt32 {
        switch self {
        case .night: return 0x182050
        case .oled: return 0x14102A
        case .graphite: return 0x26282F
        case .ocean: return 0x0B3A4E
        case .plum: return 0x2E1248
        }
    }
}

enum PosterSize: String, CaseIterable, Identifiable {
    case compact, regular, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Petites"
        case .regular: return "Normales"
        case .large: return "Grandes"
        }
    }

    var width: CGFloat {
        switch self {
        case .compact: return 96
        case .regular: return 118
        case .large: return 146
        }
    }
}

enum LiveLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: String { rawValue }
    var title: String { self == .grid ? "Mosaïque" : "Liste" }
}

struct AccentPreset: Identifiable {
    let name: String
    let hex: UInt32
    var id: UInt32 { hex }
}

/// Réglages d'apparence et de lecture, enregistrés sur l'appareil.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let accentPresets: [AccentPreset] = [
        AccentPreset(name: "iTv", hex: 0x8B7CFF),
        AccentPreset(name: "Bleu", hex: 0x4F6BFF),
        AccentPreset(name: "Indigo", hex: 0x7462FF),
        AccentPreset(name: "Violet", hex: 0xA65CF6),
        AccentPreset(name: "Rose", hex: 0xF0458A),
        AccentPreset(name: "Rouge", hex: 0xF2414B),
        AccentPreset(name: "Orange", hex: 0xFF8A1F),
        AccentPreset(name: "Jaune", hex: 0xF5C518),
        AccentPreset(name: "Vert", hex: 0x2FCB6B),
        AccentPreset(name: "Turquoise", hex: 0x19C3C3),
        AccentPreset(name: "Blanc", hex: 0xEDEDF2),
    ]

    static let defaultAccent: UInt32 = 0x8B7CFF

    private(set) var accentHex: UInt32
    private(set) var background: BackgroundStyle
    private(set) var posterSize: PosterSize
    private(set) var liveLayout: LiveLayout
    private(set) var engine: PlaybackEngine

    // Fiches films et séries (clé TMDB fournie par l'utilisateur)
    var tmdbKey: String { didSet { UserDefaults.standard.set(tmdbKey, forKey: Keys.tmdbKey) } }
    // Lecture
    var autoPlayNext: Bool { didSet { UserDefaults.standard.set(autoPlayNext, forKey: Keys.autoPlayNext) } }
    var resumePlayback: Bool { didSet { UserDefaults.standard.set(resumePlayback, forKey: Keys.resumePlayback) } }
    // Foot
    var hideScores: Bool { didSet { UserDefaults.standard.set(hideScores, forKey: Keys.hideScores) } }
    var footRefreshSeconds: Int { didSet { UserDefaults.standard.set(footRefreshSeconds, forKey: Keys.footRefresh) } }
    /// Diffuseurs / mots-clés de chaînes modifiés par l'utilisateur (slug → liste).
    var broadcasters: [String: String] { didSet { UserDefaults.standard.set(broadcasters, forKey: Keys.broadcasters) } }

    private enum Keys {
        static let accent = "settings.accent"
        static let background = "settings.background"
        static let posterSize = "settings.posterSize"
        static let liveLayout = "settings.liveLayout"
        static let engine = "settings.engine"
        static let tmdbKey = "settings.tmdbKey"
        static let autoPlayNext = "settings.autoPlayNext"
        static let resumePlayback = "settings.resumePlayback"
        static let hideScores = "settings.hideScores"
        static let footRefresh = "settings.footRefresh"
        static let broadcasters = "settings.broadcasters"
        static let themeVersion = "settings.themeVersion"
    }

    private init() {
        let defaults = UserDefaults.standard
        let migrating = defaults.integer(forKey: Keys.themeVersion) < 2
        if let stored = defaults.object(forKey: Keys.accent) as? NSNumber, !(migrating && stored.uint32Value == 0x4F6BFF) {
            accentHex = stored.uint32Value
        } else {
            accentHex = Self.defaultAccent
        }
        // iTv : fond noir profond par défaut (l'ancien « Nuit » bleuté devient « Noir »).
        let storedBackground = BackgroundStyle(rawValue: defaults.string(forKey: Keys.background) ?? "")
        background = migrating && (storedBackground == nil || storedBackground == .night) ? .oled : (storedBackground ?? .oled)
        defaults.set(2, forKey: Keys.themeVersion)
        tmdbKey = defaults.string(forKey: Keys.tmdbKey) ?? ""
        autoPlayNext = defaults.object(forKey: Keys.autoPlayNext) as? Bool ?? true
        resumePlayback = defaults.object(forKey: Keys.resumePlayback) as? Bool ?? true
        hideScores = defaults.bool(forKey: Keys.hideScores)
        footRefreshSeconds = defaults.object(forKey: Keys.footRefresh) as? Int ?? 60
        broadcasters = defaults.dictionary(forKey: Keys.broadcasters) as? [String: String] ?? [:]
        posterSize = PosterSize(rawValue: defaults.string(forKey: Keys.posterSize) ?? "") ?? .regular
        liveLayout = LiveLayout(rawValue: defaults.string(forKey: Keys.liveLayout) ?? "") ?? .grid
        engine = PlaybackEngine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .auto
    }

    func setAccent(_ hex: UInt32) {
        accentHex = hex
        UserDefaults.standard.set(NSNumber(value: hex), forKey: Keys.accent)
    }

    func setBackground(_ style: BackgroundStyle) {
        background = style
        UserDefaults.standard.set(style.rawValue, forKey: Keys.background)
    }

    func setPosterSize(_ size: PosterSize) {
        posterSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Keys.posterSize)
    }

    func setLiveLayout(_ layout: LiveLayout) {
        liveLayout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: Keys.liveLayout)
    }

    func setEngine(_ engine: PlaybackEngine) {
        self.engine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: Keys.engine)
    }

    func broadcasterKeywords(_ slug: String) -> String {
        if let custom = broadcasters[slug], !custom.trimmed.isEmpty { return custom }
        return LeagueCatalog.find(slug)?.channelKeywords ?? ""
    }

    func broadcasterLabel(_ slug: String) -> String {
        if let custom = broadcasters[slug], !custom.trimmed.isEmpty { return custom }
        return LeagueCatalog.find(slug)?.broadcaster ?? ""
    }

    func resetAppearance() {
        setAccent(Self.defaultAccent)
        setBackground(.oled)
        setPosterSize(.regular)
        setLiveLayout(.grid)
    }
}
