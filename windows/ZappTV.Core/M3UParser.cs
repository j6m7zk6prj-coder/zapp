using System.Text.RegularExpressions;

namespace ZappTV.Core;

/// <summary>Lit une playlist M3U / M3U8 « étendue » (#EXTINF avec attributs tvg-*).</summary>
public static partial class M3UParser
{
    [GeneratedRegex("([A-Za-z0-9_-]+)=\"([^\"]*)\"")]
    private static partial Regex AttributeRegex();

    public static List<MediaItem> Parse(string text)
    {
        var items = new List<MediaItem>();
        (Dictionary<string, string> Attributes, string Title)? pending = null;
        string? groupOverride = null;

        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;

            if (line.StartsWith("#EXTINF", StringComparison.OrdinalIgnoreCase))
            {
                pending = ParseExtinf(line);
                groupOverride = null;
            }
            else if (line.StartsWith("#EXTGRP:", StringComparison.OrdinalIgnoreCase))
            {
                groupOverride = line["#EXTGRP:".Length..].Trim();
            }
            else if (line.StartsWith('#'))
            {
                continue;
            }
            else if (pending is { } entry && IsStreamUrl(line))
            {
                var attributes = entry.Attributes;
                var group = attributes.GetValueOrDefault("group-title") is { Length: > 0 } g
                    ? g
                    : groupOverride is { Length: > 0 } o ? o : "Sans catégorie";
                var logo = attributes.GetValueOrDefault("tvg-logo");
                var epg = attributes.GetValueOrDefault("tvg-id");

                items.Add(new MediaItem
                {
                    Id = TextUtil.StableHash(line).ToString("x"),
                    Name = entry.Title,
                    Group = group,
                    Kind = DetectKind(line),
                    StreamUrl = line,
                    LogoUrl = string.IsNullOrWhiteSpace(logo) ? null : logo,
                    EpgId = string.IsNullOrWhiteSpace(epg) ? null : epg,
                });
                pending = null;
                groupOverride = null;
            }
        }
        return items;
    }

    /// <summary>Attributs <c>cle="valeur"</c> et titre (après la première virgule hors guillemets).</summary>
    public static (Dictionary<string, string> Attributes, string Title) ParseExtinf(string line)
    {
        var attributes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match match in AttributeRegex().Matches(line))
        {
            attributes[match.Groups[1].Value.ToLowerInvariant()] = match.Groups[2].Value;
        }

        var inQuotes = false;
        var commaIndex = -1;
        for (var i = 0; i < line.Length; i++)
        {
            var c = line[i];
            if (c == '"') inQuotes = !inQuotes;
            else if (c == ',' && !inQuotes)
            {
                commaIndex = i;
                break;
            }
        }

        var title = commaIndex >= 0 ? line[(commaIndex + 1)..].Trim() : "";
        if (title.Length == 0) title = attributes.GetValueOrDefault("tvg-name") ?? "";
        if (title.Length == 0) title = "Sans titre";
        return (attributes, title);
    }

    /// <summary>Les serveurs Xtream exposent les films sous /movie/ et les séries sous /series/.</summary>
    public static MediaKind DetectKind(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return MediaKind.Live;
        var path = uri.AbsolutePath.ToLowerInvariant();
        if (path.Contains("/series/")) return MediaKind.Series;
        if (path.Contains("/movie/") || path.Contains("/movies/")) return MediaKind.Movie;
        var extension = Path.GetExtension(path).TrimStart('.');
        return extension is "mp4" or "mkv" or "avi" or "mov" or "m4v" or "webm"
            ? MediaKind.Movie
            : MediaKind.Live;
    }

    private static bool IsStreamUrl(string line) =>
        line.Contains("://", StringComparison.Ordinal) && Uri.TryCreate(line, UriKind.Absolute, out _);
}
