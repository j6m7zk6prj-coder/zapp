import Foundation

struct TeamRef: Hashable, Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let shortName: String
    let abbreviation: String
    let logo: URL?
    let color: String?

    static func logo(for id: String) -> URL? {
        URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\(id).png")
    }
}

enum MatchState: String, Codable, Sendable {
    case scheduled, live, finished, postponed
}

enum MatchEventKind: String, Codable, Sendable {
    case goal, penalty, ownGoal, missedPenalty, yellow, red, substitution, other

    static func from(_ type: String?, _ text: String? = nil) -> MatchEventKind {
        let t = (type ?? text ?? "").lowercased()
        if t.contains("own") { return .ownGoal }
        if t.contains("penalty") && (t.contains("miss") || t.contains("saved")) { return .missedPenalty }
        if t.contains("penalty") { return .penalty }
        if t.contains("goal") { return .goal }
        if t.contains("red") { return .red }
        if t.contains("yellow") { return .yellow }
        if t.contains("substitution") { return .substitution }
        return .other
    }
}

struct MatchEvent: Hashable, Codable, Sendable, Identifiable {
    let kind: MatchEventKind
    let clock: String
    let isHome: Bool
    let text: String

    var id: String { "\(kind.rawValue)-\(clock)-\(text)-\(isHome)" }
    var isGoal: Bool { kind == .goal || kind == .penalty || kind == .ownGoal }

    var symbol: String {
        switch kind {
        case .goal, .penalty, .ownGoal: return "soccerball"
        case .missedPenalty: return "xmark.circle"
        case .yellow, .red: return "rectangle.portrait.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .other: return "circle.fill"
        }
    }
}

struct Match: Hashable, Codable, Sendable, Identifiable {
    let id: String
    let leagueSlug: String
    var leagueName: String
    let date: Date
    let state: MatchState
    /// « FT », « HT », « 67' »…
    let statusDetail: String
    let clock: String?
    let home: TeamRef
    let away: TeamRef
    let homeScore: String?
    let awayScore: String?
    let homeWinner: Bool
    let awayWinner: Bool
    let venue: String?
    var events: [MatchEvent]

    func involves(_ teamID: String) -> Bool { home.id == teamID || away.id == teamID }

    /// Statut lisible en français.
    var statusText: String {
        switch state {
        case .live:
            return statusDetail == "HT" || statusDetail == "Halftime" ? "Mi-temps" : (clock ?? statusDetail)
        case .finished:
            if statusDetail.localizedCaseInsensitiveContains("pen") { return "Terminé (t.a.b.)" }
            if statusDetail.localizedCaseInsensitiveContains("aet") { return "Terminé (a.p.)" }
            return "Terminé"
        case .postponed:
            return statusDetail.localizedCaseInsensitiveContains("cancel") ? "Annulé" : "Reporté"
        case .scheduled:
            return FootFormat.kickoff(date)
        }
    }
}

struct StatLine: Hashable, Sendable, Identifiable {
    let key: String
    let label: String
    let home: String
    let away: String

    var id: String { key }
    var homeValue: Double { FootFormat.number(home) }
    var awayValue: Double { FootFormat.number(away) }
}

struct LineupPlayer: Hashable, Sendable, Identifiable {
    let jersey: String
    let name: String
    let position: String
    let starter: Bool
    let subbedIn: Bool
    let subbedOut: Bool
    var id: String { jersey + name }
}

struct Lineup: Hashable, Sendable, Identifiable {
    let teamName: String
    let isHome: Bool
    let formation: String?
    let players: [LineupPlayer]
    var id: String { teamName }
}

struct StandingRow: Hashable, Sendable, Identifiable {
    let rank: Int
    let teamID: String
    let teamName: String
    let logo: URL?
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let goalDiff: String
    let points: Int
    let noteColor: String?
    let noteText: String?
    var id: String { "\(rank)-\(teamID)-\(teamName)" }
}

struct StandingGroup: Hashable, Sendable, Identifiable {
    let name: String
    let rows: [StandingRow]
    var id: String { name }
}

struct LeagueTable: Sendable {
    let title: String
    let groups: [StandingGroup]
}

struct MatchDetail: Sendable {
    let match: Match
    let stats: [StatLine]
    let events: [MatchEvent]
    let lineups: [Lineup]
    let standings: [StandingRow]
    let attendance: String?
}

/// Une compétition, avec son diffuseur habituel en France.
struct League: Hashable, Sendable, Identifiable {
    let slug: String
    let name: String
    let area: String
    let broadcaster: String
    let channelKeywords: String
    var id: String { slug }
}

enum LeagueCatalog {
    // Diffuseurs en France pour la saison 2026-2027 (source : Maxifoot, 6 août 2026). Modifiables dans les réglages.
    private static let canal = "Canal+ Foot, Canal+ Sport 360, Canal+ Sport, Canal+ Premier League, Canal+"
    private static let bein = "beIN Sports 1, beIN Sports 2, beIN Sports 3, beIN Sports"
    private static let dazn = "DAZN 1, DAZN 2, DAZN"

    static let all: [League] = [
        League(slug: "fra.1", name: "Ligue 1", area: "France", broadcaster: "Ligue 1+", channelKeywords: "Ligue 1+, Ligue 1"),
        League(slug: "fra.2", name: "Ligue 2", area: "France", broadcaster: "beIN Sports", channelKeywords: bein),
        League(slug: "fra.coupe_de_france", name: "Coupe de France", area: "France", broadcaster: "beIN Sports", channelKeywords: bein),
        League(slug: "uefa.champions", name: "Ligue des champions", area: "Europe", broadcaster: "Canal+", channelKeywords: canal),
        League(slug: "uefa.europa", name: "Ligue Europa", area: "Europe", broadcaster: "Canal+", channelKeywords: canal),
        League(slug: "uefa.europa.conf", name: "Ligue Conférence", area: "Europe", broadcaster: "Canal+", channelKeywords: canal),
        League(slug: "uefa.nations", name: "Ligue des nations", area: "Europe", broadcaster: "L'Équipe", channelKeywords: "L'Equipe"),
        League(slug: "eng.1", name: "Premier League", area: "Angleterre", broadcaster: "Canal+", channelKeywords: canal),
        League(slug: "eng.2", name: "Championship", area: "Angleterre", broadcaster: "", channelKeywords: ""),
        League(slug: "eng.fa", name: "FA Cup", area: "Angleterre", broadcaster: "beIN Sports", channelKeywords: bein),
        League(slug: "eng.league_cup", name: "Carabao Cup", area: "Angleterre", broadcaster: "", channelKeywords: ""),
        League(slug: "esp.1", name: "LaLiga", area: "Espagne", broadcaster: "DAZN / Disney+", channelKeywords: dazn + ", Disney+"),
        League(slug: "esp.copa_del_rey", name: "Coupe du Roi", area: "Espagne", broadcaster: "DAZN", channelKeywords: dazn),
        League(slug: "ita.1", name: "Serie A", area: "Italie", broadcaster: "DAZN", channelKeywords: dazn),
        League(slug: "ita.coppa_italia", name: "Coupe d'Italie", area: "Italie", broadcaster: "DAZN", channelKeywords: dazn),
        League(slug: "ger.1", name: "Bundesliga", area: "Allemagne", broadcaster: "beIN Sports", channelKeywords: bein),
        League(slug: "ger.dfb_pokal", name: "Coupe d'Allemagne", area: "Allemagne", broadcaster: "", channelKeywords: ""),
        League(slug: "por.1", name: "Liga Portugal", area: "Portugal", broadcaster: "", channelKeywords: ""),
        League(slug: "ned.1", name: "Eredivisie", area: "Pays-Bas", broadcaster: "", channelKeywords: ""),
        League(slug: "bel.1", name: "Pro League", area: "Belgique", broadcaster: "", channelKeywords: ""),
        League(slug: "tur.1", name: "Süper Lig", area: "Turquie", broadcaster: "", channelKeywords: ""),
        League(slug: "sco.1", name: "Scottish Premiership", area: "Écosse", broadcaster: "", channelKeywords: ""),
        League(slug: "ksa.1", name: "Saudi Pro League", area: "Arabie saoudite", broadcaster: "", channelKeywords: ""),
        League(slug: "usa.1", name: "MLS", area: "États-Unis", broadcaster: "Apple TV", channelKeywords: "Apple TV, MLS"),
        League(slug: "bra.1", name: "Brasileirão", area: "Brésil", broadcaster: "", channelKeywords: ""),
        League(slug: "arg.1", name: "Liga Profesional", area: "Argentine", broadcaster: "", channelKeywords: ""),
        League(slug: "mex.1", name: "Liga MX", area: "Mexique", broadcaster: "", channelKeywords: ""),
        League(slug: "conmebol.libertadores", name: "Copa Libertadores", area: "Amérique du Sud", broadcaster: "", channelKeywords: ""),
        League(slug: "fifa.worldq.uefa", name: "Qualifs Coupe du monde (Europe)", area: "International", broadcaster: "", channelKeywords: ""),
        League(slug: "fifa.friendly", name: "Matchs amicaux internationaux", area: "International", broadcaster: "", channelKeywords: ""),
        League(slug: "caf.nations", name: "Coupe d'Afrique des nations", area: "International", broadcaster: "", channelKeywords: ""),
        League(slug: "fifa.world", name: "Coupe du monde", area: "International", broadcaster: "", channelKeywords: ""),
        League(slug: "uefa.euro", name: "Euro", area: "International", broadcaster: "", channelKeywords: ""),
    ]

    static let defaultFollowed = ["fra.1", "uefa.champions", "eng.1"]

    private static let bySlug = Dictionary(uniqueKeysWithValues: all.map { ($0.slug, $0) })
    private static let logoLock = NSLock()
    nonisolated(unsafe) private static var logos: [String: URL] = [:]

    static func find(_ slug: String) -> League? { bySlug[slug] }

    static func name(of slug: String, fallback: String? = nil) -> String {
        if let league = bySlug[slug] { return league.name }
        if let fallback, !fallback.isEmpty { return fallback }
        return slug
    }

    /// Logo de compétition renvoyé par ESPN (mémorisé au premier chargement).
    static func rememberLogo(_ slug: String, _ url: URL?) {
        guard let url else { return }
        logoLock.lock()
        logos[slug] = url
        logoLock.unlock()
    }

    static func logo(for slug: String) -> URL? {
        logoLock.lock()
        defer { logoLock.unlock() }
        if let url = logos[slug] { return url }
        // Logos ESPN connus (évite d'attendre le premier chargement).
        let ids = ["fra.1": 9, "eng.1": 23, "esp.1": 15, "ita.1": 12, "ger.1": 10, "uefa.champions": 2, "uefa.europa": 2310, "fra.2": 96]
        if let id = ids[slug] { return URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500/\(id).png") }
        return nil
    }
}

enum FootFormat {
    static let french = Locale(identifier: "fr_FR")

    static func kickoff(_ date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(french))
        return "\(dayTitle(date, calendar: calendar, short: true)) · \(time)"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(french))
    }

    static func dayTitle(_ date: Date, calendar: Calendar = .current, short: Bool = false) -> String {
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInTomorrow(date) { return "Demain" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        let text = short
            ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(french))
            : date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(french))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func number(_ text: String?) -> Double {
        guard let text, !text.trimmed.isEmpty else { return 0 }
        let cleaned = text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".").trimmed
        return Double(cleaned) ?? 0
    }

    static func statLabel(_ key: String) -> String? {
        switch key {
        case "possessionPct": return "Possession (%)"
        case "totalShots": return "Tirs"
        case "shotsOnTarget": return "Tirs cadrés"
        case "blockedShots": return "Tirs contrés"
        case "wonCorners": return "Corners"
        case "foulsCommitted": return "Fautes"
        case "offsides": return "Hors-jeu"
        case "yellowCards": return "Cartons jaunes"
        case "redCards": return "Cartons rouges"
        case "saves": return "Arrêts"
        case "totalPasses": return "Passes"
        case "accuratePasses": return "Passes réussies"
        case "totalCrosses": return "Centres"
        case "totalTackles": return "Tacles"
        case "interceptions": return "Interceptions"
        default: return nil
        }
    }
}

/// Trouve dans la playlist les chaînes d'un diffuseur (« Canal+ Foot » → « FR | CANAL+ FOOT FHD »).
enum ChannelMatcher {
    private static let noise: Set<String> = [
        "fr", "france", "hd", "fhd", "uhd", "sd", "4k", "hevc", "h265", "raw", "vip", "backup", "multi", "tv", "live", "the",
    ]

    static func normalize(_ text: String) -> String {
        let folded = text.lowercased()
            .replacingOccurrences(of: "+", with: " plus ")
            .folding(options: [.diacriticInsensitive], locale: french)
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    private static let french = Locale(identifier: "fr_FR")

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init).filter { !noise.contains($0) }
    }

    static func splitKeywords(_ keywords: String?) -> [String] {
        (keywords ?? "")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }

    /// Chaînes en direct correspondant aux mots-clés, dans l'ordre des mots-clés puis de la plus courte à la plus longue.
    static func find(in channels: [MediaItem], keywords: String?, limit: Int = 12) -> [MediaItem] {
        let patterns = splitKeywords(keywords).map(tokens).filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return [] }
        var results: [(item: MediaItem, pattern: Int, length: Int)] = []
        for channel in channels where channel.kind == .live {
            let words = Set(tokens(channel.name))
            if let index = patterns.firstIndex(where: { $0.allSatisfy(words.contains) }) {
                results.append((channel, index, channel.name.count))
            }
        }
        var seen = Set<String>()
        return results
            .sorted { $0.pattern != $1.pattern ? $0.pattern < $1.pattern : $0.length < $1.length }
            .map(\.item)
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }
}
