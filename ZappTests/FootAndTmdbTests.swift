import XCTest
@testable import Zapp

final class EspnParsingTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    func testParsesScoreboard() throws {
        let root = try json("""
        {"leagues":[{"name":"English Premier League","slug":"eng.1","logos":[{"href":"https://a.espncdn.com/i/leaguelogos/soccer/500/23.png"}]}],
         "events":[{"id":"401879244","date":"2026-11-08T14:00Z",
          "status":{"displayClock":"90'+6'","type":{"state":"post","completed":true,"detail":"FT","shortDetail":"FT","name":"STATUS_FULL_TIME"}},
          "competitions":[{"venue":{"fullName":"American Express Stadium"},
            "details":[{"type":{"text":"Goal"},"clock":{"displayValue":"15'"},"team":{"id":"331"},"athletesInvolved":[{"displayName":"Diego Gómez"}]},
                       {"type":{"text":"Red Card"},"clock":{"displayValue":"23'"},"team":{"id":"337"},"athletesInvolved":[{"displayName":"Igor Thiago"}]}],
            "competitors":[
              {"id":"331","homeAway":"home","score":"2","winner":true,"team":{"id":"331","displayName":"Brighton & Hove Albion","shortDisplayName":"Brighton","abbreviation":"BHA","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/331.png"}},
              {"id":"337","homeAway":"away","score":"0","winner":false,"team":{"id":"337","displayName":"Brentford","shortDisplayName":"Brentford","abbreviation":"BRE"}}]}]},
          {"id":"2","date":"2026-11-09T20:00Z","status":{"displayClock":"67'","type":{"state":"in","name":"STATUS_SECOND_HALF","shortDetail":"67'"}},
           "competitions":[{"competitors":[
              {"homeAway":"home","score":"1","team":{"id":"1","displayName":"A"}},
              {"homeAway":"away","score":"1","team":{"id":"2","displayName":"B"}}]}]}]}
        """)
        let matches = EspnClient.parseScoreboard(root, slug: "eng.1")
        XCTAssertEqual(matches.count, 2)
        let match = matches[0]
        XCTAssertEqual(match.leagueName, "Premier League")
        XCTAssertEqual(match.state, .finished)
        XCTAssertEqual(match.home.shortName, "Brighton")
        XCTAssertEqual(match.homeScore, "2")
        XCTAssertEqual(match.awayScore, "0")
        XCTAssertTrue(match.homeWinner)
        XCTAssertEqual(match.statusText, "Terminé")
        XCTAssertEqual(match.events.count, 2)
        XCTAssertTrue(match.events[0].isHome)
        XCTAssertEqual(match.events[1].kind, .red)
        XCTAssertEqual(match.away.logo, TeamRef.logo(for: "337"))

        let live = matches[1]
        XCTAssertEqual(live.state, .live)
        XCTAssertEqual(live.statusText, "67'")
        XCTAssertEqual(LeagueCatalog.logo(for: "eng.1")?.absoluteString, "https://a.espncdn.com/i/leaguelogos/soccer/500/23.png")
    }

    func testScheduleScoresCanBeObjects() throws {
        let root = try json("""
        {"events":[{"id":"9","date":"2026-11-07T18:00Z","league":{"slug":"fra.1","abbreviation":"Ligue 1"},
          "competitions":[{"status":{"type":{"state":"post","shortDetail":"FT"}},"competitors":[
            {"homeAway":"home","score":{"value":0.0,"displayValue":"0"},"team":{"id":"172","displayName":"AJ Auxerre"}},
            {"homeAway":"away","score":{"value":1.0,"displayValue":"1"},"winner":true,"team":{"id":"6851","displayName":"Paris FC"}}]}]}]}
        """)
        let matches = EspnClient.parseSchedule(root)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].leagueSlug, "fra.1")
        XCTAssertEqual(matches[0].homeScore, "0")
        XCTAssertEqual(matches[0].awayScore, "1")
        XCTAssertTrue(matches[0].awayWinner)
        XCTAssertTrue(matches[0].involves("6851"))
    }

    func testParsesSummary() throws {
        let root = try json("""
        {"header":{"id":"401879244","league":{"slug":"eng.1","name":"English Premier League"},
           "competitions":[{"date":"2026-11-08T14:00Z","status":{"type":{"state":"post","shortDetail":"FT"}},"competitors":[
             {"homeAway":"home","score":"2","team":{"id":"331","displayName":"Brighton & Hove Albion","logos":[{"href":"https://x/331.png"}]}},
             {"homeAway":"away","score":"0","team":{"id":"337","displayName":"Brentford"}}]}]},
         "boxscore":{"teams":[
           {"team":{"id":"331"},"statistics":[{"name":"possessionPct","label":"Possession","displayValue":"75.3"},{"name":"totalShots","displayValue":"20"}]},
           {"team":{"id":"337"},"statistics":[{"name":"possessionPct","label":"Possession","displayValue":"24.7"},{"name":"totalShots","displayValue":"9"}]}]},
         "keyEvents":[{"type":{"type":"kickoff","text":"Kickoff"}},
           {"type":{"type":"goal","text":"Goal"},"clock":{"displayValue":"15'"},"team":{"id":"331"},"participants":[{"athlete":{"displayName":"Diego Gómez"}}]},
           {"type":{"type":"penalty---scored","text":"Penalty - Scored"},"clock":{"displayValue":"42'"},"team":{"displayName":"Brighton & Hove Albion"},"participants":[{"athlete":{"displayName":"Pascal Gross"}}]},
           {"type":{"type":"substitution","text":"Substitution"},"clock":{"displayValue":"60'"},"team":{"id":"337"},"participants":[{"athlete":{"displayName":"In"}},{"athlete":{"displayName":"Out"}}]}],
         "rosters":[{"homeAway":"away","formation":"4-4-2","team":{"displayName":"Brentford"},"roster":[{"starter":true,"jersey":"1","athlete":{"displayName":"Kelleher"},"position":{"abbreviation":"G"}}]},
                    {"homeAway":"home","formation":"4-2-3-1","team":{"displayName":"Brighton"},"roster":[]}],
         "standings":{"groups":[{"standings":{"entries":[{"team":"Arsenal","id":"359","stats":[{"name":"rank","displayValue":"1"},{"name":"points","displayValue":"27"},{"name":"gamesPlayed","displayValue":"10"}]}]}}]},
         "gameInfo":{"attendance":31629}}
        """)
        let detail = try XCTUnwrap(EspnClient.parseSummary(root, slug: "all"))
        XCTAssertEqual(detail.match.leagueSlug, "eng.1")
        XCTAssertEqual(detail.match.home.logo?.absoluteString, "https://x/331.png")
        XCTAssertEqual(detail.stats.count, 2)
        XCTAssertEqual(detail.stats[0].label, "Possession (%)")
        XCTAssertEqual(detail.stats[0].homeValue, 75.3, accuracy: 0.001)
        XCTAssertEqual(detail.events.count, 3)
        XCTAssertEqual(detail.events[1].kind, .penalty)
        XCTAssertTrue(detail.events[1].isHome)
        XCTAssertEqual(detail.events[2].text, "In ↔ Out")
        XCTAssertFalse(detail.events[2].isHome)
        XCTAssertTrue(detail.lineups[0].isHome)
        XCTAssertEqual(detail.lineups[1].formation, "4-4-2")
        XCTAssertEqual(detail.standings.count, 1)
        XCTAssertEqual(detail.standings[0].teamName, "Arsenal")
        XCTAssertEqual(detail.standings[0].points, 27)
        XCTAssertEqual(detail.standings[0].logo, TeamRef.logo(for: "359"))
        XCTAssertNotNil(detail.attendance)
    }

    func testParsesStandings() throws {
        let root = try json("""
        {"name":"French Ligue 1","children":[{"name":"French Ligue 1 2026-27","standings":{"entries":[
          {"team":{"id":"160","displayName":"Paris Saint-Germain","logos":[{"href":"https://x/160.png"}]},
           "note":{"color":"#81D6AC","description":"Champions League"},
           "stats":[{"name":"gamesPlayed","displayValue":"10"},{"name":"wins","displayValue":"7"},{"name":"ties","displayValue":"2"},
                    {"name":"losses","displayValue":"1"},{"name":"pointsFor","displayValue":"22"},{"name":"pointsAgainst","displayValue":"10"},
                    {"name":"pointDifferential","displayValue":"+12"},{"name":"points","displayValue":"23"},{"name":"rank","displayValue":"1"}]}]}}]}
        """)
        let table = EspnClient.parseStandings(root)
        XCTAssertEqual(table.groups.count, 1)
        let row = try XCTUnwrap(table.groups.first?.rows.first)
        XCTAssertEqual(row.teamName, "Paris Saint-Germain")
        XCTAssertEqual(row.points, 23)
        XCTAssertEqual(row.goalsFor, 22)
        XCTAssertEqual(row.goalDiff, "+12")
        XCTAssertEqual(row.noteText, "Champions League")
    }
}

final class ChannelMatcherTests: XCTestCase {
    private func channel(_ name: String) -> MediaItem {
        MediaItem(id: name, name: name, group: "TV", kind: .live, streamURL: URL(string: "http://example.com/1"))
    }

    func testFindsChannelsByBroadcaster() {
        let channels = ["FR | CANAL+ FOOT FHD", "FR | CANAL+ SPORT 360 HD", "FR | CANAL+", "FR | beIN SPORTS 1 HD", "UK | Sky Sports Main Event", "FR | TF1"].map(channel)
        let canal = ChannelMatcher.find(in: channels, keywords: LeagueCatalog.find("eng.1")?.channelKeywords)
        XCTAssertEqual(canal.map(\.name), ["FR | CANAL+ FOOT FHD", "FR | CANAL+ SPORT 360 HD", "FR | CANAL+"])
        XCTAssertEqual(ChannelMatcher.find(in: channels, keywords: "beIN Sports").map(\.name), ["FR | beIN SPORTS 1 HD"])
        XCTAssertTrue(ChannelMatcher.find(in: channels, keywords: "").isEmpty)
    }

    func testNormalizesNames() {
        XCTAssertEqual(ChannelMatcher.normalize("FR | CANAL+ FOOT FHD"), "fr canal plus foot fhd")
        XCTAssertEqual(ChannelMatcher.tokens("L'Équipe HD"), ["l", "equipe"])
    }

    func testHistoryResumeRules() {
        let url = URL(string: "http://example.com/film.mp4")!
        XCTAssertTrue(HistoryEntry(id: "a", title: "A", url: url, isLive: false, positionMs: 600_000, durationMs: 6_000_000).canResume)
        XCTAssertFalse(HistoryEntry(id: "a", title: "A", url: url, isLive: false, positionMs: 10_000, durationMs: 6_000_000).canResume)
        XCTAssertFalse(HistoryEntry(id: "a", title: "A", url: url, isLive: false, positionMs: 5_900_000, durationMs: 6_000_000).canResume)
        XCTAssertFalse(HistoryEntry(id: "a", title: "A", url: url, isLive: true, positionMs: 600_000, durationMs: 6_000_000).canResume)
    }
}

final class TmdbTests: XCTestCase {
    func testCleansPlaylistNames() {
        let cases: [(String, String, Int?)] = [
            ("FR - Avatar (2009) [4K]", "Avatar", 2009),
            ("|FR| Dune : Deuxième partie 2024", "Dune : Deuxième partie", 2024),
            ("[VF] Inception MULTI 1080p", "Inception", nil),
            ("WALL-E", "WALL-E", nil),
            ("1917", "1917", nil),
            ("Breaking Bad S01 E02", "Breaking Bad", nil),
            ("EN: The.Matrix.1999", "The Matrix", 1999),
        ]
        for (name, title, year) in cases {
            let result = TitleCleaner.clean(name)
            XCTAssertEqual(result.title, title, name)
            XCTAssertEqual(result.year, year, name)
        }
    }

    func testKeyIgnoresAccentsCaseAndArticle() {
        XCTAssertEqual(TitleCleaner.key("Amélie"), TitleCleaner.key("AMELIE"))
        XCTAssertEqual(TitleCleaner.key("The Matrix"), "matrix")
        XCTAssertEqual(TitleCleaner.key("Dune : Deuxième partie"), "dune deuxieme partie")
    }

    func testSearchPrefersExactTitle() throws {
        let root = try JSONValue(data: Data(#"{"results":[{"id":1,"title":"Avatar : La voie de l'eau"},{"id":19995,"title":"Avatar"}]}"#.utf8))
        XCTAssertEqual(TmdbClient.parseSearch(root, title: "Avatar"), 19995)
        XCTAssertEqual(TmdbClient.parseSearch(root, title: "Autre"), 1)
    }

    func testParsesMovieDetails() throws {
        let root = try JSONValue(data: Data("""
        {"id":19995,"title":"Avatar","original_title":"Avatar","release_date":"2009-12-15","vote_average":7.588,"vote_count":32000,
         "overview":"Malgré sa paralysie…","tagline":"Entrez dans le monde de Pandora.","runtime":162,
         "poster_path":"/p.jpg","backdrop_path":"/b.jpg","genres":[{"id":28,"name":"Action"},{"id":12,"name":"Aventure"}],
         "credits":{"cast":[{"name":"Sam Worthington","character":"Jake Sully","profile_path":"/s.jpg"}],
                    "crew":[{"job":"Producer","name":"X"},{"job":"Director","name":"James Cameron"}]},
         "videos":{"results":[{"site":"YouTube","type":"Teaser","key":"tease","iso_639_1":"en"},
                              {"site":"YouTube","type":"Trailer","key":"frtrailer","iso_639_1":"fr","official":true}]},
         "images":{"logos":[{"file_path":"/en.png","iso_639_1":"en"},{"file_path":"/fr.png","iso_639_1":"fr"}]}}
        """.utf8))
        let info = TmdbClient.parseDetails(root, kind: .movie)
        XCTAssertEqual(info.title, "Avatar")
        XCTAssertNil(info.originalTitle)
        XCTAssertEqual(info.year, 2009)
        XCTAssertEqual(info.rating, 7.6)
        XCTAssertEqual(info.runtime, "2 h 42")
        XCTAssertEqual(info.genres, ["Action", "Aventure"])
        XCTAssertEqual(info.director, "James Cameron")
        XCTAssertEqual(info.cast.first?.character, "Jake Sully")
        XCTAssertEqual(info.trailerURL?.absoluteString, "https://www.youtube.com/watch?v=frtrailer")
        XCTAssertEqual(info.logo?.absoluteString, "https://image.tmdb.org/t/p/w500/fr.png")
    }

    func testParsesTrendingAndSkipsPeople() throws {
        let root = try JSONValue(data: Data("""
        {"results":[{"id":1,"media_type":"movie","title":"Film","release_date":"2026-10-01","backdrop_path":"/a.jpg","vote_average":7.2},
                    {"id":2,"media_type":"person","name":"Quelqu'un"},
                    {"id":3,"media_type":"tv","name":"Série","first_air_date":"2025-05-05"}]}
        """.utf8))
        let trends = TmdbClient.parseTrending(root)
        XCTAssertEqual(trends.count, 2)
        XCTAssertEqual(trends[1].kind, .tv)
        XCTAssertEqual(trends[0].year, 2026)
    }
}
