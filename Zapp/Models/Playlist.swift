import Foundation

enum PlaylistSource: Codable, Hashable, Sendable {
    /// Playlist M3U téléchargée depuis une URL.
    case m3uURL(URL)
    /// Fichier M3U importé, copié dans Documents/Playlists.
    case m3uFile(String)
    /// Compte Xtream Codes. Le mot de passe est rangé dans le trousseau.
    case xtream(server: URL, username: String)

    var label: String {
        switch self {
        case .m3uURL: return "URL M3U"
        case .m3uFile: return "Fichier M3U"
        case .xtream: return "Xtream Codes"
        }
    }
}

struct Playlist: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var source: PlaylistSource
    var createdAt: Date

    init(id: UUID = UUID(), name: String, source: PlaylistSource, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.source = source
        self.createdAt = createdAt
    }

    /// Identifiants Xtream complets (mot de passe lu dans le trousseau).
    var xtreamCredentials: XtreamCredentials? {
        guard case let .xtream(server, username) = source,
              let password = Keychain.get(id.uuidString) else { return nil }
        return XtreamCredentials(server: server, username: username, password: password)
    }
}
