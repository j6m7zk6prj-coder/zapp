import Foundation

/// Type de contenu d'une playlist IPTV.
enum MediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case live, movie, series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live TV"
        case .movie: return "Films"
        case .series: return "Séries"
        }
    }

    var unit: String {
        switch self {
        case .live: return "chaînes"
        case .movie: return "films"
        case .series: return "séries"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "tv"
        case .movie: return "film"
        case .series: return "rectangle.stack"
        }
    }
}

/// Une chaîne, un film ou une série issue d'une playlist.
struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var group: String
    var kind: MediaKind
    var streamURL: URL?
    var logoURL: URL?
    var rating: Double?
    var addedAt: Date?
    /// Identifiant Xtream d'une série (pour charger ses épisodes).
    var seriesID: String?
    /// Identifiant EPG (tvg-id) d'une chaîne.
    var epgID: String?

    init(
        id: String,
        name: String,
        group: String,
        kind: MediaKind,
        streamURL: URL? = nil,
        logoURL: URL? = nil,
        rating: Double? = nil,
        addedAt: Date? = nil,
        seriesID: String? = nil,
        epgID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.kind = kind
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.rating = rating
        self.addedAt = addedAt
        self.seriesID = seriesID
        self.epgID = epgID
    }

    /// Nom sans préfixe de pays du type « FR | ».
    var displayName: String {
        if let range = name.range(of: "|", options: .backwards) {
            let trimmed = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return name
    }

    /// Initiales utilisées quand il n'y a pas de logo.
    var initials: String { displayName.initials }

    /// Une série Xtream ouvre une fiche avec ses épisodes ; le reste se lit directement.
    var opensDetail: Bool { kind == .series && seriesID != nil }

    var playable: Playable? {
        guard let streamURL else { return nil }
        return Playable(
            id: id,
            title: name,
            subtitle: group,
            url: streamURL,
            artworkURL: logoURL,
            isLive: kind == .live
        )
    }
}

/// Ce que le lecteur sait lire.
struct Playable: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let url: URL
    let artworkURL: URL?
    let isLive: Bool
}

struct Episode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let season: Int
    let number: Int
    let url: URL
    let plot: String?
    let imageURL: URL?
    let duration: String?

    func playable(seriesName: String) -> Playable {
        Playable(
            id: "episode-\(id)",
            title: title,
            subtitle: "\(seriesName) · S\(season) E\(number)",
            url: url,
            artworkURL: imageURL,
            isLive: false
        )
    }
}

struct SeriesDetail: Sendable {
    var plot: String?
    var genre: String?
    var episodes: [Episode]

    var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
}

extension String {
    /// Deux premières initiales, utilisées quand il n'y a pas de logo.
    var initials: String {
        let words = split(separator: " ")
            .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        let letters = String(words.prefix(2).compactMap { $0.first }).uppercased()
        return letters.isEmpty ? "TV" : letters
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Hash FNV-1a stable d'une exécution à l'autre (contrairement à `hashValue`).
    var stableHash: UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
