using System.Globalization;
using System.Text.Json;

namespace ZappTV.Core;

public sealed class XtreamException(string message) : Exception(message);

public sealed record XtreamCredentials(string Server, string Username, string Password)
{
    /// <summary>Accepte « hote:port », « http://hote:port/ » ou une URL complète vers player_api.php.</summary>
    public static string? NormalizeServer(string raw)
    {
        var value = raw.Trim();
        if (value.Length == 0) return null;
        if (!value.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            && !value.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            value = "http://" + value;
        }
        var index = value.IndexOf("/player_api.php", StringComparison.OrdinalIgnoreCase);
        if (index >= 0) value = value[..index];
        value = value.TrimEnd('/');
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) && !string.IsNullOrEmpty(uri.Host) ? value : null;
    }
}

/// <summary>Client minimal de l'API Xtream Codes (player_api.php).</summary>
public sealed class XtreamClient(XtreamCredentials credentials)
{
    public async Task AuthenticateAsync(CancellationToken ct = default)
    {
        var root = await GetAsync(null, ct);
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("user_info", out var info)
            || XJson.Int(info, "auth") != 1)
        {
            throw new XtreamException("Identifiants Xtream refusés par le serveur.");
        }
    }

    public async Task<List<MediaItem>> FetchLibraryAsync(CancellationToken ct = default)
    {
        var liveGroups = CategoriesAsync("get_live_categories", ct);
        var movieGroups = CategoriesAsync("get_vod_categories", ct);
        var seriesGroups = CategoriesAsync("get_series_categories", ct);
        var live = GetAsync("get_live_streams", ct);
        var movies = GetAsync("get_vod_streams", ct);
        var series = GetAsync("get_series", ct);
        await Task.WhenAll(liveGroups, movieGroups, seriesGroups, live, movies, series);

        var items = new List<MediaItem>();

        foreach (var entry in XJson.Array(live.Result))
        {
            var id = XJson.Str(entry, "stream_id");
            if (id is null) continue;
            items.Add(new MediaItem
            {
                Id = $"live-{id}",
                Name = XJson.Str(entry, "name") ?? $"Chaîne {id}",
                Group = GroupOf(entry, liveGroups.Result),
                Kind = MediaKind.Live,
                StreamUrl = StreamUrl("live", id, "m3u8"),
                LogoUrl = XJson.Str(entry, "stream_icon"),
                AddedAt = XJson.Date(entry, "added"),
                EpgId = XJson.Str(entry, "epg_channel_id"),
            });
        }

        foreach (var entry in XJson.Array(movies.Result))
        {
            var id = XJson.Str(entry, "stream_id");
            if (id is null) continue;
            items.Add(new MediaItem
            {
                Id = $"movie-{id}",
                Name = XJson.Str(entry, "name") ?? $"Film {id}",
                Group = GroupOf(entry, movieGroups.Result),
                Kind = MediaKind.Movie,
                StreamUrl = StreamUrl("movie", id, XJson.Str(entry, "container_extension") ?? "mp4"),
                LogoUrl = XJson.Str(entry, "stream_icon"),
                Rating = XJson.Double(entry, "rating"),
                AddedAt = XJson.Date(entry, "added"),
            });
        }

        foreach (var entry in XJson.Array(series.Result))
        {
            var id = XJson.Str(entry, "series_id");
            if (id is null) continue;
            items.Add(new MediaItem
            {
                Id = $"series-{id}",
                Name = XJson.Str(entry, "name") ?? $"Série {id}",
                Group = GroupOf(entry, seriesGroups.Result),
                Kind = MediaKind.Series,
                LogoUrl = XJson.Str(entry, "cover"),
                Rating = XJson.Double(entry, "rating"),
                AddedAt = XJson.Date(entry, "last_modified"),
                SeriesId = id,
            });
        }
        return items;
    }

    public async Task<SeriesDetail> SeriesDetailAsync(string seriesId, CancellationToken ct = default)
    {
        var root = await GetAsync("get_series_info", ct, ("series_id", seriesId));
        if (root.ValueKind != JsonValueKind.Object) throw new XtreamException("Réponse du serveur illisible.");
        root.TryGetProperty("info", out var info);

        // Selon les serveurs : { "1": [...], "2": [...] } ou [[...], [...]]
        var groups = new List<JsonElement>();
        if (root.TryGetProperty("episodes", out var episodesNode))
        {
            if (episodesNode.ValueKind == JsonValueKind.Object)
                groups.AddRange(episodesNode.EnumerateObject().Select(p => p.Value));
            else if (episodesNode.ValueKind == JsonValueKind.Array)
                groups.AddRange(episodesNode.EnumerateArray());
        }

        var episodes = new List<Episode>();
        foreach (var group in groups)
        {
            foreach (var entry in XJson.Array(group))
            {
                var id = XJson.Str(entry, "id");
                if (id is null) continue;
                entry.TryGetProperty("info", out var details);
                episodes.Add(new Episode(
                    id,
                    XJson.Str(entry, "title") ?? "Épisode",
                    XJson.Int(entry, "season") ?? 1,
                    XJson.Int(entry, "episode_num") ?? 0,
                    StreamUrl("series", id, XJson.Str(entry, "container_extension") ?? "mp4"),
                    XJson.Str(details, "plot"),
                    XJson.Str(details, "movie_image"),
                    XJson.Str(details, "duration")));
            }
        }
        episodes.Sort((a, b) => a.Season != b.Season ? a.Season.CompareTo(b.Season) : a.Number.CompareTo(b.Number));
        return new SeriesDetail(XJson.Str(info, "plot"), XJson.Str(info, "genre"), episodes);
    }

    // ── Privé ────────────────────────────────────────────────────────────

    private static string GroupOf(JsonElement entry, Dictionary<string, string> map)
    {
        var id = XJson.Str(entry, "category_id");
        return id != null && map.TryGetValue(id, out var name) ? name : "Sans catégorie";
    }

    private string StreamUrl(string kind, string id, string extension) =>
        $"{credentials.Server}/{kind}/{Uri.EscapeDataString(credentials.Username)}/{Uri.EscapeDataString(credentials.Password)}/{id}.{extension}";

    private async Task<Dictionary<string, string>> CategoriesAsync(string action, CancellationToken ct)
    {
        var map = new Dictionary<string, string>();
        foreach (var entry in XJson.Array(await GetAsync(action, ct)))
        {
            var id = XJson.Str(entry, "category_id");
            var name = XJson.Str(entry, "category_name");
            if (id != null && name != null) map[id] = name;
        }
        return map;
    }

    private async Task<JsonElement> GetAsync(string? action, CancellationToken ct, params (string Key, string Value)[] extra)
    {
        var query = $"username={Uri.EscapeDataString(credentials.Username)}&password={Uri.EscapeDataString(credentials.Password)}";
        if (action != null) query += $"&action={action}";
        foreach (var (key, value) in extra) query += $"&{key}={Uri.EscapeDataString(value)}";
        var url = $"{credentials.Server}/player_api.php?{query}";

        using var response = await Http.Client.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode)
            throw new XtreamException($"Le serveur a répondu avec l'erreur {(int)response.StatusCode}.");
        var bytes = await response.Content.ReadAsByteArrayAsync(ct);
        try
        {
            using var document = JsonDocument.Parse(bytes);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            throw new XtreamException("Réponse du serveur illisible.");
        }
    }
}

/// <summary>Les serveurs Xtream mélangent nombres et chaînes : lecture tolérante.</summary>
public static class XJson
{
    public static IEnumerable<JsonElement> Array(JsonElement element) =>
        element.ValueKind == JsonValueKind.Array
            ? element.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.Object)
            : Enumerable.Empty<JsonElement>();

    public static string? Str(JsonElement element, string property)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(property, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString() is { Length: > 0 } s ? s : null,
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.True => "1",
            JsonValueKind.False => "0",
            _ => null,
        };
    }

    public static int? Int(JsonElement element, string property)
    {
        var text = Str(element, property);
        if (text is null) return null;
        if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var i)) return i;
        return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? (int)d : null;
    }

    public static double? Double(JsonElement element, string property) => ParseDouble(Str(element, property));

    public static double? ParseDouble(string? text) =>
        text != null && double.TryParse(text.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var d)
            ? d
            : null;

    public static DateTimeOffset? Date(JsonElement element, string property)
    {
        var seconds = Double(element, property);
        return seconds is > 0 ? DateTimeOffset.FromUnixTimeSeconds((long)seconds.Value) : null;
    }
}
