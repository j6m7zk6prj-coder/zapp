import Foundation
import Observation

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let queue: [Playable]
    let index: Int
}

/// Fiche d'une équipe.
struct TeamRoute: Hashable {
    let team: TeamRef
    let league: String
}

/// Classement complet d'une compétition.
struct StandingsRoute: Hashable {
    let slug: String
}

/// Écrans « Tout voir » ouverts depuis l'accueil.
enum BrowseRoute: Hashable {
    case kind(MediaKind)
    case favorites
    case customLinks
    case group(MediaKind, String)

    var title: String {
        switch self {
        case .kind(let kind): return kind.title
        case .favorites: return "Mes favoris"
        case .customLinks: return CustomLink.defaultGroup
        case .group(_, let name): return name
        }
    }
}

/// Présente le lecteur et l'éditeur depuis n'importe quel écran.
@MainActor
@Observable
final class Router {
    var playback: PlaybackRequest?
    var editing: MediaItem?
    var sheet: AppSheet?

    /// Pour une chaîne, `context` devient la file de zapping.
    func play(_ item: MediaItem, context: [MediaItem]) {
        guard let playable = item.playable else { return }
        guard item.kind == .live else {
            playback = PlaybackRequest(queue: [playable], index: 0)
            return
        }
        let queue = context.filter { $0.kind == .live }.compactMap(\.playable)
        if let index = queue.firstIndex(where: { $0.id == playable.id }) {
            playback = PlaybackRequest(queue: queue, index: index)
        } else {
            playback = PlaybackRequest(queue: [playable], index: 0)
        }
    }

    func play(queue: [Playable], index: Int) {
        guard queue.indices.contains(index) else { return }
        playback = PlaybackRequest(queue: queue, index: index)
    }

    func edit(_ item: MediaItem) {
        editing = item
    }
}
