import Foundation

/// Télécharge et décode une playlist, hors du thread principal.
enum PlaylistLoader {
    static func fetch(_ playlist: Playlist) async throws -> [MediaItem] {
        switch playlist.source {
        case .m3uURL(let url):
            var request = URLRequest(url: url)
            request.timeoutInterval = 90
            request.setValue("Zapp/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw XtreamError.http(http.statusCode)
            }
            return M3UParser.parse(String(decoding: data, as: UTF8.self))

        case .m3uFile(let fileName):
            let data = try Data(contentsOf: AppPaths.playlistFile(fileName))
            return M3UParser.parse(String(decoding: data, as: UTF8.self))

        case .xtream:
            guard let credentials = playlist.xtreamCredentials else {
                throw XtreamError.missingCredentials
            }
            return try await XtreamClient(credentials: credentials).fetchLibrary()
        }
    }
}

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var playlistsFolder: URL {
        documents.appendingPathComponent("Playlists", isDirectory: true)
    }

    static func playlistFile(_ name: String) -> URL {
        playlistsFolder.appendingPathComponent(name)
    }

    static var logosFolder: URL {
        documents.appendingPathComponent("Logos", isDirectory: true)
    }

    static func logoFile(_ name: String) -> URL {
        logosFolder.appendingPathComponent(name)
    }

    static func ensurePlaylistsFolder() throws {
        try FileManager.default.createDirectory(at: playlistsFolder, withIntermediateDirectories: true)
    }
}

/// Cache disque du contenu d'une playlist, pour un démarrage instantané.
enum LibraryCache {
    /// Au-delà, on recharge la playlist en arrière-plan.
    static let maxAge: TimeInterval = 12 * 60 * 60

    static func url(for id: UUID) -> URL {
        AppPaths.caches.appendingPathComponent("library-\(id.uuidString).json")
    }

    static func load(_ id: UUID) async -> [MediaItem]? {
        let fileURL = url(for: id)
        return await Task.detached(priority: .userInitiated) { () -> [MediaItem]? in
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? JSONDecoder().decode([MediaItem].self, from: data)
        }.value
    }

    static func save(_ items: [MediaItem], for id: UUID) {
        let fileURL = url(for: id)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(items) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func isStale(_ id: UUID) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: id).path)
        guard let modified = attributes?[.modificationDate] as? Date else { return true }
        return Date().timeIntervalSince(modified) > maxAge
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
