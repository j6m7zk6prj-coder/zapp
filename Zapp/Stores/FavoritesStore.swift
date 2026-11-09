import Foundation
import Observation

/// Favoris du profil actif.
@MainActor
@Observable
final class FavoritesStore {
    @ObservationIgnored private let profiles: ProfileStore

    init(profiles: ProfileStore) {
        self.profiles = profiles
    }

    var ids: Set<String> { profiles.current.favorites }

    func contains(_ item: MediaItem) -> Bool { ids.contains(item.id) }

    func toggle(_ item: MediaItem) {
        profiles.toggleFavorite(item.id)
    }
}
