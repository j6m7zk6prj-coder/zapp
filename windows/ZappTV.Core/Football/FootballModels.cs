using System.Globalization;
using System.Text;

namespace ZappTV.Core.Football;

public sealed record TeamRef(string Id, string Name, string ShortName, string Abbr, string? Logo, string? Color)
{
    public static string LogoFor(string id) => $"https://a.espncdn.com/i/teamlogos/soccer/500/{id}.png";
}

public enum MatchState { Scheduled, Live, Finished, Postponed }

public sealed record Match
{
    public required string Id { get; init; }
    public required string LeagueSlug { get; init; }
    public string LeagueName { get; init; } = "";
    public DateTimeOffset Date { get; init; }
    public MatchState State { get; init; }
    /// <summary>« FT », « HT », « 67' », « Postponed »…</summary>
    public string StatusDetail { get; init; } = "";
    public string? Clock { get; init; }
    public required TeamRef Home { get; init; }
    public required TeamRef Away { get; init; }
    public string? HomeScore { get; init; }
    public string? AwayScore { get; init; }
    public bool HomeWinner { get; init; }
    public bool AwayWinner { get; init; }
    public string? Venue { get; init; }
    public IReadOnlyList<MatchEvent> Events { get; init; } = [];

    public bool Involves(string teamId) => Home.Id == teamId || Away.Id == teamId;

    /// <summary>Statut lisible en français.</summary>
    public string StatusText => State switch
    {
        MatchState.Live => StatusDetail is "HT" or "Halftime" ? "Mi-temps" : (Clock ?? StatusDetail),
        MatchState.Finished => StatusDetail.Contains("Pen", StringComparison.OrdinalIgnoreCase) ? "Terminé (t.a.b.)"
            : StatusDetail.Contains("AET", StringComparison.OrdinalIgnoreCase) ? "Terminé (a.p.)" : "Terminé",
        MatchState.Postponed => StatusDetail.Contains("Cancel", StringComparison.OrdinalIgnoreCase) ? "Annulé" : "Reporté",
        _ => FootFormat.Kickoff(Date),
    };
}

public enum MatchEventKind { Goal, Penalty, OwnGoal, MissedPenalty, Yellow, Red, Substitution, Other }

public sealed record MatchEvent(MatchEventKind Kind, string Clock, bool IsHome, string Text)
{
    public static MatchEventKind KindFrom(string? type, string? text = null)
    {
        var t = (type ?? text ?? "").ToLowerInvariant();
        if (t.Contains("own")) return MatchEventKind.OwnGoal;
        if (t.Contains("penalty") && (t.Contains("miss") || t.Contains("saved"))) return MatchEventKind.MissedPenalty;
        if (t.Contains("penalty")) return MatchEventKind.Penalty;
        if (t.Contains("goal")) return MatchEventKind.Goal;
        if (t.Contains("red")) return MatchEventKind.Red;
        if (t.Contains("yellow")) return MatchEventKind.Yellow;
        if (t.Contains("substitution")) return MatchEventKind.Substitution;
        return MatchEventKind.Other;
    }

    public string Icon => Kind switch
    {
        MatchEventKind.Goal or MatchEventKind.Penalty => "⚽",
        MatchEventKind.OwnGoal => "⚽ (c.s.c.)",
        MatchEventKind.MissedPenalty => "✗ pén.",
        MatchEventKind.Yellow => "🟨",
        MatchEventKind.Red => "🟥",
        MatchEventKind.Substitution => "⇄",
        _ => "•",
    };

    public bool IsGoal => Kind is MatchEventKind.Goal or MatchEventKind.Penalty or MatchEventKind.OwnGoal;
}

public sealed record StatLine(string Key, string Label, string Home, string Away)
{
    public double HomeValue => FootFormat.Number(Home);
    public double AwayValue => FootFormat.Number(Away);
}

public sealed record LineupPlayer(string Jersey, string Name, string Position, bool Starter, bool SubbedIn, bool SubbedOut);

public sealed record Lineup(string TeamName, bool IsHome, string? Formation, IReadOnlyList<LineupPlayer> Players);

public sealed record StandingRow(
    int Rank, string TeamId, string TeamName, string? Logo, int Played, int Won, int Drawn, int Lost,
    int GoalsFor, int GoalsAgainst, string GoalDiff, int Points, string? NoteColor, string? NoteText);

public sealed record LeagueTable(string Title, IReadOnlyList<(string Group, IReadOnlyList<StandingRow> Rows)> Groups);

public sealed record MatchDetail(
    Match Match,
    IReadOnlyList<StatLine> Stats,
    IReadOnlyList<MatchEvent> Events,
    IReadOnlyList<Lineup> Lineups,
    IReadOnlyList<StandingRow> Standings,
    string? Attendance);

/// <summary>Une compétition proposée dans l'app, avec son diffuseur habituel en France.</summary>
public sealed record League(string Slug, string Name, string Area, string Broadcaster, string ChannelKeywords)
{
    public string Logo => LeagueCatalog.LogoFor(Slug);
}

public static class LeagueCatalog
{
    // Diffuseurs en France pour la saison 2026-2027 (source : Maxifoot, 6 août 2026). Modifiables dans les réglages.
    private const string CanalKeywords = "Canal+ Foot, Canal+ Sport 360, Canal+ Sport, Canal+ Premier League, Canal+";
    private const string BeinKeywords = "beIN Sports 1, beIN Sports 2, beIN Sports 3, beIN Sports";
    private const string DaznKeywords = "DAZN 1, DAZN 2, DAZN";

    public static readonly IReadOnlyList<League> All =
    [
        new("fra.1", "Ligue 1", "France", "Ligue 1+", "Ligue 1+, Ligue 1"),
        new("fra.2", "Ligue 2", "France", "beIN Sports", BeinKeywords),
        new("fra.coupe_de_france", "Coupe de France", "France", "beIN Sports", BeinKeywords),
        new("uefa.champions", "Ligue des champions", "Europe", "Canal+", CanalKeywords),
        new("uefa.europa", "Ligue Europa", "Europe", "Canal+", CanalKeywords),
        new("uefa.europa.conf", "Ligue Conférence", "Europe", "Canal+", CanalKeywords),
        new("uefa.nations", "Ligue des nations", "Europe", "L'Équipe", "L'Equipe"),
        new("eng.1", "Premier League", "Angleterre", "Canal+", CanalKeywords),
        new("eng.2", "Championship", "Angleterre", "", ""),
        new("eng.fa", "FA Cup", "Angleterre", "beIN Sports", BeinKeywords),
        new("eng.league_cup", "Carabao Cup", "Angleterre", "", ""),
        new("esp.1", "LaLiga", "Espagne", "DAZN / Disney+", DaznKeywords + ", Disney+"),
        new("esp.copa_del_rey", "Coupe du Roi", "Espagne", "DAZN", DaznKeywords),
        new("ita.1", "Serie A", "Italie", "DAZN", DaznKeywords),
        new("ita.coppa_italia", "Coupe d'Italie", "Italie", "DAZN", DaznKeywords),
        new("ger.1", "Bundesliga", "Allemagne", "beIN Sports", BeinKeywords),
        new("ger.dfb_pokal", "Coupe d'Allemagne", "Allemagne", "", ""),
        new("por.1", "Liga Portugal", "Portugal", "", ""),
        new("ned.1", "Eredivisie", "Pays-Bas", "", ""),
        new("bel.1", "Pro League", "Belgique", "", ""),
        new("tur.1", "Süper Lig", "Turquie", "", ""),
        new("sco.1", "Scottish Premiership", "Écosse", "", ""),
        new("ksa.1", "Saudi Pro League", "Arabie saoudite", "", ""),
        new("usa.1", "MLS", "États-Unis", "Apple TV", "Apple TV, MLS"),
        new("bra.1", "Brasileirão", "Brésil", "", ""),
        new("arg.1", "Liga Profesional", "Argentine", "", ""),
        new("mex.1", "Liga MX", "Mexique", "", ""),
        new("conmebol.libertadores", "Copa Libertadores", "Amérique du Sud", "", ""),
        new("fifa.worldq.uefa", "Qualifs Coupe du monde (Europe)", "International", "", ""),
        new("fifa.friendly", "Matchs amicaux internationaux", "International", "", ""),
        new("caf.nations", "Coupe d'Afrique des nations", "International", "", ""),
        new("fifa.world", "Coupe du monde", "International", "", ""),
        new("uefa.euro", "Euro", "International", "", ""),
    ];

    public static readonly IReadOnlyList<string> DefaultFollowed = ["fra.1", "uefa.champions", "eng.1"];

    private static readonly Dictionary<string, League> BySlug = All.ToDictionary(l => l.Slug);
    private static readonly Dictionary<string, string> Logos = new();

    public static League? Find(string slug) => BySlug.GetValueOrDefault(slug);

    public static string NameOf(string slug, string? fallback = null) =>
        Find(slug)?.Name ?? (string.IsNullOrWhiteSpace(fallback) ? slug : fallback);

    /// <summary>Logo renvoyé par ESPN (mémorisé au premier chargement de la ligue).</summary>
    public static void RememberLogo(string slug, string? url)
    {
        if (!string.IsNullOrEmpty(url)) lock (Logos) Logos[slug] = url;
    }

    public static string LogoFor(string slug)
    {
        lock (Logos) return Logos.GetValueOrDefault(slug) ?? "";
    }
}

public static class FootFormat
{
    public static readonly CultureInfo French = CultureInfo.GetCultureInfo("fr-FR");

    public static string Kickoff(DateTimeOffset date)
    {
        var local = date.ToLocalTime();
        var today = DateTime.Today;
        var day = local.Date == today ? "Aujourd'hui"
            : local.Date == today.AddDays(1) ? "Demain"
            : local.Date == today.AddDays(-1) ? "Hier"
            : local.ToString("ddd d MMM", French);
        return $"{day} · {local:HH:mm}";
    }

    public static string DayTitle(DateTime day)
    {
        var today = DateTime.Today;
        if (day == today) return "Aujourd'hui";
        if (day == today.AddDays(1)) return "Demain";
        if (day == today.AddDays(-1)) return "Hier";
        var text = day.ToString("dddd d MMMM", French);
        return char.ToUpper(text[0], French) + text[1..];
    }

    public static double Number(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return 0;
        var cleaned = text.Replace("%", "").Replace(',', '.').Trim();
        return double.TryParse(cleaned, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : 0;
    }

    /// <summary>Libellés français des statistiques ESPN (null = statistique non affichée).</summary>
    public static string? StatLabel(string key) => key switch
    {
        "possessionPct" => "Possession (%)",
        "totalShots" => "Tirs",
        "shotsOnTarget" => "Tirs cadrés",
        "blockedShots" => "Tirs contrés",
        "wonCorners" => "Corners",
        "foulsCommitted" => "Fautes",
        "offsides" => "Hors-jeu",
        "yellowCards" => "Cartons jaunes",
        "redCards" => "Cartons rouges",
        "saves" => "Arrêts",
        "totalPasses" => "Passes",
        "accuratePasses" => "Passes réussies",
        "totalCrosses" => "Centres",
        "totalTackles" => "Tacles",
        "interceptions" => "Interceptions",
        "totalClearance" => "Dégagements",
        _ => null,
    };
}

/// <summary>Trouve dans la playlist les chaînes qui correspondent à un diffuseur (« Canal+ Foot » → « FR | CANAL+ FOOT FHD »).</summary>
public static class ChannelMatcher
{
    private static readonly HashSet<string> Noise =
    [
        "fr", "france", "hd", "fhd", "uhd", "sd", "4k", "hevc", "h265", "raw", "vip", "backup", "multi", "tv", "live", "the",
    ];

    public static string Normalize(string text)
    {
        var lowered = text.ToLowerInvariant().Replace("+", " plus ");
        var decomposed = lowered.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            var category = CharUnicodeInfo.GetUnicodeCategory(c);
            if (category == UnicodeCategory.NonSpacingMark) continue;
            builder.Append(char.IsLetterOrDigit(c) ? c : ' ');
        }
        return string.Join(' ', builder.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    public static string[] Tokens(string text) =>
        Normalize(text).Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(t => !Noise.Contains(t)).ToArray();

    public static IReadOnlyList<string> SplitKeywords(string? keywords) =>
        (keywords ?? "").Split([',', ';', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    /// <summary>Chaînes en direct correspondant aux mots-clés, dans l'ordre des mots-clés puis du plus court au plus long.</summary>
    public static List<MediaItem> Find(IEnumerable<MediaItem> channels, string? keywords, int limit = 12)
    {
        var patterns = SplitKeywords(keywords).Select(Tokens).Where(t => t.Length > 0).ToList();
        if (patterns.Count == 0) return [];

        var results = new List<(MediaItem Item, int Pattern, int Length)>();
        foreach (var channel in channels)
        {
            if (channel.Kind != MediaKind.Live) continue;
            var words = new HashSet<string>(Tokens(channel.Name));
            for (var p = 0; p < patterns.Count; p++)
            {
                if (patterns[p].All(words.Contains))
                {
                    results.Add((channel, p, channel.Name.Length));
                    break;
                }
            }
        }
        return results
            .OrderBy(r => r.Pattern)
            .ThenBy(r => r.Length)
            .Select(r => r.Item)
            .DistinctBy(i => i.Id)
            .Take(limit)
            .ToList();
    }
}
