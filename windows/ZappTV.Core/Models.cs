using System.Text.Json.Serialization;

namespace ZappTV.Core;

public enum MediaKind { Live, Movie, Series }

public static class MediaKindExtensions
{
    public static string Title(this MediaKind kind) => kind switch
    {
        MediaKind.Live => "En direct",
        MediaKind.Movie => "Films",
        _ => "Séries",
    };

    public static string Unit(this MediaKind kind) => kind switch
    {
        MediaKind.Live => "chaînes",
        MediaKind.Movie => "films",
        _ => "séries",
    };

    public static string Label(this MediaKind kind) => kind switch
    {
        MediaKind.Live => "EN DIRECT",
        MediaKind.Movie => "FILM",
        _ => "SÉRIE",
    };
}

/// <summary>Une chaîne, un film ou une série issue d'une playlist ou d'un lien perso.</summary>
public sealed record MediaItem
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public string Group { get; init; } = "Sans catégorie";
    public MediaKind Kind { get; init; }
    public string? StreamUrl { get; init; }
    public string? LogoUrl { get; init; }
    public double? Rating { get; init; }
    public DateTimeOffset? AddedAt { get; init; }
    public string? SeriesId { get; init; }
    public string? EpgId { get; init; }

    [JsonIgnore] public string DisplayName => TextUtil.DisplayName(Name);
    [JsonIgnore] public string Initials => TextUtil.Initials(DisplayName);
    [JsonIgnore] public bool IsCustomLink => Id.StartsWith(CustomLink.IdPrefix, StringComparison.Ordinal);
    /// <summary>Une série Xtream ouvre une fiche avec ses épisodes.</summary>
    [JsonIgnore] public bool OpensDetail => Kind == MediaKind.Series && SeriesId != null;

    public Playable? ToPlayable() => StreamUrl is null
        ? null
        : new Playable(Id, Name, Group, StreamUrl, LogoUrl, Kind == MediaKind.Live);
}

/// <summary>Ce que le lecteur sait lire.</summary>
public sealed record Playable(string Id, string Title, string? Subtitle, string Url, string? ArtworkUrl, bool IsLive);

public sealed record Episode(
    string Id, string Title, int Season, int Number, string Url,
    string? Plot, string? ImageUrl, string? Duration)
{
    public Playable ToPlayable(string seriesName) =>
        new($"episode-{Id}", Title, $"{seriesName} · S{Season} E{Number}", Url, ImageUrl, false);
}

public sealed record SeriesDetail(string? Plot, string? Genre, List<Episode> Episodes)
{
    public List<int> Seasons => Episodes.Select(e => e.Season).Distinct().Order().ToList();
}

public enum PlaylistSourceType { M3uUrl, M3uFile, Xtream }

public sealed class Playlist
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public PlaylistSourceType Type { get; set; }
    /// <summary>URL M3U.</summary>
    public string? Url { get; set; }
    /// <summary>Fichier M3U importé (dans le dossier Playlists).</summary>
    public string? FileName { get; set; }
    public string? Server { get; set; }
    public string? Username { get; set; }
    /// <summary>Mot de passe Xtream chiffré (DPAPI côté Windows).</summary>
    public string? ProtectedPassword { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;

    [JsonIgnore]
    public string Label => Type switch
    {
        PlaylistSourceType.M3uUrl => "URL M3U",
        PlaylistSourceType.M3uFile => "Fichier M3U",
        _ => "Xtream Codes",
    };
}

/// <summary>Un flux ajouté à la main (n'importe quel format).</summary>
public sealed class CustomLink
{
    public const string DefaultGroup = "Mes liens";
    public const string IdPrefix = "custom-";

    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Url { get; set; } = "";
    public string Group { get; set; } = DefaultGroup;
    public MediaKind Kind { get; set; } = MediaKind.Live;
    public string? LogoUrl { get; set; }
    public string? LogoFile { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;

    [JsonIgnore] public string ItemId => IdPrefix + Id.ToString("N");

    [JsonIgnore]
    public string? ResolvedLogoUrl => LogoFile != null ? AppPaths.LogoFile(LogoFile) : LogoUrl;

    public MediaItem ToMediaItem() => new()
    {
        Id = ItemId,
        Name = Name,
        Group = string.IsNullOrWhiteSpace(Group) ? DefaultGroup : Group,
        Kind = Kind,
        StreamUrl = Url,
        LogoUrl = ResolvedLogoUrl,
        AddedAt = CreatedAt,
    };
}

/// <summary>Modifications de l'utilisateur sur un élément de playlist.</summary>
public sealed class ItemOverride
{
    public string? Name { get; set; }
    public string? Group { get; set; }
    public string? LogoUrl { get; set; }
    public string? LogoFile { get; set; }
    public bool? RemoveLogo { get; set; }
    public bool? Hidden { get; set; }

    [JsonIgnore]
    public bool IsEmpty =>
        string.IsNullOrWhiteSpace(Name)
        && string.IsNullOrWhiteSpace(Group)
        && LogoUrl == null
        && LogoFile == null
        && RemoveLogo != true
        && Hidden != true;

    public MediaItem Apply(MediaItem item)
    {
        var result = item;
        if (!string.IsNullOrWhiteSpace(Name)) result = result with { Name = Name.Trim() };
        if (!string.IsNullOrWhiteSpace(Group)) result = result with { Group = Group.Trim() };
        if (RemoveLogo == true) result = result with { LogoUrl = null };
        else if (LogoFile != null) result = result with { LogoUrl = AppPaths.LogoFile(LogoFile) };
        else if (LogoUrl != null) result = result with { LogoUrl = LogoUrl };
        return result;
    }

    public ItemOverride Clone() => (ItemOverride)MemberwiseClone();
}

public enum BackgroundStyle { Night, Oled, Graphite, Ocean, Plum }
public enum PosterSize { Compact, Regular, Large }
public enum LiveLayout { Grid, List }

public static class AppearanceExtensions
{
    public static string Title(this BackgroundStyle style) => style switch
    {
        BackgroundStyle.Night => "Nuit",
        BackgroundStyle.Oled => "Noir OLED",
        BackgroundStyle.Graphite => "Graphite",
        BackgroundStyle.Ocean => "Océan",
        _ => "Prune",
    };

    /// <summary>(fond, surface, surface haute, lueur) en 0xRRGGBB.</summary>
    public static (uint Base, uint Surface, uint SurfaceHigh, uint Glow) Palette(this BackgroundStyle style) => style switch
    {
        BackgroundStyle.Night => (0x0A0D17, 0x141827, 0x1F2436, 0x182050),
        BackgroundStyle.Oled => (0x000000, 0x111113, 0x1C1C1F, 0x0B0B0D),
        BackgroundStyle.Graphite => (0x141518, 0x202126, 0x2C2E35, 0x26282F),
        BackgroundStyle.Ocean => (0x05161F, 0x0C2430, 0x143443, 0x0B3A4E),
        _ => (0x130A1C, 0x21132D, 0x2F1C40, 0x2E1248),
    };

    public static string Title(this PosterSize size) => size switch
    {
        PosterSize.Compact => "Petites",
        PosterSize.Regular => "Normales",
        _ => "Grandes",
    };

    /// <summary>Largeur d'une affiche en pixels (PC).</summary>
    public static double Width(this PosterSize size) => size switch
    {
        PosterSize.Compact => 128,
        PosterSize.Regular => 160,
        _ => 200,
    };

    public static string Title(this LiveLayout layout) => layout == LiveLayout.Grid ? "Mosaïque" : "Liste";
}

public sealed class AppSettingsData
{
    public const uint DefaultAccent = 0x4F6BFF;

    public uint Accent { get; set; } = DefaultAccent;
    public BackgroundStyle Background { get; set; } = BackgroundStyle.Night;
    public PosterSize PosterSize { get; set; } = PosterSize.Regular;
    public LiveLayout LiveLayout { get; set; } = LiveLayout.Grid;
    public double Volume { get; set; } = 80;

    public static readonly (string Name, uint Hex)[] AccentPresets =
    [
        ("Bleu", 0x4F6BFF), ("Indigo", 0x7462FF), ("Violet", 0xA65CF6), ("Rose", 0xF0458A),
        ("Rouge", 0xF2414B), ("Orange", 0xFF8A1F), ("Jaune", 0xF5C518), ("Vert", 0x2FCB6B),
        ("Turquoise", 0x19C3C3), ("Blanc", 0xEDEDF2),
    ];
}
