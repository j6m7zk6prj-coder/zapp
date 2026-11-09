using System.Collections.Concurrent;
using System.Text.Json;

namespace ZappTV.Core.Football;

/// <summary>
/// Données foot gratuites et sans clé (API publique d'ESPN) : matchs, scores en direct,
/// statistiques, compositions, classements, équipes. Réponses mises en cache quelques minutes.
/// </summary>
public sealed class EspnClient
{
    private const string Site = "https://site.api.espn.com/apis/site/v2/sports/soccer";
    private const string StandingsApi = "https://site.api.espn.com/apis/v2/sports/soccer";

    private readonly ConcurrentDictionary<string, (DateTime At, JsonElement Root)> _cache = new();

    /// <summary>Matchs d'une ligue pour un jour local (ESPN raisonne en heure de New York : on prend la veille aussi).</summary>
    public async Task<List<Match>> DayAsync(string slug, DateTime localDay, CancellationToken ct = default)
    {
        var day = localDay.Date;
        var maxAge = MaxAgeFor(day);
        var tasks = new[] { day.AddDays(-1), day }
            .Select(d => GetAsync($"{Site}/{slug}/scoreboard?dates={d:yyyyMMdd}", maxAge, ct))
            .ToArray();
        var roots = await Task.WhenAll(tasks);
        return roots
            .SelectMany(root => ParseScoreboard(root, slug))
            .Where(m => m.Date.ToLocalTime().Date == day)
            .DistinctBy(m => m.Id)
            .OrderBy(m => m.Date)
            .ToList();
    }

    /// <summary>Matchs de plusieurs ligues pour un jour (les ligues en erreur sont ignorées).</summary>
    public async Task<List<Match>> DayAsync(IEnumerable<string> slugs, DateTime localDay, CancellationToken ct = default)
    {
        var tasks = slugs.Distinct().Select(async slug =>
        {
            try { return await DayAsync(slug, localDay, ct); }
            catch (Exception) when (!ct.IsCancellationRequested) { return new List<Match>(); }
        });
        var results = await Task.WhenAll(tasks);
        return results.SelectMany(r => r).OrderBy(m => m.Date).ToList();
    }

    /// <summary>Calendrier d'une équipe, toutes compétitions (à venir ou résultats).</summary>
    public async Task<List<Match>> TeamScheduleAsync(string teamId, bool upcoming, CancellationToken ct = default)
    {
        var url = $"{Site}/all/teams/{teamId}/schedule" + (upcoming ? "?fixture=true" : "");
        var root = await GetAsync(url, TimeSpan.FromMinutes(upcoming ? 10 : 5), ct);
        return ParseSchedule(root);
    }

    public async Task<MatchDetail> SummaryAsync(string eventId, string slug, bool live, CancellationToken ct = default)
    {
        var root = await GetAsync($"{Site}/{slug}/summary?event={eventId}", TimeSpan.FromSeconds(live ? 20 : 300), ct);
        return ParseSummary(root, slug);
    }

    public async Task<LeagueTable> StandingsAsync(string slug, CancellationToken ct = default)
    {
        var root = await GetAsync($"{StandingsApi}/{slug}/standings", TimeSpan.FromMinutes(15), ct);
        return ParseStandings(root);
    }

    public async Task<List<TeamRef>> TeamsAsync(string slug, CancellationToken ct = default)
    {
        var root = await GetAsync($"{Site}/{slug}/teams", TimeSpan.FromHours(12), ct);
        var teams = new List<TeamRef>();
        if (Path(root, "sports", 0, "leagues", 0, "teams") is { ValueKind: JsonValueKind.Array } array)
        {
            foreach (var entry in array.EnumerateArray())
            {
                if (entry.TryGetProperty("team", out var team) && ParseTeam(team) is { } parsed) teams.Add(parsed);
            }
        }
        return teams.OrderBy(t => t.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    public void Invalidate() => _cache.Clear();

    private static TimeSpan MaxAgeFor(DateTime day)
    {
        var today = DateTime.Today;
        if (day >= today.AddDays(-1) && day <= today) return TimeSpan.FromSeconds(45);
        return day < today ? TimeSpan.FromMinutes(30) : TimeSpan.FromMinutes(10);
    }

    private async Task<JsonElement> GetAsync(string url, TimeSpan maxAge, CancellationToken ct)
    {
        if (_cache.TryGetValue(url, out var hit) && DateTime.UtcNow - hit.At < maxAge) return hit.Root;
        using var response = await Http.Client.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"Données foot indisponibles ({(int)response.StatusCode}).");
        var bytes = await response.Content.ReadAsByteArrayAsync(ct);
        using var document = JsonDocument.Parse(bytes);
        var root = document.RootElement.Clone();
        _cache[url] = (DateTime.UtcNow, root);
        return root;
    }

    // ── Analyse des réponses (publique pour les tests) ─────────────────────

    public static List<Match> ParseScoreboard(JsonElement root, string slug)
    {
        var league = Path(root, "leagues", 0);
        var leagueName = LeagueCatalog.NameOf(slug, Str(league, "name"));
        LeagueCatalog.RememberLogo(slug, Str(Path(league, "logos", 0), "href"));

        var matches = new List<Match>();
        if (Path(root, "events") is { ValueKind: JsonValueKind.Array } events)
        {
            foreach (var ev in events.EnumerateArray())
            {
                if (ParseEvent(ev, slug, leagueName) is { } match) matches.Add(match);
            }
        }
        return matches;
    }

    public static List<Match> ParseSchedule(JsonElement root)
    {
        var matches = new List<Match>();
        if (Path(root, "events") is not { ValueKind: JsonValueKind.Array } events) return matches;
        foreach (var ev in events.EnumerateArray())
        {
            var league = Path(ev, "league");
            var slug = Str(league, "slug") ?? "all";
            var name = LeagueCatalog.NameOf(slug, Str(league, "abbreviation") ?? Str(league, "name"));
            if (ParseEvent(ev, slug, name) is { } match) matches.Add(match);
        }
        return matches.OrderBy(m => m.Date).ToList();
    }

    public static Match? ParseEvent(JsonElement ev, string slug, string leagueName)
    {
        var id = Str(ev, "id");
        var competition = Path(ev, "competitions", 0);
        if (id is null || competition.ValueKind != JsonValueKind.Object) return null;

        JsonElement home = default, away = default;
        if (Path(competition, "competitors") is { ValueKind: JsonValueKind.Array } competitors)
        {
            foreach (var competitor in competitors.EnumerateArray())
            {
                if (Str(competitor, "homeAway") == "home") home = competitor;
                else away = competitor;
            }
        }
        if (home.ValueKind != JsonValueKind.Object || away.ValueKind != JsonValueKind.Object) return null;
        var homeTeam = ParseTeam(Path(home, "team"));
        var awayTeam = ParseTeam(Path(away, "team"));
        if (homeTeam is null || awayTeam is null) return null;

        var status = Path(ev, "status").ValueKind == JsonValueKind.Object ? Path(ev, "status") : Path(competition, "status");
        var (state, detail, clock) = ParseStatus(status);

        var events = new List<MatchEvent>();
        if (Path(competition, "details") is { ValueKind: JsonValueKind.Array } details)
        {
            foreach (var d in details.EnumerateArray())
            {
                var kind = MatchEvent.KindFrom(Str(Path(d, "type"), "text"));
                if (kind is MatchEventKind.Other or MatchEventKind.Substitution) continue;
                var who = Path(d, "athletesInvolved", 0);
                events.Add(new MatchEvent(kind, Str(Path(d, "clock"), "displayValue") ?? "",
                    Str(Path(d, "team"), "id") == homeTeam.Id, Str(who, "displayName") ?? Str(who, "shortName") ?? ""));
            }
        }

        return new Match
        {
            Id = id,
            LeagueSlug = slug,
            LeagueName = leagueName,
            Date = Date(ev, "date") ?? Date(competition, "date") ?? DateTimeOffset.MinValue,
            State = state,
            StatusDetail = detail,
            Clock = clock,
            Home = homeTeam,
            Away = awayTeam,
            HomeScore = state == MatchState.Scheduled ? null : Score(home),
            AwayScore = state == MatchState.Scheduled ? null : Score(away),
            HomeWinner = Bool(home, "winner"),
            AwayWinner = Bool(away, "winner"),
            Venue = Str(Path(competition, "venue"), "fullName"),
            Events = events,
        };
    }

    public static MatchDetail ParseSummary(JsonElement root, string slug)
    {
        var header = Path(root, "header");
        var leagueSlug = Str(Path(header, "league"), "slug") ?? slug;
        var leagueName = LeagueCatalog.NameOf(leagueSlug, Str(Path(header, "league"), "name"));

        // L'en-tête a la même forme qu'un évènement de scoreboard (avec logos[] au lieu de logo).
        var match = ParseEvent(header, leagueSlug, leagueName)
            ?? throw new InvalidOperationException("Match introuvable.");
        var homeId = match.Home.Id;

        var stats = new List<StatLine>();
        if (Path(root, "boxscore", "teams") is { ValueKind: JsonValueKind.Array } teams)
        {
            Dictionary<string, (string Label, string Value)> homeStats = new(), awayStats = new();
            foreach (var team in teams.EnumerateArray())
            {
                var isHome = Str(Path(team, "team"), "id") == homeId;
                var target = isHome ? homeStats : awayStats;
                if (Path(team, "statistics") is not { ValueKind: JsonValueKind.Array } list) continue;
                foreach (var stat in list.EnumerateArray())
                {
                    var name = Str(stat, "name");
                    if (name != null) target[name] = (Str(stat, "label") ?? name, Str(stat, "displayValue") ?? "0");
                }
            }
            string[] order =
            [
                "possessionPct", "totalShots", "shotsOnTarget", "blockedShots", "wonCorners", "saves", "totalPasses",
                "accuratePasses", "totalCrosses", "totalTackles", "interceptions", "foulsCommitted", "offsides",
                "yellowCards", "redCards",
            ];
            foreach (var key in order)
            {
                if (!homeStats.TryGetValue(key, out var h) || !awayStats.TryGetValue(key, out var a)) continue;
                stats.Add(new StatLine(key, FootFormat.StatLabel(key) ?? h.Label, h.Value, a.Value));
            }
        }

        var events = new List<MatchEvent>();
        if (Path(root, "keyEvents") is { ValueKind: JsonValueKind.Array } keyEvents)
        {
            foreach (var ke in keyEvents.EnumerateArray())
            {
                var type = Path(ke, "type");
                var kind = MatchEvent.KindFrom(Str(type, "type"), Str(type, "text"));
                if (kind == MatchEventKind.Other) continue;
                var teamName = Str(Path(ke, "team"), "displayName");
                var teamId = Str(Path(ke, "team"), "id");
                var isHome = teamId != null ? teamId == homeId : teamName == match.Home.Name;
                var names = new List<string>();
                if (Path(ke, "participants") is { ValueKind: JsonValueKind.Array } participants)
                {
                    foreach (var p in participants.EnumerateArray())
                    {
                        if (Str(Path(p, "athlete"), "displayName") is { } n) names.Add(n);
                    }
                }
                var text = kind == MatchEventKind.Substitution && names.Count >= 2
                    ? $"{names[0]} ↔ {names[1]}"
                    : names.Count > 0 ? names[0] : Str(ke, "shortText") ?? Str(type, "text") ?? "";
                events.Add(new MatchEvent(kind, Str(Path(ke, "clock"), "displayValue") ?? "", isHome, text));
            }
        }

        var lineups = new List<Lineup>();
        if (Path(root, "rosters") is { ValueKind: JsonValueKind.Array } rosters)
        {
            foreach (var roster in rosters.EnumerateArray())
            {
                var players = new List<LineupPlayer>();
                if (Path(roster, "roster") is { ValueKind: JsonValueKind.Array } list)
                {
                    foreach (var p in list.EnumerateArray())
                    {
                        players.Add(new LineupPlayer(
                            Str(p, "jersey") ?? "",
                            Str(Path(p, "athlete"), "displayName") ?? "?",
                            Str(Path(p, "position"), "abbreviation") ?? "",
                            Bool(p, "starter"), Bool(p, "subbedIn"), Bool(p, "subbedOut")));
                    }
                }
                var formation = Path(roster, "formation");
                lineups.Add(new Lineup(
                    Str(Path(roster, "team"), "displayName") ?? "",
                    Str(roster, "homeAway") == "home",
                    formation.ValueKind == JsonValueKind.String ? formation.GetString() : Str(formation, "summary") ?? Str(formation, "name"),
                    players));
            }
            lineups.Sort((a, b) => b.IsHome.CompareTo(a.IsHome));
        }

        var standings = new List<StandingRow>();
        if (Path(root, "standings", "groups") is { ValueKind: JsonValueKind.Array } groups)
        {
            foreach (var group in groups.EnumerateArray())
            {
                var rows = ParseEntries(Path(group, "standings", "entries"));
                if (rows.Any(r => r.TeamId == homeId || r.TeamId == match.Away.Id || r.TeamName == match.Home.Name || r.TeamName == match.Away.Name))
                {
                    standings = rows;
                    break;
                }
                if (standings.Count == 0) standings = rows;
            }
        }

        var attendance = Path(root, "gameInfo", "attendance");
        var attendanceText = attendance.ValueKind == JsonValueKind.Number && attendance.GetInt32() > 0
            ? attendance.GetInt32().ToString("N0", FootFormat.French)
            : null;

        return new MatchDetail(match, stats, events, lineups, standings, attendanceText);
    }

    public static LeagueTable ParseStandings(JsonElement root)
    {
        var groups = new List<(string, IReadOnlyList<StandingRow>)>();
        if (Path(root, "children") is { ValueKind: JsonValueKind.Array } children)
        {
            foreach (var child in children.EnumerateArray())
            {
                var rows = ParseEntries(Path(child, "standings", "entries"));
                if (rows.Count > 0) groups.Add((Str(child, "name") ?? "", rows));
            }
        }
        return new LeagueTable(Str(root, "name") ?? "Classement", groups);
    }

    private static List<StandingRow> ParseEntries(JsonElement entries)
    {
        var rows = new List<StandingRow>();
        if (entries.ValueKind != JsonValueKind.Array) return rows;
        foreach (var entry in entries.EnumerateArray())
        {
            var team = Path(entry, "team");
            string teamId, teamName;
            string? logo = null;
            if (team.ValueKind == JsonValueKind.Object)
            {
                teamId = Str(team, "id") ?? "";
                teamName = Str(team, "displayName") ?? Str(team, "name") ?? "";
                logo = Str(Path(team, "logos", 0), "href") ?? (teamId.Length > 0 ? TeamRef.LogoFor(teamId) : null);
            }
            else
            {
                teamId = Str(entry, "id") ?? "";
                teamName = team.ValueKind == JsonValueKind.String ? team.GetString() ?? "" : "";
                if (teamId.Length > 0) logo = TeamRef.LogoFor(teamId);
            }

            var stats = new Dictionary<string, string>();
            if (Path(entry, "stats") is { ValueKind: JsonValueKind.Array } list)
            {
                foreach (var s in list.EnumerateArray())
                {
                    if (Str(s, "name") is { } name) stats[name] = Str(s, "displayValue") ?? "";
                }
            }
            int I(string key) => (int)FootFormat.Number(stats.GetValueOrDefault(key));
            var note = Path(entry, "note");
            rows.Add(new StandingRow(
                I("rank") is > 0 and var rank ? rank : rows.Count + 1,
                teamId, teamName, logo,
                I("gamesPlayed"), I("wins"), I("ties"), I("losses"),
                I("pointsFor"), I("pointsAgainst"),
                stats.GetValueOrDefault("pointDifferential") ?? "",
                I("points"),
                Str(note, "color"), Str(note, "description")));
        }
        return rows.OrderBy(r => r.Rank).ToList();
    }

    private static TeamRef? ParseTeam(JsonElement team)
    {
        var id = Str(team, "id");
        if (id is null) return null;
        var name = Str(team, "displayName") ?? Str(team, "name") ?? id;
        var logo = Str(team, "logo") ?? Str(Path(team, "logos", 0), "href") ?? TeamRef.LogoFor(id);
        return new TeamRef(id, name, Str(team, "shortDisplayName") ?? name, Str(team, "abbreviation") ?? "", logo, Str(team, "color"));
    }

    private static (MatchState State, string Detail, string? Clock) ParseStatus(JsonElement status)
    {
        var type = Path(status, "type");
        var state = Str(type, "state");
        var name = Str(type, "name") ?? "";
        var detail = Str(type, "shortDetail") ?? Str(type, "detail") ?? "";
        var clock = Str(status, "displayClock");
        var result = state switch
        {
            "in" => MatchState.Live,
            "post" => MatchState.Finished,
            _ => MatchState.Scheduled,
        };
        if (name.Contains("POSTPONED") || name.Contains("CANCELED") || name.Contains("SUSPENDED") || name.Contains("ABANDONED"))
            result = MatchState.Postponed;
        if (result == MatchState.Live && (name.Contains("HALFTIME") || detail == "HT")) detail = "HT";
        return (result, detail, result == MatchState.Live && detail != "HT" ? clock : null);
    }

    private static string? Score(JsonElement competitor)
    {
        if (!competitor.TryGetProperty("score", out var score)) return null;
        return score.ValueKind switch
        {
            JsonValueKind.String => score.GetString(),
            JsonValueKind.Number => score.GetRawText(),
            JsonValueKind.Object => Str(score, "displayValue"),
            _ => null,
        };
    }

    // ── Accès tolérant au JSON ─────────────────────────────────────────────

    public static JsonElement Path(JsonElement element, params object[] path)
    {
        var current = element;
        foreach (var step in path)
        {
            if (step is string key)
            {
                if (current.ValueKind != JsonValueKind.Object || !current.TryGetProperty(key, out current)) return default;
            }
            else if (step is int index)
            {
                if (current.ValueKind != JsonValueKind.Array || current.GetArrayLength() <= index) return default;
                current = current[index];
            }
        }
        return current;
    }

    private static string? Str(JsonElement element, string property) => XJson.Str(element, property);

    private static bool Bool(JsonElement element, string property) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.True;

    private static DateTimeOffset? Date(JsonElement element, string property) =>
        Str(element, property) is { } text && DateTimeOffset.TryParse(text, System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : null;
}
