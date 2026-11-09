using ZappTV.Core.Football;

namespace ZappTV.Core;

public sealed class Profile
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Moi";
    public uint Color { get; set; } = 0x4F6BFF;
    public string Initial => string.IsNullOrWhiteSpace(Name) ? "?" : Name.Trim()[..1].ToUpperInvariant();
}

public sealed class FollowedTeam
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Logo { get; set; }
    public string League { get; set; } = "";
}

/// <summary>Une lecture en cours (film, épisode) ou une chaîne regardée récemment.</summary>
public sealed class HistoryEntry
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string? Subtitle { get; set; }
    public string Url { get; set; } = "";
    public string? Artwork { get; set; }
    public bool IsLive { get; set; }
    public long PositionMs { get; set; }
    public long DurationMs { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.Now;

    public double Progress => DurationMs > 0 ? Math.Clamp((double)PositionMs / DurationMs, 0, 1) : 0;

    /// <summary>Film / épisode commencé mais pas fini.</summary>
    public bool CanResume => !IsLive && DurationMs > 0 && PositionMs > 30_000 && Progress < 0.95;

    public Playable ToPlayable() => new(Id, Title, Subtitle, Url, Artwork, IsLive);
}

/// <summary>Données propres à un profil.</summary>
public sealed class ProfileData
{
    public HashSet<string> Favorites { get; set; } = [];
    public List<string> Leagues { get; set; } = [.. LeagueCatalog.DefaultFollowed];
    public List<FollowedTeam> Teams { get; set; } = [];
    /// <summary>Chaînes choisies pour une compétition (slug → identifiants de chaînes).</summary>
    public Dictionary<string, List<string>> ChannelPins { get; set; } = new();
    public List<HistoryEntry> History { get; set; } = [];
}

internal sealed class ProfilesFile
{
    public List<Profile> Profiles { get; set; } = [];
    public Guid? ActiveId { get; set; }
}

/// <summary>Profils du foyer : chacun a ses favoris, ses équipes, ses ligues et son historique.</summary>
public sealed class ProfileStore
{
    public static readonly uint[] Colors = [0x4F6BFF, 0xF2414B, 0x2FCB6B, 0xFF8A1F, 0xA65CF6, 0x19C3C3, 0xF0458A, 0xF5C518];

    private readonly string _path = AppPaths.DataFile("profiles.json");
    private readonly ProfilesFile _file;

    public event Action? Switched;
    public event Action? FavoritesChanged;
    public event Action? FootChanged;
    public event Action? HistoryChanged;
    public event Action? ProfilesChanged;

    public ProfileStore()
    {
        _file = JsonFile.Load<ProfilesFile>(_path) ?? new ProfilesFile();
        if (_file.Profiles.Count == 0)
        {
            var first = new Profile();
            _file.Profiles.Add(first);
            _file.ActiveId = first.Id;
            var data = new ProfileData();
            // Reprise des favoris de la version précédente.
            if (JsonFile.Load<List<string>>(AppPaths.DataFile("favorites.json")) is { } old) data.Favorites = [.. old];
            JsonFile.Save(DataPath(first.Id), data);
            JsonFile.Save(_path, _file);
        }
        Current = LoadData(Active.Id);
    }

    public IReadOnlyList<Profile> Profiles => _file.Profiles;
    public Profile Active => _file.Profiles.FirstOrDefault(p => p.Id == _file.ActiveId) ?? _file.Profiles[0];
    public ProfileData Current { get; private set; }

    // ── Profils ───────────────────────────────────────────────────────────

    public Profile Add(string name)
    {
        var profile = new Profile
        {
            Name = string.IsNullOrWhiteSpace(name) ? $"Profil {_file.Profiles.Count + 1}" : name.Trim(),
            Color = Colors[_file.Profiles.Count % Colors.Length],
        };
        _file.Profiles.Add(profile);
        JsonFile.Save(DataPath(profile.Id), new ProfileData());
        SaveProfiles();
        return profile;
    }

    public void Update(Profile profile, string name, uint color)
    {
        profile.Name = string.IsNullOrWhiteSpace(name) ? profile.Name : name.Trim();
        profile.Color = color;
        SaveProfiles();
    }

    public void Delete(Profile profile)
    {
        if (_file.Profiles.Count <= 1) return;
        _file.Profiles.RemoveAll(p => p.Id == profile.Id);
        try { File.Delete(DataPath(profile.Id)); } catch { }
        if (_file.ActiveId == profile.Id) Switch(_file.Profiles[0].Id);
        else SaveProfiles();
    }

    public void Switch(Guid id)
    {
        if (_file.Profiles.All(p => p.Id != id)) return;
        SaveData();
        _file.ActiveId = id;
        Current = LoadData(id);
        SaveProfiles();
        Switched?.Invoke();
        FavoritesChanged?.Invoke();
        FootChanged?.Invoke();
        HistoryChanged?.Invoke();
    }

    // ── Favoris ───────────────────────────────────────────────────────────

    public void ToggleFavorite(string id)
    {
        if (!Current.Favorites.Remove(id)) Current.Favorites.Add(id);
        SaveData();
        FavoritesChanged?.Invoke();
    }

    // ── Foot ──────────────────────────────────────────────────────────────

    public bool FollowsLeague(string slug) => Current.Leagues.Contains(slug);
    public bool FollowsTeam(string id) => Current.Teams.Any(t => t.Id == id);

    public void SetLeagueFollowed(string slug, bool followed)
    {
        Current.Leagues.Remove(slug);
        if (followed) Current.Leagues.Add(slug);
        SaveData();
        FootChanged?.Invoke();
    }

    public void SetTeamFollowed(FollowedTeam team, bool followed)
    {
        Current.Teams.RemoveAll(t => t.Id == team.Id);
        if (followed) Current.Teams.Add(team);
        SaveData();
        FootChanged?.Invoke();
    }

    public IReadOnlyList<string> PinnedChannels(string slug) =>
        Current.ChannelPins.TryGetValue(slug, out var list) ? list : [];

    public void TogglePin(string slug, string channelId)
    {
        if (!Current.ChannelPins.TryGetValue(slug, out var list)) Current.ChannelPins[slug] = list = [];
        if (!list.Remove(channelId)) list.Insert(0, channelId);
        if (list.Count == 0) Current.ChannelPins.Remove(slug);
        SaveData();
        FootChanged?.Invoke();
    }

    // ── Historique ────────────────────────────────────────────────────────

    /// <summary>Enregistre la position de lecture (sans prévenir l'interface, appelé souvent).</summary>
    public void Record(Playable playable, long positionMs, long durationMs, bool notify)
    {
        var entry = Current.History.FirstOrDefault(h => h.Id == playable.Id);
        if (entry is null)
        {
            entry = new HistoryEntry { Id = playable.Id };
            Current.History.Insert(0, entry);
        }
        entry.Title = playable.Title;
        entry.Subtitle = playable.Subtitle;
        entry.Url = playable.Url;
        entry.Artwork = playable.ArtworkUrl;
        entry.IsLive = playable.IsLive;
        if (positionMs >= 0) entry.PositionMs = positionMs;
        if (durationMs > 0) entry.DurationMs = durationMs;
        entry.UpdatedAt = DateTimeOffset.Now;
        Current.History = Current.History.OrderByDescending(h => h.UpdatedAt).Take(200).ToList();
        SaveData();
        if (notify) HistoryChanged?.Invoke();
    }

    public HistoryEntry? HistoryFor(string id) => Current.History.FirstOrDefault(h => h.Id == id);

    public List<HistoryEntry> ContinueWatching(int limit = 20) =>
        Current.History.Where(h => h.CanResume).OrderByDescending(h => h.UpdatedAt).Take(limit).ToList();

    public List<HistoryEntry> RecentChannels(int limit = 20) =>
        Current.History.Where(h => h.IsLive).OrderByDescending(h => h.UpdatedAt).Take(limit).ToList();

    public void RemoveHistory(string id)
    {
        Current.History.RemoveAll(h => h.Id == id);
        SaveData();
        HistoryChanged?.Invoke();
    }

    public void ClearHistory()
    {
        Current.History.Clear();
        SaveData();
        HistoryChanged?.Invoke();
    }

    // ── Fichiers ──────────────────────────────────────────────────────────

    private static string DataPath(Guid id) => AppPaths.DataFile($"profile-{id:N}.json");

    private static ProfileData LoadData(Guid id) => JsonFile.Load<ProfileData>(DataPath(id)) ?? new ProfileData();

    private void SaveData() => JsonFile.Save(DataPath(Active.Id), Current);

    private void SaveProfiles()
    {
        JsonFile.Save(_path, _file);
        ProfilesChanged?.Invoke();
    }
}
