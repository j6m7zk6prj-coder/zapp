using System.Security.Cryptography;
using System.Text;
using LibVLCSharp.Shared;
using ZappTV.Core;
using ZappTV.Core.Football;

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
