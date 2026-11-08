import Foundation
import Observation

/// Liste des playlists enregistrées et playlist active.
@MainActor
@Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private(set) var activeID: UUID?

    private enum Keys {
        static let playlists = "playlists.v1"
        static let active = "playlists.active"
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.playlists),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        if let raw = defaults.string(forKey: Keys.active) {
            activeID = UUID(uuidString: raw)
        }
    }

    var active: Playlist? {
        playlists.first { $0.id == activeID } ?? playlists.first
    }

    func add(_ playlist: Playlist, password: String?) {
        if let password {
            Keychain.set(password, for: playlist.id.uuidString)
        }
        playlists.append(playlist)
        activeID = playlist.id
        save()
    }

    func setActive(_ id: UUID) {
        activeID = id
        save()
    }

    func remove(_ playlist: Playlist) {
        Keychain.delete(playlist.id.uuidString)
        LibraryCache.remove(playlist.id)
        if case .m3uFile(let fileName) = playlist.source {
            try? FileManager.default.removeItem(at: AppPaths.playlistFile(fileName))
        }
        playlists.removeAll { $0.id == playlist.id }
        if activeID == playlist.id { activeID = playlists.first?.id }
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: Keys.playlists)
        }
        defaults.set(activeID?.uuidString, forKey: Keys.active)
    }
}
