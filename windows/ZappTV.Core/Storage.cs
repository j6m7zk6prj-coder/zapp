using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ZappTV.Core;

/// <summary>Dossier des données : %APPDATA%\ZappTV.</summary>
public static class AppPaths
{
    public static string Root { get; set; } =
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ZappTV");

    public static string DataFile(string name)
    {
        Directory.CreateDirectory(Root);
        return System.IO.Path.Combine(Root, name);
    }

    public static string Folder(string name)
    {
        var path = System.IO.Path.Combine(Root, name);
        Directory.CreateDirectory(path);
        return path;
    }

    public static string LogoFile(string name) => System.IO.Path.Combine(Root, "Logos", name);
    public static string PlaylistFile(string name) => System.IO.Path.Combine(Root, "Playlists", name);
    public static string CacheFile(Guid id) => System.IO.Path.Combine(Folder("Cache"), $"library-{id:N}.json");
}

public static class JsonFile
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() },
    };

    public static T? Load<T>(string path) where T : class
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var stream = File.OpenRead(path);
            return JsonSerializer.Deserialize<T>(stream, Options);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Écriture atomique (fichier temporaire puis remplacement).</summary>
    public static void Save<T>(string path, T value)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
            var temp = path + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(value, Options), Encoding.UTF8);
            File.Move(temp, path, overwrite: true);
        }
        catch
        {
            // Pas bloquant : on retentera à la prochaine modification.
        }
    }
}

public static class Http
{
    public static readonly HttpClient Client = Create();

    private static HttpClient Create()
    {
        var handler = new SocketsHttpHandler
        {
            AutomaticDecompression = DecompressionMethods.All,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        };
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(90) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("ZappTV/1.0");
        return client;
    }
}

/// <summary>Télécharge et décode une playlist, hors du thread de l'interface.</summary>
public static class PlaylistLoader
{
    public static async Task<List<MediaItem>> FetchAsync(Playlist playlist, Func<Playlist, string?> passwordResolver, CancellationToken ct = default)
    {
        switch (playlist.Type)
        {
            case PlaylistSourceType.M3uUrl:
            {
                using var response = await Http.Client.GetAsync(playlist.Url, ct);
                if (!response.IsSuccessStatusCode)
                    throw new XtreamException($"Le serveur a répondu avec l'erreur {(int)response.StatusCode}.");
                var bytes = await response.Content.ReadAsByteArrayAsync(ct);
                return await Task.Run(() => M3UParser.Parse(Encoding.UTF8.GetString(bytes)), ct);
            }
            case PlaylistSourceType.M3uFile:
            {
                var text = await File.ReadAllTextAsync(AppPaths.PlaylistFile(playlist.FileName ?? ""), ct);
                return await Task.Run(() => M3UParser.Parse(text), ct);
            }
            default:
            {
                var password = passwordResolver(playlist);
                if (playlist.Server is null || playlist.Username is null || password is null)
                    throw new XtreamException("Identifiants introuvables. Supprime puis rajoute la playlist.");
                var client = new XtreamClient(new XtreamCredentials(playlist.Server, playlist.Username, password));
                return await client.FetchLibraryAsync(ct);
            }
        }
    }
}

/// <summary>Cache disque d'une playlist, pour un démarrage instantané.</summary>
public static class LibraryCache
{
    public static readonly TimeSpan MaxAge = TimeSpan.FromHours(12);

    public static Task<List<MediaItem>?> LoadAsync(Guid id) => Task.Run(() =>
        JsonFile.Load<List<MediaItem>>(AppPaths.CacheFile(id)));

    public static void Save(Guid id, List<MediaItem> items) =>
        _ = Task.Run(() => JsonFile.Save(AppPaths.CacheFile(id), items));

    public static bool IsStale(Guid id)
    {
        var path = AppPaths.CacheFile(id);
        return !File.Exists(path) || DateTime.Now - File.GetLastWriteTime(path) > MaxAge;
    }

    public static void Remove(Guid id)
    {
        try { File.Delete(AppPaths.CacheFile(id)); } catch { }
    }
}

/// <summary>Logos importés depuis un fichier image.</summary>
public static class LogoStorage
{
    public static string? Import(string sourcePath)
    {
        try
        {
            AppPaths.Folder("Logos");
            var extension = System.IO.Path.GetExtension(sourcePath).ToLowerInvariant();
            if (extension is not (".png" or ".jpg" or ".jpeg" or ".gif" or ".bmp" or ".webp" or ".ico")) extension = ".png";
            var name = Guid.NewGuid().ToString("N") + extension;
            File.Copy(sourcePath, AppPaths.LogoFile(name));
            return name;
        }
        catch
        {
            return null;
        }
    }

    public static void Delete(string? name)
    {
        if (string.IsNullOrEmpty(name)) return;
        try { File.Delete(AppPaths.LogoFile(name)); } catch { }
    }
}
