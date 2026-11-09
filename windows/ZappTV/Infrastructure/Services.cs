using System.Security.Cryptography;
using System.Text;
using LibVLCSharp.Shared;
using ZappTV.Core;
using ZappTV.Core.Football;
using ZappTV.Core.Tmdb;

namespace ZappTV;

/// <summary>Instances partagées de l'app.</summary>
public static class Services
{
    public static SettingsStore Settings { get; private set; } = null!;
    public static PlaylistStore Playlists { get; private set; } = null!;
    public static FavoritesStore Favorites { get; private set; } = null!;
    public static ProfileStore Profiles { get; private set; } = null!;
    public static EspnClient Foot { get; } = new();
    public static CustomizationStore Customization { get; private set; } = null!;
    public static Library Library { get; private set; } = null!;

    /// <summary>Fiches films/séries (null tant qu'aucune clé TMDB n'est enregistrée).</summary>
    public static TmdbClient? Tmdb { get; private set; }
    private static TmdbCache? _tmdbCache;
    private static string _tmdbKey = "";
    private static (DateTime At, List<(MediaItem Item, TmdbTrend Trend)> List)? _trending;
    public static LibVLC LibVLC => _libVlc ??= new LibVLC("--no-osd", "--no-video-title-show", "--no-stats");

    private static LibVLC? _libVlc;

    public static void Initialize()
    {
        Settings = new SettingsStore();
        Playlists = new PlaylistStore();
        Profiles = new ProfileStore();
        Favorites = new FavoritesStore(Profiles);
        Customization = new CustomizationStore();
        Library = new Library();

        _tmdbCache = new TmdbCache(AppPaths.DataFile("tmdb-cache.json"));
        SyncTmdb();
        Settings.Changed += SyncTmdb;
        Library.Changed += () => _trending = null;

        Customization.Changed += SyncCustomization;
        Playlists.Changed += () =>
        {
            if (Playlists.Active?.Id != Library.LoadedPlaylistId) LoadActivePlaylist();
        };
        SyncCustomization();
    }

    /// <summary>Chaînes de la playlist pour une compétition : choix de l'utilisateur d'abord, puis diffuseurs habituels.</summary>
    public static List<MediaItem> ChannelsFor(string leagueSlug, int limit = 10)
    {
        var channels = Library.All(MediaKind.Live);
        var pinned = Profiles.PinnedChannels(leagueSlug).Select(Library.Item).OfType<MediaItem>().ToList();
        var matched = ChannelMatcher.Find(channels, Settings.Data.BroadcasterKeywords(leagueSlug), limit);
        return pinned.Concat(matched).DistinctBy(i => i.Id).Take(limit).ToList();
    }

    private static void SyncTmdb()
    {
        var key = Settings.Data.TmdbKey.Trim();
        if (key == _tmdbKey && (Tmdb != null || key.Length == 0)) return;
        _tmdbKey = key;
        _trending = null;
        Tmdb = key.Length > 0 ? new TmdbClient(key, _tmdbCache) : null;
    }

    public static void ClearTmdbCache()
    {
        _tmdbCache?.Clear();
        _trending = null;
    }

    /// <summary>Films et séries en tendance cette semaine qui sont dans la playlist.</summary>
    public static async Task<List<(MediaItem Item, TmdbTrend Trend)>> TrendingInPlaylistAsync()
    {
        if (Tmdb is not { } tmdb) return [];
        if (_trending is { } cached && DateTime.Now - cached.At < TimeSpan.FromHours(6)) return cached.List;
        var trends = await tmdb.TrendingAsync();
        var items = Library.All(MediaKind.Movie).Concat(Library.All(MediaKind.Series)).ToList();
        var list = await Task.Run(() =>
        {
            var index = new Dictionary<string, List<MediaItem>>();
            foreach (var item in items)
            {
                var key = TitleCleaner.Key(TitleCleaner.Clean(item.Name).Title);
                if (key.Length < 2) continue;
                if (!index.TryGetValue(key, out var bucket)) index[key] = bucket = [];
                bucket.Add(item);
            }
            var result = new List<(MediaItem, TmdbTrend)>();
            foreach (var trend in trends)
            {
                var wanted = trend.Kind == TmdbKind.Movie ? MediaKind.Movie : MediaKind.Series;
                var keys = new[] { trend.Title, trend.OriginalTitle }.OfType<string>().Select(TitleCleaner.Key).Distinct();
                var match = keys.SelectMany(k => index.TryGetValue(k, out var b) ? b : []).FirstOrDefault(i => i.Kind == wanted);
                if (match != null && result.All(r => r.Item1.Id != match.Id)) result.Add((match, trend));
            }
            return result;
        });
        _trending = (DateTime.Now, list);
        return list;
    }

    public static bool HasContent => Playlists.Playlists.Count > 0 || Customization.Links.Count > 0;

    public static async void LoadActivePlaylist(bool force = false)
    {
        var active = Playlists.Active;
        if (active is null)
        {
            Library.ResetPlaylist();
            return;
        }
        try
        {
            await Library.LoadAsync(active, Passwords.Resolve, force);
        }
        catch
        {
            // Les erreurs sont déjà exposées par Library.ErrorMessage.
        }
    }

    private static void SyncCustomization() =>
        Library.SetCustomization(Customization.LinkItems, Customization.Overrides);
}

/// <summary>Mots de passe Xtream chiffrés avec le compte Windows (DPAPI).</summary>
public static class Passwords
{
    public static string Protect(string password) =>
        Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(password), null, DataProtectionScope.CurrentUser));

    public static string? Resolve(Playlist playlist)
    {
        if (string.IsNullOrEmpty(playlist.ProtectedPassword)) return null;
        try
        {
            var bytes = ProtectedData.Unprotect(Convert.FromBase64String(playlist.ProtectedPassword), null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }
        catch
        {
            return null;
        }
    }
}
