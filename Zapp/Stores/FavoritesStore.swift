import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private(set) var ids: Set<String>
    private static let key = "favorites.v1"

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ item: MediaItem) -> Bool { ids.contains(item.id) }

    func toggle(_ item: MediaItem) {
        if ids.contains(item.id) {
            ids.remove(item.id)
        } else {
            ids.insert(item.id)
        }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}
