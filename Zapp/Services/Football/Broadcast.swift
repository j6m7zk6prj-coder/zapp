import Foundation

/// Chaînes de la playlist pour une compétition : choix de l'utilisateur d'abord, puis diffuseurs habituels.
@MainActor
enum Broadcast {
    static func channels(for slug: String, library: Library, profiles: ProfileStore, limit: Int = 10) -> [MediaItem] {
        let pinned = profiles.pinnedChannels(slug).compactMap { library.item($0) }
        let matched = ChannelMatcher.find(in: library.all(.live), keywords: AppSettings.shared.broadcasterKeywords(slug), limit: limit)
        var seen = Set<String>()
        return (pinned + matched).filter { seen.insert($0.id).inserted }.prefix(limit).map { $0 }
    }
}
