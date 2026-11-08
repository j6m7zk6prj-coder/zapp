import Foundation
import Observation

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let queue: [Playable]
    let index: Int
}

/// Ouvre le lecteur plein écran depuis n'importe quel écran.
@MainActor
@Observable
final class PlayerPresenter {
    var request: PlaybackRequest?

    /// Pour une chaîne, `context` devient la file de zapping.
    func play(_ item: MediaItem, context: [MediaItem]) {
        guard let playable = item.playable else { return }
        guard item.kind == .live else {
            request = PlaybackRequest(queue: [playable], index: 0)
            return
        }
        let queue = context.filter { $0.kind == .live }.compactMap(\.playable)
        if let index = queue.firstIndex(where: { $0.id == playable.id }) {
            request = PlaybackRequest(queue: queue, index: index)
        } else {
            request = PlaybackRequest(queue: [playable], index: 0)
        }
    }

    func play(queue: [Playable], index: Int) {
        guard queue.indices.contains(index) else { return }
        request = PlaybackRequest(queue: queue, index: index)
    }
}
