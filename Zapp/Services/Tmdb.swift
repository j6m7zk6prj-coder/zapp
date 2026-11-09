import Foundation

enum TmdbKind: String, Codable, Sendable {
    case movie, tv
}

struct TmdbCast: Hashable, Codable, Sendable, Identifiable {
    let name: String
    let character: String?
    let photo: URL?
    var id: String { name + (character ?? "") }
}

/// Fiche enrichie d'un film ou d'une série (The Movie Database).
struct TmdbInfo: Hashable, Codable, Sendable {
    var id: Int
    var kind: TmdbKind
    var title: String
    var originalTitle: String?
    var year: Int?
    var rating: Double?
    var votes: Int?
    var overview: String?
    var tagline: String?
    var poster: URL?
    var backdrop: URL?
    var logo: URL?
    var genres: [String] = []
    var runtimeMinutes: Int?
    var seasons: Int?
    var director: String?
    var cast: [TmdbCast] = []
    var trailerKey: String?

    var trailerURL: URL? { trailerKey.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") } }

    var runtime: String {
        guard let minutes = runtimeMinutes, minutes > 0 else { return "" }
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}

/// Titre en tendance cette semaine.
struct TmdbTrend: Hashable, Sendable {
    let id: Int
    let kind: TmdbKind
    let title: String
    let originalTitle: String?
    let year: Int?
    let backdrop: URL?
    let poster: URL?
    let rating: Double?
    let overview: String?
}

/// Nettoie les noms des playlists (« FR - Avatar (2009) [4K] » → « Avatar », 2009).
enum TitleCleaner {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Les motifs sont fixes : une erreur ici est un bug de programmation.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let prefix = regex(#"^\s*((\[[^\]]*\]|\|[^|]*\||\b[A-Z0-9]{2,4}\s*(?:\s[-–]\s|[:|•])\s*|[A-Z]{2}\s*\|\s*)\s*)+"#)
    private static let yearInBrackets = regex(#"[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]"#)
    private static let trailingYear = regex(#"[\s\-–]((?:19|20)\d{2})\s*$"#)
    private static let brackets = regex(#"\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}"#)
    private static let episode = regex(#"\bS\d{1,2}\s*E\d{1,3}\b.*$"#, [.caseInsensitive])
    private static let tags = regex(#"\b(4K|UHD|FHD|HD|SD|HDR|HDR10|1080p|720p|2160p|480p|MULTI|VOSTFR|VOST|VFF|VFQ|VFI|VF|VO|TRUEFRENCH|FRENCH|SUBFRENCH|x264|x265|h264|h265|HEVC|WEB-?DL|WEBRIP|BLURAY|BDRIP|DVDRIP|AC3|DTS|ATMOS|10bit)\b"#, [.caseInsensitive])
    private static let spaces = regex(#"\s{2,}"#)

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func clean(_ name: String) -> (title: String, year: Int?) {
        var text = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ").trimmed
        text = replace(prefix, in: text, with: "")
        var year: Int?
        if let match = yearInBrackets.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            year = Int(text[range])
        }
        text = replace(brackets, in: text, with: " ")
        text = replace(episode, in: text, with: " ")
        text = replace(tags, in: text, with: " ")
        text = replace(spaces, in: text, with: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -|:•–"))
        if year == nil,
           let match = trailingYear.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.range.location > 0,
           let yearRange = Range(match.range(at: 1), in: text),
           let whole = Range(match.range, in: text) {
            // On garde « 1917 » ou « 2012 » quand le titre n'est qu'une année.
            year = Int(text[yearRange])
            text = String(text[..<whole.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " -–"))
        }
        return (text.isEmpty ? name.trimmed : text, year)
    }

    /// Clé de comparaison (minuscules, sans accents ni ponctuation, sans « the »).
    static func key(_ title: String) -> String {
        let folded = title.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        var result = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, result.last != " " {
                result.append(" ")
            }
        }
        result = result.trimmed
        return result.hasPrefix("the ") ? String(result.dropFirst(4)) : result
    }
}

enum TmdbError: LocalizedError {
    case badKey
    case unavailable(Int)

    var errorDescription: String? {
        switch self {
        case .badKey: return "Clé TMDB refusée : vérifie-la dans les réglages."
        case .unavailable(let code): return "TMDB indisponible (\(code))."
        }
    }
}

/// Client TMDB (clé gratuite fournie par l'utilisateur) avec cache disque titre → fiche.
actor TmdbClient {
    private let key: String
    private var cache: [String: CacheEntry]
    private var pending: [String: Task<TmdbInfo?, Never>] = [:]
    private var saveTask: Task<Void, Never>?

    struct CacheEntry: Codable {
        var info: TmdbInfo?
        var at: Date
    }

    private static var cacheURL: URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("tmdb-cache.json")
    }

    init(key: String) {
        self.key = key.trimmed
        if let data = try? Data(contentsOf: Self.cacheURL),
           let stored = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            cache = stored
        } else {
            cache = [:]
        }
    }

    var hasKey: Bool { !key.isEmpty }
    private var isBearer: Bool { key.hasPrefix("eyJ") }

    func validate() async -> Bool {
        (try? await get("/configuration")) != nil
    }

    /// Fiche correspondant à un élément de playlist (nil si introuvable).
    func find(name: String, kind: MediaKind) async -> TmdbInfo? {
        guard hasKey, kind != .live else { return nil }
        let cacheKey = "\(kind == .series ? "tv" : "movie"):\(TitleCleaner.key(name))"
        if let entry = cache[cacheKey] {
            let maxAge: TimeInterval = entry.info == nil ? 3 * 86_400 : 30 * 86_400
            if Date().timeIntervalSince(entry.at) < maxAge { return entry.info }
        }
        if let task = pending[cacheKey] { return await task.value }
        let task = Task { await self.lookup(name: name, kind: kind) }
        pending[cacheKey] = task
        let info = await task.value
        pending[cacheKey] = nil
        cache[cacheKey] = CacheEntry(info: info, at: Date())
        scheduleSave()
        return info
    }

    private func lookup(name: String, kind: MediaKind) async -> TmdbInfo? {
        let (title, year) = TitleCleaner.clean(name)
        let tmdbKind: TmdbKind = kind == .series ? .tv : .movie
        do {
            var id = try await search(title, year: year, kind: tmdbKind)
            if id == nil, year != nil { id = try await search(title, year: nil, kind: tmdbKind) }
            guard let id else { return nil }
            return try await details(id: id, kind: tmdbKind)
        } catch {
            return nil
        }
    }

    private func search(_ title: String, year: Int?, kind: TmdbKind) async throws -> Int? {
        var query = "query=\(Self.escape(title))&language=fr-FR&include_adult=false"
        if let year { query += kind == .movie ? "&year=\(year)" : "&first_air_date_year=\(year)" }
        let root = try await get("/search/\(kind == .movie ? "movie" : "tv")?\(query)")
        return Self.parseSearch(root, title: title)
    }

    func details(id: Int, kind: TmdbKind) async throws -> TmdbInfo {
        let path = kind == .movie ? "movie" : "tv"
        let root = try await get("/\(path)/\(id)?language=fr-FR&append_to_response=credits,videos,images&include_image_language=fr,en,null&include_video_language=fr,en")
        return Self.parseDetails(root, kind: kind)
    }

    func trending(pages: Int = 3) async throws -> [TmdbTrend] {
        guard hasKey else { return [] }
        var list: [TmdbTrend] = []
        for page in 1...pages {
            list += Self.parseTrending(try await get("/trending/all/week?language=fr-FR&page=\(page)"))
        }
        return list
    }

    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            let keep = cache.sorted { $0.value.at > $1.value.at }.prefix(4000)
            let snapshot = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.cacheURL, options: .atomic) }
        }
    }

    private func get(_ pathAndQuery: String) async throws -> JSONNode {
        var url = "https://api.themoviedb.org/3" + pathAndQuery
        if !isBearer { url += (url.contains("?") ? "&" : "?") + "api_key=" + Self.escape(key) }
        guard let endpoint = URL(string: url) else { throw TmdbError.unavailable(0) }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isBearer { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw TmdbError.badKey }
        guard (200..<300).contains(code) else { throw TmdbError.unavailable(code) }
        return try JSONNode(data: data)
    }

    private static func escape(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    // MARK: Analyse (statique pour les tests)

    static func image(_ path: String?, _ size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    /// Meilleur résultat : titre identique en priorité, sinon le premier.
    static func parseSearch(_ root: JSONNode, title: String) -> Int? {
        let wanted = TitleCleaner.key(title)
        var first: Int?
        for result in root["results"].array {
            guard let id = result["id"].int else { continue }
            if first == nil { first = id }
            let names = ["title", "name", "original_title", "original_name"].compactMap { result[$0].string }
            if names.contains(where: { TitleCleaner.key($0) == wanted }) { return id }
        }
        return first
    }

    static func parseDetails(_ root: JSONNode, kind: TmdbKind) -> TmdbInfo {
        let title = root[kind == .movie ? "title" : "name"].string ?? ""
        let original = root[kind == .movie ? "original_title" : "original_name"].string
        let date = root[kind == .movie ? "release_date" : "first_air_date"].string
        let runtime = kind == .movie ? root["runtime"].int : root["episode_run_time"][0].int

        let crew = root["credits"]["crew"].array
        var director = crew.first(where: { $0["job"].string == "Director" })?["name"].string
        if director == nil {
            let creators = root["created_by"].array.compactMap { $0["name"].string }
            if !creators.isEmpty { director = creators.joined(separator: ", ") }
        }

        let videos = root["videos"]["results"].array.filter {
            $0["site"].string == "YouTube" && ["Trailer", "Teaser"].contains($0["type"].string ?? "")
        }
        let trailer = videos.sorted { a, b in
            let la = a["iso_639_1"].string == "fr" ? 0 : 1, lb = b["iso_639_1"].string == "fr" ? 0 : 1
            if la != lb { return la < lb }
            let ta = a["type"].string == "Trailer" ? 0 : 1, tb = b["type"].string == "Trailer" ? 0 : 1
            if ta != tb { return ta < tb }
            return a["official"].bool && !b["official"].bool
        }.first?["key"].string

        func languageRank(_ value: JSONNode) -> Int {
            switch value["iso_639_1"].string {
            case "fr": return 0
            case "en": return 1
            default: return 2
            }
        }
        let logo = root["images"]["logos"].array
            .sorted { languageRank($0) < languageRank($1) }
            .compactMap { $0["file_path"].string }
            .first { !$0.lowercased().hasSuffix(".svg") }

        let rating = root["vote_average"].double
        return TmdbInfo(
            id: root["id"].int ?? 0,
            kind: kind,
            title: title,
            originalTitle: original != title ? original : nil,
            year: date.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil },
            rating: rating.flatMap { $0 > 0 ? ($0 * 10).rounded() / 10 : nil },
            votes: root["vote_count"].int,
            overview: root["overview"].string.flatMap { $0.isEmpty ? nil : $0 },
            tagline: root["tagline"].string.flatMap { $0.isEmpty ? nil : $0 },
            poster: image(root["poster_path"].string, "w500"),
            backdrop: image(root["backdrop_path"].string, "w1280"),
            logo: image(logo, "w500"),
            genres: root["genres"].array.compactMap { $0["name"].string },
            runtimeMinutes: runtime.flatMap { $0 > 0 ? $0 : nil },
            seasons: kind == .tv ? root["number_of_seasons"].int : nil,
            director: director,
            cast: root["credits"]["cast"].array.prefix(15).compactMap { person in
                guard let name = person["name"].string, !name.isEmpty else { return nil }
                return TmdbCast(name: name, character: person["character"].string, photo: image(person["profile_path"].string, "w185"))
            },
            trailerKey: trailer
        )
    }

    static func parseTrending(_ root: JSONNode) -> [TmdbTrend] {
        root["results"].array.compactMap { result in
            guard let type = result["media_type"].string, type == "movie" || type == "tv" else { return nil }
            let kind: TmdbKind = type == "movie" ? .movie : .tv
            let date = result[kind == .movie ? "release_date" : "first_air_date"].string
            let rating = result["vote_average"].double
            return TmdbTrend(
                id: result["id"].int ?? 0,
                kind: kind,
                title: result[kind == .movie ? "title" : "name"].string ?? "",
                originalTitle: result[kind == .movie ? "original_title" : "original_name"].string,
                year: date.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil },
                backdrop: image(result["backdrop_path"].string, "w1280"),
                poster: image(result["poster_path"].string, "w500"),
                rating: rating.flatMap { $0 > 0 ? ($0 * 10).rounded() / 10 : nil },
                overview: result["overview"].string
            )
        }
    }
}
