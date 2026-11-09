using System.Text.Json;
using ZappTV.Core;
using ZappTV.Core.Football;

namespace ZappTV.Tests;

public class EspnParsingTests
{
    // Extraits réels de l'API (forme vérifiée le 9 novembre 2026).
    private const string Scoreboard = """
        {"leagues":[{"name":"English Premier League","slug":"eng.1","logos":[{"href":"https://a.espncdn.com/i/leaguelogos/soccer/500/23.png"}]}],
         "events":[{"id":"401879244","date":"2026-11-08T14:00Z","name":"Brentford at Brighton & Hove Albion",
          "status":{"displayClock":"90'+6'","type":{"state":"post","completed":true,"detail":"FT","shortDetail":"FT","name":"STATUS_FULL_TIME"}},
          "competitions":[{"venue":{"fullName":"American Express Stadium"},
            "details":[{"type":{"text":"Goal"},"clock":{"displayValue":"15'"},"team":{"id":"331"},"athletesInvolved":[{"displayName":"Diego Gómez"}]},
                       {"type":{"text":"Red Card"},"clock":{"displayValue":"23'"},"team":{"id":"337"},"athletesInvolved":[{"displayName":"Igor Thiago"}]}],
            "competitors":[
              {"id":"331","homeAway":"home","score":"2","winner":true,"team":{"id":"331","displayName":"Brighton & Hove Albion","shortDisplayName":"Brighton","abbreviation":"BHA","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/331.png"}},
              {"id":"337","homeAway":"away","score":"0","winner":false,"team":{"id":"337","displayName":"Brentford","shortDisplayName":"Brentford","abbreviation":"BRE","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/337.png"}}]}]},
          {"id":"2","date":"2026-11-09T20:00Z","status":{"displayClock":"67'","type":{"state":"in","name":"STATUS_SECOND_HALF","shortDetail":"67'"}},
           "competitions":[{"competitors":[
              {"homeAway":"home","score":"1","team":{"id":"1","displayName":"A"}},
              {"homeAway":"away","score":"1","team":{"id":"2","displayName":"B"}}]}]}]}
        """;

    [Fact]
    public void ParsesScoreboard()
    {
        using var doc = JsonDocument.Parse(Scoreboard);
        var matches = EspnClient.ParseScoreboard(doc.RootElement, "eng.1");

        Assert.Equal(2, matches.Count);
        var m = matches[0];
        Assert.Equal("Premier League", m.LeagueName);
        Assert.Equal(MatchState.Finished, m.State);
        Assert.Equal("Brighton", m.Home.ShortName);
        Assert.Equal("2", m.HomeScore);
        Assert.Equal("0", m.AwayScore);
        Assert.True(m.HomeWinner);
        Assert.Equal("Terminé", m.StatusText);
        Assert.Equal(2, m.Events.Count);
        Assert.True(m.Events[0].IsHome);
        Assert.Equal(MatchEventKind.Red, m.Events[1].Kind);
        Assert.False(m.Events[1].IsHome);

        var live = matches[1];
        Assert.Equal(MatchState.Live, live.State);
        Assert.Equal("67'", live.StatusText);
        Assert.Equal(TeamRef.LogoFor("1"), live.Home.Logo);
        Assert.Equal("https://a.espncdn.com/i/leaguelogos/soccer/500/23.png", LeagueCatalog.LogoFor("eng.1"));
    }

    [Fact]
    public void ScheduleScoresCanBeObjects()
    {
        const string json = """
            {"events":[{"id":"9","date":"2026-11-07T18:00Z","league":{"slug":"fra.1","abbreviation":"Ligue 1"},
              "competitions":[{"status":{"type":{"state":"post","shortDetail":"FT"}},"competitors":[
                {"homeAway":"home","score":{"value":0.0,"displayValue":"0"},"team":{"id":"172","displayName":"AJ Auxerre"}},
                {"homeAway":"away","score":{"value":1.0,"displayValue":"1"},"winner":true,"team":{"id":"6851","displayName":"Paris FC"}}]}]}]}
            """;
        using var doc = JsonDocument.Parse(json);
        var match = Assert.Single(EspnClient.ParseSchedule(doc.RootElement));
        Assert.Equal("fra.1", match.LeagueSlug);
        Assert.Equal("Ligue 1", match.LeagueName);
        Assert.Equal("0", match.HomeScore);
        Assert.Equal("1", match.AwayScore);
        Assert.True(match.AwayWinner);
        Assert.True(match.Involves("6851"));
    }

    [Fact]
    public void ParsesSummary()
    {
        const string json = """
            {"header":{"id":"401879244","league":{"slug":"eng.1","name":"English Premier League"},
               "competitions":[{"date":"2026-11-08T14:00Z","status":{"type":{"state":"post","shortDetail":"FT"}},"competitors":[
                 {"homeAway":"home","score":"2","team":{"id":"331","displayName":"Brighton & Hove Albion","logos":[{"href":"https://x/331.png"}]}},
                 {"homeAway":"away","score":"0","team":{"id":"337","displayName":"Brentford","logos":[{"href":"https://x/337.png"}]}}]}]},
             "boxscore":{"teams":[
               {"team":{"id":"331"},"statistics":[{"name":"possessionPct","label":"Possession","displayValue":"75.3"},{"name":"totalShots","displayValue":"20"}]},
               {"team":{"id":"337"},"statistics":[{"name":"possessionPct","label":"Possession","displayValue":"24.7"},{"name":"totalShots","displayValue":"9"}]}]},
             "keyEvents":[{"type":{"type":"kickoff","text":"Kickoff"}},
               {"type":{"type":"goal","text":"Goal"},"clock":{"displayValue":"15'"},"team":{"id":"331","displayName":"Brighton & Hove Albion"},"participants":[{"athlete":{"displayName":"Diego Gómez"}}]},
               {"type":{"type":"penalty---scored","text":"Penalty - Scored"},"clock":{"displayValue":"42'"},"team":{"displayName":"Brighton & Hove Albion"},"participants":[{"athlete":{"displayName":"Pascal Gross"}}]},
               {"type":{"type":"substitution","text":"Substitution"},"clock":{"displayValue":"60'"},"team":{"id":"337"},"participants":[{"athlete":{"displayName":"In"}},{"athlete":{"displayName":"Out"}}]}],
             "rosters":[{"homeAway":"away","formation":"4-4-2","team":{"displayName":"Brentford"},"roster":[{"starter":true,"jersey":"1","athlete":{"displayName":"Kelleher"},"position":{"abbreviation":"G"}}]},
                        {"homeAway":"home","formation":"4-2-3-1","team":{"displayName":"Brighton"},"roster":[]}],
             "standings":{"groups":[{"standings":{"entries":[{"team":"Arsenal","id":"359","stats":[{"name":"rank","displayValue":"1"},{"name":"points","displayValue":"27"},{"name":"gamesPlayed","displayValue":"10"}]}]}}]},
             "gameInfo":{"attendance":31629}}
            """;
        using var doc = JsonDocument.Parse(json);
        var detail = EspnClient.ParseSummary(doc.RootElement, "all");

        Assert.Equal("eng.1", detail.Match.LeagueSlug);
        Assert.Equal("https://x/331.png", detail.Match.Home.Logo);
        Assert.Equal(2, detail.Stats.Count);
        Assert.Equal("Possession (%)", detail.Stats[0].Label);
        Assert.Equal(75.3, detail.Stats[0].HomeValue);
        Assert.Equal(3, detail.Events.Count);
        Assert.Equal(MatchEventKind.Penalty, detail.Events[1].Kind);
        Assert.True(detail.Events[1].IsHome);
        Assert.Equal("In ↔ Out", detail.Events[2].Text);
        Assert.False(detail.Events[2].IsHome);
        Assert.True(detail.Lineups[0].IsHome);
        Assert.Equal("4-4-2", detail.Lineups[1].Formation);
        var row = Assert.Single(detail.Standings);
        Assert.Equal("Arsenal", row.TeamName);
        Assert.Equal(27, row.Points);
        Assert.Equal(TeamRef.LogoFor("359"), row.Logo);
        Assert.NotNull(detail.Attendance);
    }

    [Fact]
    public void ParsesStandings()
    {
        const string json = """
            {"name":"French Ligue 1","children":[{"name":"French Ligue 1 2026-27","standings":{"entries":[
              {"team":{"id":"160","displayName":"Paris Saint-Germain","logos":[{"href":"https://x/160.png"}]},
               "note":{"color":"#81D6AC","description":"Champions League"},
               "stats":[{"name":"gamesPlayed","displayValue":"10"},{"name":"wins","displayValue":"7"},{"name":"ties","displayValue":"2"},
                        {"name":"losses","displayValue":"1"},{"name":"pointsFor","displayValue":"22"},{"name":"pointsAgainst","displayValue":"10"},
                        {"name":"pointDifferential","displayValue":"+12"},{"name":"points","displayValue":"23"},{"name":"rank","displayValue":"1"}]}]}}]}
            """;
        using var doc = JsonDocument.Parse(json);
        var table = EspnClient.ParseStandings(doc.RootElement);
        var row = Assert.Single(Assert.Single(table.Groups).Rows);
        Assert.Equal(("Paris Saint-Germain", 23, 22, 10, "+12", "Champions League"),
            (row.TeamName, row.Points, row.GoalsFor, row.GoalsAgainst, row.GoalDiff, row.NoteText));
    }
}

public class ChannelMatcherTests
{
    private static MediaItem Channel(string name) => new() { Id = name, Name = name, Kind = MediaKind.Live, StreamUrl = "http://example.com/" + name };

    [Fact]
    public void FindsChannelsByBroadcaster()
    {
        var channels = new[]
        {
            Channel("FR | CANAL+ FOOT FHD"), Channel("FR | CANAL+ SPORT 360 HD"), Channel("FR | CANAL+"),
            Channel("FR | beIN SPORTS 1 HD"), Channel("UK | Sky Sports Main Event"), Channel("FR | TF1"),
        };
        var canal = ChannelMatcher.Find(channels, LeagueCatalog.Find("eng.1")!.ChannelKeywords);
        Assert.Equal(new[] { "FR | CANAL+ FOOT FHD", "FR | CANAL+ SPORT 360 HD", "FR | CANAL+" }, canal.Select(c => c.Name).ToArray());

        var bein = ChannelMatcher.Find(channels, "beIN Sports");
        Assert.Equal("FR | beIN SPORTS 1 HD", Assert.Single(bein).Name);
        Assert.Empty(ChannelMatcher.Find(channels, ""));
    }

    [Fact]
    public void NormalizesNames()
    {
        Assert.Equal("fr canal plus foot fhd", ChannelMatcher.Normalize("FR | CANAL+ FOOT FHD"));
        Assert.Equal(new[] { "l", "equipe" }, ChannelMatcher.Tokens("L'Équipe HD"));
    }
}

public class ProfileTests
{
    [Fact]
    public void HistoryResumeRules()
    {
        Assert.True(new HistoryEntry { PositionMs = 600_000, DurationMs = 6_000_000 }.CanResume);
        Assert.False(new HistoryEntry { PositionMs = 10_000, DurationMs = 6_000_000 }.CanResume);
        Assert.False(new HistoryEntry { PositionMs = 5_900_000, DurationMs = 6_000_000 }.CanResume);
        Assert.False(new HistoryEntry { PositionMs = 600_000, DurationMs = 6_000_000, IsLive = true }.CanResume);
    }

    [Fact]
    public void HomeSectionsAreCompleted()
    {
        var settings = new AppSettingsData { HomeSections = [new HomeSectionPref { Key = "movies", Visible = false }] };
        var ordered = settings.OrderedHomeSections();
        Assert.Equal("movies", ordered[0].Key);
        Assert.False(ordered[0].Visible);
        Assert.Equal(HomeSectionCatalog.All.Count, ordered.Count);
    }

    [Fact]
    public void BroadcasterOverride()
    {
        var settings = new AppSettingsData();
        Assert.Equal("Canal+", settings.BroadcasterLabel("uefa.champions"));
        settings.FootBroadcasters["uefa.champions"] = "Canal+ Foot";
        Assert.Equal("Canal+ Foot", settings.BroadcasterKeywords("uefa.champions"));
    }
}
