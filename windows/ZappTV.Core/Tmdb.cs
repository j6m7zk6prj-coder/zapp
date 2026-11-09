using System.Collections.Concurrent;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ZappTV.Core.Tmdb;

public enum TmdbKind { Movie, Tv }

public sealed record TmdbCast(string Name, string? Character, string? Photo);

/// <summary>Fiche enrichie d'un film ou d'une série (The Movie Database).</summary>
public sealed record TmdbInfo
{
    public int Id { get; init; }
    public TmdbKind Kind { get; init; }
    public string Title { get; init; } = "";
    public string? OriginalTitle { get; init; }
    public int? Year { get; init; }
    public double? Rating { get; init; }
    public int? Votes { get; init; }
    public string? Overview { get; init; }
    public string? Tagline { get; init; }
    public string? Poster { get; init; }
    public string? Backdrop { get; init; }
    public string? Logo { get; init; }
    public List<string> Genres { get; init; } = [];
    public int? RuntimeMinutes { get; init; }
    public int? Seasons { get; init; }
    public string? Director { get; init; }
    public List<TmdbCast> Cast { get; init; } = [];
    public string? TrailerKey { get; init; }

    public string? TrailerUrl => TrailerKey is null ? null : $"https://www.youtube.com/watch?v={TrailerKey}";

    public string Runtime => RuntimeMinutes is int m && m > 0
        ? (m >= 60 ? $"{m / 60} h {m % 60:00}" : $"{m} min")
        : "";
}

/// <summary>Titre en tendance cette semaine.</summary>
public sealed record TmdbTrend(int Id, TmdbKind Kind, string Title, string? OriginalTitle, int? Year, string? Backdrop, string? Poster, double? Rating, string? Overview);

/// <summary>Nettoie les noms des playlists (« FR - Avatar (2009) [4K] » → « Avatar », 2009).</summary>
public static partial class TitleCleaner
{
    [GeneratedRegex(@"^\s*((\[[^\]]*\]|\|[^|]*\||\b[A-Z0-9]{2,4}\s*(?:\s[-–]\s|[:|•])\s*|[A-Z]{2}\s*\|\s*)\s*)+")]
    private static partial Regex Prefix();

    [GeneratedRegex(@"[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]")]
    private static partial Regex YearInBrackets();

    [GeneratedRegex(@"[\s\-–]((?:19|20)\d{2})\s*$")]
    private static partial Regex TrailingYear();

    [GeneratedRegex(@"\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}")]
    private static partial Regex Brackets();

    [GeneratedRegex(@"\bS\d{1,2}\s*E\d{1,3}\b.*$", RegexOptions.IgnoreCase)]
    private static partial Regex Episode();

    [GeneratedRegex(@"\b(4K|UHD|FHD|HD|SD|HDR|HDR10|1080p|720p|2160p|480p|MULTI|VOSTFR|VOST|VFF|VFQ|VFI|VF|VO|TRUEFRENCH|FRENCH|SUBFRENCH|x264|x265|h264|h265|HEVC|WEB-?DL|WEBRIP|BLURAY|BDRIP|DVDRIP|AC3|DTS|ATMOS|10bit)\b", RegexOptions.IgnoreCase)]
    private static partial Regex Tags();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex Spaces();

    public static (string Title, int? Year) Clean(string name)
    {
        var text = name.Replace('_', ' ').Replace('.', ' ').Trim();
        text = Prefix().Replace(text, "");
        int? year = null;
        var match = YearInBrackets().Match(text);
        if (match.Success) year = int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
        text = Brackets().Replace(text, " ");
        text = Episode().Replace(text, " ");
        text = Tags().Replace(text, " ");
        text = Spaces().Replace(text, " ").Trim(' ', '-', '|', ':', '•', '–');
        if (year is null)
        {
            var trailing = TrailingYear().Match(text);
            // On garde « 1917 » ou « 2012 » quand le titre n'est qu'une année.
            if (trailing.Success && trailing.Index > 0)
            {
                year = int.Parse(trailing.Groups[1].Value, CultureInfo.InvariantCulture);
                text = text[..trailing.Index].Trim(' ', '-', '–');
            }
        }
        return (text.Length > 0 ? text : name.Trim(), year);
    }

    /// <summary>Clé de comparaison (minuscules, sans accents ni ponctuation).</summary>
    public static string Key(string title)
    {
        var normalized = title.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(normalized.Length);
        foreach (var c in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            if (char.IsLetterOrDigit(c)) builder.Append(c);
            else if (builder.Length > 0 && builder[^1] != ' ') builder.Append(' ');
        }
        var key = builder.ToString().Trim();
        return key.StartsWith("the ") ? key[4..] : key;
    }
}

/// <summary>
/// Client TMDB (clé gratuite fournie par l'utilisateur) : recherche, fiches complètes, tendances.
/// Les correspondances titre → fiche sont gardées sur disque pour ne pas refaire les recherches.
/// </summary>
public sealed class TmdbClient
{
    private const string Api = "https://api.themoviedb.org/3";
    private const string Images = "https://image.tmdb.org/t/p/";

    private readonly string _key;
    private readonly ConcurrentDictionary<string, Task<TmdbInfo?>> _pending = new();
    private readonly TmdbCache _cache;

    public TmdbClient(string key, TmdbCache? cache = null)
    {
        _key = key.Trim();
        _cache = cache ?? new TmdbCache(null);
    }

    public bool HasKey => _key.Length > 0;

    /// <summary>Jeton v4 (« eyJ… ») envoyé en en-tête, clé v3 en paramètre.</summary>
    private bool IsBearer => _key.StartsWith("eyJ", StringComparison.Ordinal);

    public async Task<bool> ValidateAsync(CancellationToken ct = default)
    {
        try
        {
            await GetAsync("/configuration", ct);
            return true;
        }
        catch (TmdbException)
        {
            return false;
        }
    }

    /// <summary>Fiche correspondant à un élément de playlist (null si introuvable).</summary>
    public Task<TmdbInfo?> FindAsync(string name, MediaKind kind, CancellationToken ct = default)
    {
        if (!HasKey || kind == MediaKind.Live) return Task.FromResult<TmdbInfo?>(null);
        var cacheKey = $"{(kind == MediaKind.Series ? "tv" : "movie")}:{TitleCleaner.Key(name)}";
        if (_cache.TryGet(cacheKey, out var cached)) return Task.FromResult(cached);
        return _pending.GetOrAdd(cacheKey, _ => FindUncachedAsync(name, kind, cacheKey, ct));
    }

    private async Task<TmdbInfo?> FindUncachedAsync(string name, MediaKind kind, string cacheKey, CancellationToken ct)
    {
        try
        {
            var (title, year) = TitleCleaner.Clean(name);
            var tmdbKind = kind == MediaKind.Series ? TmdbKind.Tv : TmdbKind.Movie;
            var id = await SearchAsync(title, year, tmdbKind, ct);
            if (id is null && year != null) id = await SearchAsync(title, null, tmdbKind, ct);
            var info = id is null ? null : await DetailsAsync(id.Value, tmdbKind, ct);
            _cache.Set(cacheKey, info);
            return info;
        }
        finally
        {
            _pending.TryRemove(cacheKey, out _);
        }
    }

    private async Task<int?> SearchAsync(string title, int? year, TmdbKind kind, CancellationToken ct)
    {
        var path = kind == TmdbKind.Movie ? "/search/movie" : "/search/tv";
        var query = $"query={Uri.EscapeDataString(title)}&language=fr-FR&include_adult=false";
        if (year != null) query += kind == TmdbKind.Movie ? $"&year={year}" : $"&first_air_date_year={year}";
        var root = await GetAsync($"{path}?{query}", ct);
        return ParseSearch(root, title);
    }

    public async Task<TmdbInfo> DetailsAsync(int id, TmdbKind kind, CancellationToken ct = default)
    {
        var path = kind == TmdbKind.Movie ? "movie" : "tv";
        var root = await GetAsync($"/{path}/{id}?language=fr-FR&append_to_response=credits,videos,images&include_image_language=fr,en,null&include_video_language=fr,en", ct);
        return ParseDetails(root, kind);
    }

    public async Task<List<TmdbTrend>> TrendingAsync(int pages = 3, CancellationToken ct = default)
    {
        if (!HasKey) return [];
        var list = new List<TmdbTrend>();
        for (var page = 1; page <= pages; page++)
        {
            var root = await GetAsync($"/trending/all/week?language=fr-FR&page={page}", ct);
            list.AddRange(ParseTrending(root));
        }
        return list;
    }

    private async Task<JsonElement> GetAsync(string pathAndQuery, CancellationToken ct)
    {
        var url = Api + pathAndQuery;
        if (!IsBearer) url += (url.Contains('?') ? "&" : "?") + "api_key=" + Uri.EscapeDataString(_key);
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (IsBearer) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _key);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await Http.Client.SendAsync(request, ct);
        if ((int)response.StatusCode == 401) throw new TmdbException("Clé TMDB refusée : vérifie-la dans les réglages.");
        if (!response.IsSuccessStatusCode) throw new TmdbException($"TMDB indisponible ({(int)response.StatusCode}).");
        var bytes = await response.Content.ReadAsByteArrayAsync(ct);
        using var document = JsonDocument.Parse(bytes);
        return document.RootElement.Clone();
    }

    // ── Analyse des réponses (publique pour les tests) ─────────────────────

    public static string? Image(string? path, string size) =>
        string.IsNullOrEmpty(path) ? null : Images + size + path;

    /// <summary>Meilleur résultat : titre identique en priorité, sinon le plus populaire.</summary>
    public static int? ParseSearch(JsonElement root, string title)
    {
        if (!root.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array) return null;
        var key = TitleCleaner.Key(title);
        int? first = null;
        foreach (var result in results.EnumerateArray())
        {
            if (!result.TryGetProperty("id", out var idElement) || !idElement.TryGetInt32(out var id)) continue;
            first ??= id;
            var names = new[] { Str(result, "title"), Str(result, "name"), Str(result, "original_title"), Str(result, "original_name") };
            if (names.Any(n => n != null && TitleCleaner.Key(n) == key)) return id;
        }
        return first;
    }

    public static TmdbInfo ParseDetails(JsonElement root, TmdbKind kind)
    {
        var title = Str(root, kind == TmdbKind.Movie ? "title" : "name") ?? "";
        var original = Str(root, kind == TmdbKind.Movie ? "original_title" : "original_name");
        var date = Str(root, kind == TmdbKind.Movie ? "release_date" : "first_air_date");
        int? runtime = kind == TmdbKind.Movie
            ? Int(root, "runtime")
            : root.TryGetProperty("episode_run_time", out var ert) && ert.ValueKind == JsonValueKind.Array && ert.GetArrayLength() > 0 && ert[0].TryGetInt32(out var r) ? r : null;

        var genres = new List<string>();
        if (root.TryGetProperty("genres", out var g) && g.ValueKind == JsonValueKind.Array)
            genres.AddRange(g.EnumerateArray().Select(x => Str(x, "name")).OfType<string>());

        var cast = new List<TmdbCast>();
        string? director = null;
        if (root.TryGetProperty("credits", out var credits))
        {
            if (credits.TryGetProperty("cast", out var c) && c.ValueKind == JsonValueKind.Array)
            {
                cast.AddRange(c.EnumerateArray().Take(15)
                    .Select(x => new TmdbCast(Str(x, "name") ?? "", Str(x, "character"), Image(Str(x, "profile_path"), "w185")))
                    .Where(x => x.Name.Length > 0));
            }
            if (credits.TryGetProperty("crew", out var crew) && crew.ValueKind == JsonValueKind.Array)
                director = crew.EnumerateArray().Where(x => Str(x, "job") == "Director").Select(x => Str(x, "name")).FirstOrDefault();
        }
        if (director is null && root.TryGetProperty("created_by", out var creators) && creators.ValueKind == JsonValueKind.Array)
            director = string.Join(", ", creators.EnumerateArray().Select(x => Str(x, "name")).OfType<string>()) is { Length: > 0 } names ? names : null;

        string? trailer = null;
        if (root.TryGetProperty("videos", out var videos) && videos.TryGetProperty("results", out var vr) && vr.ValueKind == JsonValueKind.Array)
        {
            trailer = vr.EnumerateArray()
                .Where(v => Str(v, "site") == "YouTube" && Str(v, "type") is "Trailer" or "Teaser")
                .OrderBy(v => Str(v, "iso_639_1") == "fr" ? 0 : 1)
                .ThenBy(v => Str(v, "type") == "Trailer" ? 0 : 1)
                .ThenByDescending(v => v.TryGetProperty("official", out var o) && o.ValueKind == JsonValueKind.True)
                .Select(v => Str(v, "key"))
                .FirstOrDefault();
        }

        string? logo = null;
        if (root.TryGetProperty("images", out var images) && images.TryGetProperty("logos", out var logos) && logos.ValueKind == JsonValueKind.Array)
        {
            logo = logos.EnumerateArray()
                .OrderBy(l => Str(l, "iso_639_1") switch { "fr" => 0, "en" => 1, _ => 2 })
                .Select(l => Str(l, "file_path"))
                .FirstOrDefault(p => p != null && !p.EndsWith(".svg", StringComparison.OrdinalIgnoreCase));
        }

        return new TmdbInfo
        {
            Id = Int(root, "id") ?? 0,
            Kind = kind,
            Title = title,
            OriginalTitle = original != title ? original : null,
            Year = date is { Length: >= 4 } && int.TryParse(date[..4], out var y) ? y : null,
            Rating = Dbl(root, "vote_average") is double rating && rating > 0 ? Math.Round(rating, 1) : null,
            Votes = Int(root, "vote_count"),
            Overview = Str(root, "overview") is { Length: > 0 } o2 ? o2 : null,
            Tagline = Str(root, "tagline") is { Length: > 0 } t ? t : null,
            Poster = Image(Str(root, "poster_path"), "w500"),
            Backdrop = Image(Str(root, "backdrop_path"), "w1280"),
            Logo = Image(logo, "w500"),
            Genres = genres,
            RuntimeMinutes = runtime is > 0 ? runtime : null,
            Seasons = kind == TmdbKind.Tv ? Int(root, "number_of_seasons") : null,
            Director = director,
            Cast = cast,
            TrailerKey = trailer,
        };
    }

    public static List<TmdbTrend> ParseTrending(JsonElement root)
    {
        var list = new List<TmdbTrend>();
        if (!root.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array) return list;
        foreach (var r in results.EnumerateArray())
        {
            var type = Str(r, "media_type");
            if (type is not ("movie" or "tv")) continue;
            var kind = type == "movie" ? TmdbKind.Movie : TmdbKind.Tv;
            var date = Str(r, kind == TmdbKind.Movie ? "release_date" : "first_air_date");
            list.Add(new TmdbTrend(
                Int(r, "id") ?? 0,
                kind,
                Str(r, kind == TmdbKind.Movie ? "title" : "name") ?? "",
                Str(r, kind == TmdbKind.Movie ? "original_title" : "original_name"),
                date is { Length: >= 4 } && int.TryParse(date[..4], out var y) ? y : null,
                Image(Str(r, "backdrop_path"), "w1280"),
                Image(Str(r, "poster_path"), "w500"),
                Dbl(r, "vote_average") is double v && v > 0 ? Math.Round(v, 1) : null,
                Str(r, "overview")));
        }
        return list;
    }

    private static string? Str(JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int? Int(JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i) ? i : null;

    private static double? Dbl(JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
}

public sealed class TmdbException(string message) : Exception(message);

/// <summary>Correspondances titre → fiche, sauvegardées sur disque (30 jours, 3 jours pour « introuvable »).</summary>
public sealed class TmdbCache
{
    public sealed class Entry
    {
        public TmdbInfo? Info { get; set; }
        public DateTimeOffset At { get; set; }
    }

    private readonly string? _path;
    private readonly Dictionary<string, Entry> _entries;
    private readonly Lock _lock = new();
    private Timer? _saveTimer;

    public TmdbCache(string? path)
    {
        _path = path;
        _entries = path is null ? new() : JsonFile.Load<Dictionary<string, Entry>>(path) ?? new();
    }

    public bool TryGet(string key, out TmdbInfo? info)
    {
        lock (_lock)
        {
            info = null;
            if (!_entries.TryGetValue(key, out var entry)) return false;
            var maxAge = entry.Info is null ? TimeSpan.FromDays(3) : TimeSpan.FromDays(30);
            if (DateTimeOffset.Now - entry.At > maxAge) return false;
            info = entry.Info;
            return true;
        }
    }

    public void Set(string key, TmdbInfo? info)
    {
        lock (_lock)
        {
            _entries[key] = new Entry { Info = info, At = DateTimeOffset.Now };
            if (_path is null) return;
            _saveTimer?.Dispose();
            _saveTimer = new Timer(_ => Save(), null, TimeSpan.FromSeconds(3), Timeout.InfiniteTimeSpan);
        }
    }

    public void Clear()
    {
        lock (_lock) _entries.Clear();
        Save();
    }

    private void Save()
    {
        if (_path is null) return;
        lock (_lock)
        {
            // On garde les 4000 plus récentes.
            var keep = _entries.OrderByDescending(e => e.Value.At).Take(4000).ToDictionary(e => e.Key, e => e.Value);
            try { JsonFile.Save(_path, keep); } catch { /* cache facultatif */ }
        }
    }
}
