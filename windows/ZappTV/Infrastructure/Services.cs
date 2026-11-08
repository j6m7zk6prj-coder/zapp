using System.Security.Cryptography;
using System.Text;
using LibVLCSharp.Shared;
using ZappTV.Core;

namespace ZappTV;

/// <summary>Instances partagées de l'app.</summary>
public static class Services
{
    public static SettingsStore Settings { get; private set; } = null!;
    public static PlaylistStore Playlists { get; private set; } = null!;
    public static FavoritesStore Favorites { get; private set; } = null!;
    public static CustomizationStore Customization { get; private set; } = null!;
    public static Library Library { get; private set; } = null!;
    public static LibVLC LibVLC => _libVlc ??= new LibVLC("--no-osd", "--no-video-title-show");

    private static LibVLC? _libVlc;

    public static void Initialize()
    {
        Settings = new SettingsStore();
        Playlists = new PlaylistStore();
        Favorites = new FavoritesStore();
        Customization = new CustomizationStore();
        Library = new Library();

        Customization.Changed += SyncCustomization;
        Playlists.Changed += () =>
        {
            if (Playlists.Active?.Id != Library.LoadedPlaylistId) LoadActivePlaylist();
        };
        SyncCustomization();
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
