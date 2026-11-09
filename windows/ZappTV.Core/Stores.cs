namespace ZappTV.Core;

internal sealed class PlaylistData
{
    public List<Playlist> Playlists { get; set; } = [];
    public Guid? ActiveId { get; set; }
}

public sealed class PlaylistStore
{
    private readonly string _path = AppPaths.DataFile("playlists.json");
    private readonly PlaylistData _data;

    public event Action? Changed;

    public PlaylistStore()
    {
        _data = JsonFile.Load<PlaylistData>(_path) ?? new PlaylistData();
    }

    public IReadOnlyList<Playlist> Playlists => _data.Playlists;

    public Playlist? Active =>
        _data.Playlists.FirstOrDefault(p => p.Id == _data.ActiveId) ?? _data.Playlists.FirstOrDefault();

    public void Add(Playlist playlist)
    {
        _data.Playlists.Add(playlist);
        _data.ActiveId = playlist.Id;
        Save();
    }

    public void SetActive(Guid id)
    {
        _data.ActiveId = id;
        Save();
    }

    public void Remove(Playlist playlist)
    {
        LibraryCache.Remove(playlist.Id);
        if (playlist.Type == PlaylistSourceType.M3uFile && playlist.FileName != null)
        {
            try { File.Delete(AppPaths.PlaylistFile(playlist.FileName)); } catch { }
        }
        _data.Playlists.RemoveAll(p => p.Id == playlist.Id);
        if (_data.ActiveId == playlist.Id) _data.ActiveId = _data.Playlists.FirstOrDefault()?.Id;
        Save();
    }

    private void Save()
    {
        JsonFile.Save(_path, _data);
        Changed?.Invoke();
    }
}

/// <summary>Favoris du profil actif.</summary>
public sealed class FavoritesStore
{
    private readonly ProfileStore _profiles;

    public event Action? Changed;

    public FavoritesStore(ProfileStore profiles)
    {
        _profiles = profiles;
        profiles.FavoritesChanged += () => Changed?.Invoke();
    }

    public IReadOnlyCollection<string> Ids => _profiles.Current.Favorites;

    public bool Contains(string id) => _profiles.Current.Favorites.Contains(id);

    public void Toggle(string id) => _profiles.ToggleFavorite(id);
}

internal sealed class CustomizationData
{
    public List<CustomLink> Links { get; set; } = [];
    public Dictionary<string, ItemOverride> Overrides { get; set; } = new();
}

/// <summary>Liens ajoutés à la main + modifications des éléments de playlist.</summary>
public sealed class CustomizationStore
{
    private readonly string _path = AppPaths.DataFile("customization.json");
    private readonly CustomizationData _data;

    public event Action? Changed;

    public CustomizationStore()
    {
        _data = JsonFile.Load<CustomizationData>(_path) ?? new CustomizationData();
    }

    public IReadOnlyList<CustomLink> Links => _data.Links;
    public IReadOnlyDictionary<string, ItemOverride> Overrides => _data.Overrides;
    public IEnumerable<MediaItem> LinkItems => _data.Links.Select(l => l.ToMediaItem());

    public CustomLink? LinkForItem(string itemId) => _data.Links.FirstOrDefault(l => l.ItemId == itemId);

    public void SaveLink(CustomLink link)
    {
        var index = _data.Links.FindIndex(l => l.Id == link.Id);
        if (index >= 0)
        {
            if (_data.Links[index].LogoFile != link.LogoFile) LogoStorage.Delete(_data.Links[index].LogoFile);
            _data.Links[index] = link;
        }
        else
        {
            _data.Links.Add(link);
        }
        Save();
    }

    public void DeleteLink(CustomLink link)
    {
        LogoStorage.Delete(link.LogoFile);
        _data.Links.RemoveAll(l => l.Id == link.Id);
        if (_data.Overrides.Remove(link.ItemId, out var removed)) LogoStorage.Delete(removed.LogoFile);
        Save();
    }

    public void MoveLink(CustomLink link, int delta)
    {
        var index = _data.Links.FindIndex(l => l.Id == link.Id);
        var target = index + delta;
        if (index < 0 || target < 0 || target >= _data.Links.Count) return;
        _data.Links.RemoveAt(index);
        _data.Links.Insert(target, link);
        Save();
    }

    public ItemOverride OverrideFor(string id) =>
        _data.Overrides.TryGetValue(id, out var value) ? value.Clone() : new ItemOverride();

    public void SetOverride(string id, ItemOverride value)
    {
        if (_data.Overrides.TryGetValue(id, out var previous) && previous.LogoFile != value.LogoFile)
            LogoStorage.Delete(previous.LogoFile);
        if (value.IsEmpty) _data.Overrides.Remove(id);
        else _data.Overrides[id] = value;
        Save();
    }

    public void ResetOverride(string id) => SetOverride(id, new ItemOverride());

    public void SetHidden(string id, bool hidden)
    {
        var value = OverrideFor(id);
        value.Hidden = hidden ? true : null;
        SetOverride(id, value);
    }

    private void Save()
    {
        JsonFile.Save(_path, _data);
        Changed?.Invoke();
    }
}

public sealed class SettingsStore
{
    private readonly string _path = AppPaths.DataFile("settings.json");

    public event Action? Changed;

    public SettingsStore()
    {
        Data = JsonFile.Load<AppSettingsData>(_path) ?? new AppSettingsData();
    }

    public AppSettingsData Data { get; }

    public void Update(Action<AppSettingsData> change, bool notify = true)
    {
        change(Data);
        JsonFile.Save(_path, Data);
        if (notify) Changed?.Invoke();
    }
}
