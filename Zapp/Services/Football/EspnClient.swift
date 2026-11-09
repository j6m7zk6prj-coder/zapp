import Foundation

/// Accès tolérant à un JSON décodé avec JSONSerialization.
struct JSONNode: @unchecked Sendable {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    init(data: Data) throws {
        raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    subscript(key: String) -> JSONNode {
        JSONNode((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> JSONNode {
        guard let array = raw as? [Any], array.indices.contains(index) else { return JSONNode(nil) }
        return JSONNode(array[index])
    }

    var array: [JSONNode] { (raw as? [Any])?.map(JSONNode.init) ?? [] }
    var isObject: Bool { raw is [String: Any] }
    var isNull: Bool { raw == nil || raw is NSNull }

    var string: String? {
        if let text = raw as? String { return text }
        return nil
    }

    /// Chaîne ou nombre converti en texte.
    var text: String? {
        if let text = raw as? String { return text }
        if let number = raw as? NSNumber, !(raw is Bool) { return number.stringValue }
        return nil
    }

    var int: Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let text = raw as? String { return Int(text) }
        return nil
    }

    var double: Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let text = raw as? String { return Double(text) }
        return nil
    }

    var bool: Bool { (raw as? Bool) ?? ((raw as? NSNumber)?.boolValue ?? false) }

    var url: URL? { string.flatMap { $0.isEmpty ? nil : URL(string: $0) } }

    var date: Date? {
        guard let text = string else { return nil }
        return JSONNode.parseDate(text)
    }

    static func parseDate(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: text) { return date }
        // ESPN : « 2026-11-08T14:00Z » (sans secondes).
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd"] {
            short.dateFormat = format
            if let date = short.date(from: text) { return date }
        }
        return nil
    }
}

enum FootError: LocalizedError {
    case unavailable(Int)
    case notFound

    var errorDescription: String? {
        switch self {
        case .unavailable(let code): return "Données foot indisponibles (\(code))."
        case .notFound: return "Match introuvable."
        }
    }
}

/// Données foot gratuites et sans clé (API publique d'ESPN), mises en cache quelques minutes.
actor EspnClient {
    static let shared = EspnClient()

    private let site = "https://site.api.espn.com/apis/site/v2/sports/soccer"
    private let standingsAPI = "https://site.api.espn.com/apis/v2/sports/soccer"
    private var cache: [String: (at: Date, value: JSONNode)] = [:]

    /// Matchs d'une ligue pour un jour local (ESPN raisonne en heure de New York : on prend la veille aussi).
    func day(_ slug: String, _ day: Date) async throws -> [Match] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let age = maxAge(for: start)
        var all: [Match] = []
        for offset in [-1, 0] {
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let root = try await get("\(site)/\(slug)/scoreboard?dates=\(Self.stamp(date))", maxAge: age)
            all += Self.parseScoreboard(root, slug: slug)
        }
        var seen = Set<String>()
        return all
            .filter { calendar.isDate($0.date, inSameDayAs: start) && seen.insert($0.id).inserted }
            .sorted { $0.date < $1.date }
    }

    /// Plusieurs ligues (les ligues en erreur sont ignorées).
    func day(_ slugs: [String], _ date: Date) async -> [Match] {
        var result: [Match] = []
        for slug in Array(Set(slugs)) {
            if let matches = try? await day(slug, date) { result += matches }
        }
        return result.sorted { $0.date < $1.date }
    }

    func teamSchedule(_ teamID: String, upcoming: Bool) async throws -> [Match] {
        let url = "\(site)/all/teams/\(teamID)/schedule" + (upcoming ? "?fixture=true" : "")
        return Self.parseSchedule(try await get(url, maxAge: upcoming ? 600 : 300))
    }

    func summary(_ eventID: String, slug: String, live: Bool) async throws -> MatchDetail {
        let root = try await get("\(site)/\(slug)/summary?event=\(eventID)", maxAge: live ? 20 : 300)
        guard let detail = Self.parseSummary(root, slug: slug) else { throw FootError.notFound }
        return detail
    }

    func standings(_ slug: String) async throws -> LeagueTable {
        Self.parseStandings(try await get("\(standingsAPI)/\(slug)/standings", maxAge: 900))
    }

    func teams(_ slug: String) async throws -> [TeamRef] {
        let root = try await get("\(site)/\(slug)/teams", maxAge: 43_200)
        return root["sports"][0]["leagues"][0]["teams"].array
            .compactMap { Self.parseTeam($0["team"]) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func invalidate() { cache.removeAll() }

    private func maxAge(for day: Date) -> TimeInterval {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) || calendar.isDateInYesterday(day) { return 45 }
        return day < Date() ? 1800 : 600
    }

    private func get(_ url: String, maxAge: TimeInterval) async throws -> JSONNode {
        if let hit = cache[url], Date().timeIntervalSince(hit.at) < maxAge { return hit.value }
        guard let endpoint = URL(string: url) else { throw FootError.unavailable(0) }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw FootError.unavailable(code) }
        let value = try JSONNode(data: data)
        cache[url] = (Date(), value)
        return value
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    // MARK: Analyse (statique pour les tests)

    static func parseScoreboard(_ root: JSONNode, slug: String) -> [Match] {
        let league = root["leagues"][0]
        let leagueName = LeagueCatalog.name(of: slug, fallback: league["name"].string)
        LeagueCatalog.rememberLogo(slug, league["logos"][0]["href"].url)
        return root["events"].array.compactMap { parseEvent($0, slug: slug, leagueName: leagueName) }
    }

    static func parseSchedule(_ root: JSONNode) -> [Match] {
        root["events"].array.compactMap { event -> Match? in
            let league = event["league"]
            let slug = league["slug"].string ?? "all"
            let name = LeagueCatalog.name(of: slug, fallback: league["abbreviation"].string ?? league["name"].string)
            return parseEvent(event, slug: slug, leagueName: name)
        }
        .sorted { $0.date < $1.date }
    }

    static func parseEvent(_ event: JSONNode, slug: String, leagueName: String) -> Match? {
        guard let id = event["id"].text else { return nil }
        let competition = event["competitions"][0]
        guard competition.isObject else { return nil }
        var home = JSONNode(nil), away = JSONNode(nil)
        for competitor in competition["competitors"].array {
            if competitor["homeAway"].string == "home" { home = competitor } else { away = competitor }
        }
        guard home.isObject, away.isObject,
              let homeTeam = parseTeam(home["team"]), let awayTeam = parseTeam(away["team"]) else { return nil }

        let status = event["status"].isObject ? event["status"] : competition["status"]
        let (state, detail, clock) = parseStatus(status)

        var events: [MatchEvent] = []
        for item in competition["details"].array {
            let kind = MatchEventKind.from(item["type"]["text"].string)
            if kind == .other || kind == .substitution { continue }
            let who = item["athletesInvolved"][0]
            events.append(MatchEvent(
                kind: kind,
                clock: item["clock"]["displayValue"].string ?? "",
                isHome: item["team"]["id"].text == homeTeam.id,
                text: who["displayName"].string ?? who["shortName"].string ?? ""
            ))
        }

        return Match(
            id: id,
            leagueSlug: slug,
            leagueName: leagueName,
            date: event["date"].date ?? competition["date"].date ?? .distantPast,
            state: state,
            statusDetail: detail,
            clock: clock,
            home: homeTeam,
            away: awayTeam,
            homeScore: state == .scheduled ? nil : score(home),
            awayScore: state == .scheduled ? nil : score(away),
            homeWinner: home["winner"].bool,
            awayWinner: away["winner"].bool,
            venue: competition["venue"]["fullName"].string,
            events: events
        )
    }

    static func parseSummary(_ root: JSONNode, slug: String) -> MatchDetail? {
        let header = root["header"]
        let leagueSlug = header["league"]["slug"].string ?? slug
        let leagueName = LeagueCatalog.name(of: leagueSlug, fallback: header["league"]["name"].string)
        guard let match = parseEvent(header, slug: leagueSlug, leagueName: leagueName) else { return nil }
        let homeID = match.home.id

        var stats: [StatLine] = []
        var homeStats: [String: (String, String)] = [:]
        var awayStats: [String: (String, String)] = [:]
        for team in root["boxscore"]["teams"].array {
            let isHome = team["team"]["id"].text == homeID
            for stat in team["statistics"].array {
                guard let name = stat["name"].string else { continue }
                let value = (stat["label"].string ?? name, stat["displayValue"].text ?? "0")
                if isHome { homeStats[name] = value } else { awayStats[name] = value }
            }
        }
        let order = ["possessionPct", "totalShots", "shotsOnTarget", "blockedShots", "wonCorners", "saves", "totalPasses",
                     "accuratePasses", "totalCrosses", "totalTackles", "interceptions", "foulsCommitted", "offsides",
                     "yellowCards", "redCards"]
        for key in order {
            guard let h = homeStats[key], let a = awayStats[key] else { continue }
            stats.append(StatLine(key: key, label: FootFormat.statLabel(key) ?? h.0, home: h.1, away: a.1))
        }

        var events: [MatchEvent] = []
        for item in root["keyEvents"].array {
            let type = item["type"]
            let kind = MatchEventKind.from(type["type"].string, type["text"].string)
            if kind == .other { continue }
            let teamID = item["team"]["id"].text
            let isHome = teamID.map { $0 == homeID } ?? (item["team"]["displayName"].string == match.home.name)
            let names = item["participants"].array.compactMap { $0["athlete"]["displayName"].string }
            let text: String
            if kind == .substitution, names.count >= 2 {
                text = "\(names[0]) ↔ \(names[1])"
            } else {
                text = names.first ?? item["shortText"].string ?? type["text"].string ?? ""
            }
            events.append(MatchEvent(kind: kind, clock: item["clock"]["displayValue"].string ?? "", isHome: isHome, text: text))
        }

        var lineups: [Lineup] = root["rosters"].array.map { roster in
            let players = roster["roster"].array.map { player in
                LineupPlayer(
                    jersey: player["jersey"].text ?? "",
                    name: player["athlete"]["displayName"].string ?? "?",
                    position: player["position"]["abbreviation"].string ?? "",
                    starter: player["starter"].bool,
                    subbedIn: player["subbedIn"].bool,
                    subbedOut: player["subbedOut"].bool
                )
            }
            let formation = roster["formation"]
            return Lineup(
                teamName: roster["team"]["displayName"].string ?? "",
                isHome: roster["homeAway"].string == "home",
                formation: formation.string ?? formation["summary"].string ?? formation["name"].string,
                players: players
            )
        }
        lineups.sort { $0.isHome && !$1.isHome }

        var standings: [StandingRow] = []
        for group in root["standings"]["groups"].array {
            let rows = parseEntries(group["standings"]["entries"])
            if rows.contains(where: { $0.teamID == homeID || $0.teamID == match.away.id || $0.teamName == match.home.name || $0.teamName == match.away.name }) {
                standings = rows
                break
            }
            if standings.isEmpty { standings = rows }
        }

        var attendance: String?
        if let count = root["gameInfo"]["attendance"].int, count > 0 {
            attendance = count.formatted(.number.locale(FootFormat.french))
        }
        return MatchDetail(match: match, stats: stats, events: events, lineups: lineups, standings: standings, attendance: attendance)
    }

    static func parseStandings(_ root: JSONNode) -> LeagueTable {
        let groups = root["children"].array.compactMap { child -> StandingGroup? in
            let rows = parseEntries(child["standings"]["entries"])
            return rows.isEmpty ? nil : StandingGroup(name: child["name"].string ?? "", rows: rows)
        }
        return LeagueTable(title: root["name"].string ?? "Classement", groups: groups)
    }

    private static func parseEntries(_ entries: JSONNode) -> [StandingRow] {
        var rows: [StandingRow] = []
        for entry in entries.array {
            let team = entry["team"]
            let teamID: String
            let teamName: String
            var logo: URL?
            if team.isObject {
                teamID = team["id"].text ?? ""
                teamName = team["displayName"].string ?? team["name"].string ?? ""
                logo = team["logos"][0]["href"].url ?? (teamID.isEmpty ? nil : TeamRef.logo(for: teamID))
            } else {
                teamID = entry["id"].text ?? ""
                teamName = team.string ?? ""
                if !teamID.isEmpty { logo = TeamRef.logo(for: teamID) }
            }
            var stats: [String: String] = [:]
            for stat in entry["stats"].array {
                if let name = stat["name"].string { stats[name] = stat["displayValue"].text ?? "" }
            }
            func value(_ key: String) -> Int { Int(FootFormat.number(stats[key])) }
            let rank = value("rank")
            rows.append(StandingRow(
                rank: rank > 0 ? rank : rows.count + 1,
                teamID: teamID, teamName: teamName, logo: logo,
                played: value("gamesPlayed"), won: value("wins"), drawn: value("ties"), lost: value("losses"),
                goalsFor: value("pointsFor"), goalsAgainst: value("pointsAgainst"),
                goalDiff: stats["pointDifferential"] ?? "",
                points: value("points"),
                noteColor: entry["note"]["color"].string,
                noteText: entry["note"]["description"].string
            ))
        }
        return rows.sorted { $0.rank < $1.rank }
    }

    static func parseTeam(_ team: JSONNode) -> TeamRef? {
        guard let id = team["id"].text else { return nil }
        let name = team["displayName"].string ?? team["name"].string ?? id
        return TeamRef(
            id: id,
            name: name,
            shortName: team["shortDisplayName"].string ?? name,
            abbreviation: team["abbreviation"].string ?? "",
            logo: team["logo"].url ?? team["logos"][0]["href"].url ?? TeamRef.logo(for: id),
            color: team["color"].string
        )
    }

    private static func parseStatus(_ status: JSONNode) -> (MatchState, String, String?) {
        let type = status["type"]
        let name = type["name"].string ?? ""
        var detail = type["shortDetail"].string ?? type["detail"].string ?? ""
        let clock = status["displayClock"].string
        var state: MatchState
        switch type["state"].string {
        case "in": state = .live
        case "post": state = .finished
        default: state = .scheduled
        }
        if ["POSTPONED", "CANCELED", "SUSPENDED", "ABANDONED"].contains(where: { name.contains($0) }) { state = .postponed }
        if state == .live && (name.contains("HALFTIME") || detail == "HT") { detail = "HT" }
        return (state, detail, state == .live && detail != "HT" ? clock : nil)
    }

    private static func score(_ competitor: JSONNode) -> String? {
        let score = competitor["score"]
        return score.text ?? score["displayValue"].string
    }
}
