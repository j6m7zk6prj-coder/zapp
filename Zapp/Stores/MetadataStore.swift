import Foundation
import Observation

/// Fiches TMDB et tendances, partagées par tous les écrans.
@MainActor
@Observable
final class MetadataStore {
    private(set) var infos: [String: TmdbInfo] = [:]
    private(set) var trending: [(item: MediaItem, trend: TmdbTrend)] = []
    @ObservationIgnored private var requested = Set<String>()
    @ObservationIgnored private var client: TmdbClient?
    @ObservationIgnored private var clientKey = ""
    @ObservationIgnored private var trendingSignature = ""
    @ObservationIgnored private var trendingLoadedAt = Date.distantPast

    var isEnabled: Bool { !AppSettings.shared.tmdbKey.trimmed.isEmpty }

    private func currentClient() -> TmdbClient? {
        let key = AppSettings.shared.tmdbKey.trimmed
        guard !key.isEmpty else { return nil }
        if key != clientKey || client == nil {
            client = TmdbClient(key: key)
            clientKey = key
            requested.removeAll()
            infos.removeAll()
            trending = []
            trendingSignature = ""
        }
        return client
    }

    func info(for item: MediaItem) -> TmdbInfo? { infos[item.id] }

    /// Charge la fiche d'un film ou d'une série (une seule fois par élément).
    func load(_ item: MediaItem) async {
        guard item.kind != .live, let client = currentClient(), requested.insert(item.id).inserted else { return }
        if let info = await client.find(name: item.name, kind: item.kind) {
            infos[item.id] = info
        }
    }

    /// Films et séries en tendance cette semaine qui sont dans la playlist.
    func loadTrending(library: Library) async {
        guard let client = currentClient() else {
            trending = []
            return
        }
        let movies = library.all(.movie)
        let series = library.all(.series)
        let signature = "\(clientKey.prefix(6))-\(movies.count)-\(series.count)"
        guard signature != trendingSignature || Date().timeIntervalSince(trendingLoadedAt) > 6 * 3600 else { return }
        trendingSignature = signature
        guard let trends = try? await client.trending() else { return }
        let matches = await Task.detached(priority: .utility) { () -> [(MediaItem, TmdbTrend)] in
            var index: [String: [MediaItem]] = [:]
            for item in movies + series {
                let key = TitleCleaner.key(TitleCleaner.clean(item.name).title)
                guard key.count >= 2 else { continue }
                index[key, default: []].append(item)
            }
            var result: [(MediaItem, TmdbTrend)] = []
            var used = Set<String>()
            for trend in trends {
                let wanted: MediaKind = trend.kind == .movie ? .movie : .series
                let keys = [trend.title, trend.originalTitle].compactMap { $0 }.map(TitleCleaner.key)
                if let match = keys.flatMap({ index[$0] ?? [] }).first(where: { $0.kind == wanted }),
                   used.insert(match.id).inserted {
                    result.append((match, trend))
                }
            }
            return result
        }.value
        trending = matches.map { (item: $0.0, trend: $0.1) }
        trendingLoadedAt = Date()
    }

    func validate(key: String) async -> Bool {
        await TmdbClient(key: key).validate()
    }

    func clearCache() async {
        await currentClient()?.clearCache()
        requested.removeAll()
        infos.removeAll()
        trendingSignature = ""
    }
}
