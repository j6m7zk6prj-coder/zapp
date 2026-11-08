import Foundation

enum XtreamError: LocalizedError {
    case authFailed
    case http(Int)
    case badResponse
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .authFailed: return "Identifiants Xtream refusés par le serveur."
        case .http(let code): return "Le serveur a répondu avec l'erreur \(code)."
        case .badResponse: return "Réponse du serveur illisible."
        case .missingCredentials: return "Identifiants introuvables. Supprime puis rajoute la playlist."
        }
    }
}

struct XtreamCredentials: Hashable, Sendable {
    var server: URL
    var username: String
    var password: String

    /// Accepte « hote:port », « http://hote:port/ » ou une URL complète vers player_api.php.
    static func normalizedServer(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            value = "http://" + value
        }
        if let range = value.range(of: "/player_api.php") {
            value = String(value[..<range.lowerBound])
        }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), url.host != nil else { return nil }
        return url
    }
}

/// Client minimal de l'API Xtream Codes (player_api.php).
struct XtreamClient: Sendable {
    let credentials: XtreamCredentials

    func authenticate() async throws {
        let object = try await request(action: nil)
        guard let root = object as? [String: Any],
              let info = root["user_info"] as? [String: Any],
              JSONValue.int(info["auth"]) == 1 else {
            throw XtreamError.authFailed
        }
    }

    func fetchLibrary() async throws -> [MediaItem] {
        async let liveGroups = categories("get_live_categories")
        async let movieGroups = categories("get_vod_categories")
        async let seriesGroups = categories("get_series_categories")
        async let liveStreams = list("get_live_streams")
        async let movieStreams = list("get_vod_streams")
        async let seriesList = list("get_series")

        let (lg, mg, sg) = try await (liveGroups, movieGroups, seriesGroups)
        let (live, movies, series) = try await (liveStreams, movieStreams, seriesList)

        var items: [MediaItem] = []
        items.reserveCapacity(live.count + movies.count + series.count)

        for entry in live {
            guard let id = JSONValue.string(entry["stream_id"]) else { continue }
            items.append(MediaItem(
                id: "live-\(id)",
                name: JSONValue.string(entry["name"]) ?? "Chaîne \(id)",
                group: group(entry, in: lg),
                kind: .live,
                streamURL: streamURL(kind: "live", id: id, ext: "m3u8"),
                logoURL: JSONValue.url(entry["stream_icon"]),
                addedAt: JSONValue.date(entry["added"]),
                epgID: JSONValue.string(entry["epg_channel_id"])
            ))
        }

        for entry in movies {
            guard let id = JSONValue.string(entry["stream_id"]) else { continue }
            let ext = JSONValue.string(entry["container_extension"]) ?? "mp4"
            items.append(MediaItem(
                id: "movie-\(id)",
                name: JSONValue.string(entry["name"]) ?? "Film \(id)",
                group: group(entry, in: mg),
                kind: .movie,
                streamURL: streamURL(kind: "movie", id: id, ext: ext),
                logoURL: JSONValue.url(entry["stream_icon"]),
                rating: JSONValue.double(entry["rating"]),
                addedAt: JSONValue.date(entry["added"])
            ))
        }

        for entry in series {
            guard let id = JSONValue.string(entry["series_id"]) else { continue }
            items.append(MediaItem(
                id: "series-\(id)",
                name: JSONValue.string(entry["name"]) ?? "Série \(id)",
                group: group(entry, in: sg),
                kind: .series,
                logoURL: JSONValue.url(entry["cover"]),
                rating: JSONValue.double(entry["rating"]),
                addedAt: JSONValue.date(entry["last_modified"]),
                seriesID: id
            ))
        }
        return items
    }

    func seriesDetail(id: String) async throws -> SeriesDetail {
        let object = try await request(
            action: "get_series_info",
            extra: [URLQueryItem(name: "series_id", value: id)]
        )
        guard let root = object as? [String: Any] else { throw XtreamError.badResponse }
        let info = root["info"] as? [String: Any]

        // Selon les serveurs : { "1": [...], "2": [...] } ou [[...], [...]]
        var groups: [[Any]] = []
        if let bySeason = root["episodes"] as? [String: Any] {
            groups = bySeason.values.compactMap { $0 as? [Any] }
        } else if let array = root["episodes"] as? [Any] {
            groups = array.compactMap { $0 as? [Any] }
        }

        var episodes: [Episode] = []
        for group in groups {
            for case let entry as [String: Any] in group {
                guard let episodeID = JSONValue.string(entry["id"]) else { continue }
                let ext = JSONValue.string(entry["container_extension"]) ?? "mp4"
                let details = entry["info"] as? [String: Any]
                episodes.append(Episode(
                    id: episodeID,
                    title: JSONValue.string(entry["title"]) ?? "Épisode",
                    season: JSONValue.int(entry["season"]) ?? 1,
                    number: JSONValue.int(entry["episode_num"]) ?? 0,
                    url: streamURL(kind: "series", id: episodeID, ext: ext),
                    plot: JSONValue.string(details?["plot"]),
                    imageURL: JSONValue.url(details?["movie_image"]),
                    duration: JSONValue.string(details?["duration"])
                ))
            }
        }
        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }

        return SeriesDetail(
            plot: JSONValue.string(info?["plot"]),
            genre: JSONValue.string(info?["genre"]),
            episodes: episodes
        )
    }

    // MARK: - Privé

    private func group(_ entry: [String: Any], in map: [String: String]) -> String {
        guard let categoryID = JSONValue.string(entry["category_id"]) else { return "Sans catégorie" }
        return map[categoryID] ?? "Sans catégorie"
    }

    private func streamURL(kind: String, id: String, ext: String) -> URL {
        credentials.server
            .appendingPathComponent(kind)
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(id).\(ext)")
    }

    private func categories(_ action: String) async throws -> [String: String] {
        let object = try await request(action: action)
        guard let array = object as? [[String: Any]] else { return [:] }
        var map: [String: String] = [:]
        for entry in array {
            if let id = JSONValue.string(entry["category_id"]),
               let name = JSONValue.string(entry["category_name"]) {
                map[id] = name
            }
        }
        return map
    }

    private func list(_ action: String) async throws -> [[String: Any]] {
        let object = try await request(action: action)
        return object as? [[String: Any]] ?? []
    }

    private func request(action: String?, extra: [URLQueryItem] = []) async throws -> Any {
        let base = credentials.server.appendingPathComponent("player_api.php")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw XtreamError.badResponse
        }
        var query = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
        ]
        if let action { query.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems = query + extra
        guard let url = components.url else { throw XtreamError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("Zapp/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw XtreamError.http(http.statusCode)
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw XtreamError.badResponse
        }
    }
}

/// Les serveurs Xtream mélangent nombres et chaînes : on lit tout de façon tolérante.
enum JSONValue {
    static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string.isEmpty ? nil : string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            return Int(string) ?? Double(string).map { Int($0) }
        }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    static func url(_ value: Any?) -> URL? {
        guard let string = string(value) else { return nil }
        return URL(string: string)
    }

    static func date(_ value: Any?) -> Date? {
        guard let seconds = double(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
