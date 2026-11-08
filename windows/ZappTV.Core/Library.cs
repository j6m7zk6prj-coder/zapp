namespace ZappTV.Core;

/// <summary>Contenu affiché : liens perso + playlist active, avec les modifications appliquées.</summary>
public sealed class Library
{
    public IReadOnlyList<MediaItem> Items { get; private set; } = [];
    public IReadOnlyList<MediaItem> HiddenItems { get; private set; } = [];
    public IReadOnlyList<MediaItem> CustomLinkItems { get; private set; } = [];
    public bool IsLoading { get; private set; }
    public string? ErrorMessage { get; private set; }
    public Guid? LoadedPlaylistId { get; private set; }

    /// <summary>Déclenché sur le thread appelant (l'interface) après chaque changement.</summary>
    public event Action? Changed;

    private List<MediaItem> _playlistItems = [];
    private List<MediaItem> _customItems = [];
    private Dictionary<string, ItemOverride> _overrides = new();
    private Dictionary<MediaKind, List<MediaItem>> _byKind = new();
    private Dictionary<MediaKind, List<string>> _groups = new();
    private Dictionary<string, MediaItem> _index = new();
    private Dictionary<string, MediaItem> _base = new();
    private int _loadVersion;

    // ── Lecture ───────────────────────────────────────────────────────────

    public IReadOnlyList<MediaItem> All(MediaKind kind) =>
        _byKind.TryGetValue(kind, out var list) ? list : [];

    public int Count(MediaKind kind) => _byKind.TryGetValue(kind, out var list) ? list.Count : 0;

    public IReadOnlyList<string> Groups(MediaKind kind) =>
        _groups.TryGetValue(kind, out var list) ? list : [];

    /// <summary>Version à jour (modifications comprises).</summary>
    public MediaItem? Item(string id) => _index.GetValueOrDefault(id);

    /// <summary>Version d'origine, avant modifications.</summary>
    public MediaItem? BaseItem(string id) => _base.GetValueOrDefault(id);

    public List<MediaItem> Lookup(IEnumerable<string> ids) =>
        ids.Select(id => _index.GetValueOrDefault(id))
            .OfType<MediaItem>()
            .OrderBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();

    public List<MediaItem> RecentlyAdded(MediaKind kind, int limit = 20)
    {
        var list = All(kind).Where(i => !i.IsCustomLink).ToList();
        if (list.Any(i => i.AddedAt != null))
            return list.OrderByDescending(i => i.AddedAt ?? DateTimeOffset.MinValue).Take(limit).ToList();
        return Enumerable.Reverse(list).Take(limit).ToList();
    }

    // ── Chargement ────────────────────────────────────────────────────────

    public void SetCustomization(IEnumerable<MediaItem> links, IReadOnlyDictionary<string, ItemOverride> overrides)
    {
        _customItems = links.ToList();
        _overrides = new Dictionary<string, ItemOverride>(overrides);
        Rebuild();
    }

    public async Task LoadAsync(Playlist playlist, Func<Playlist, string?> passwordResolver, bool force = false)
    {
        if (!force && LoadedPlaylistId == playlist.Id && _playlistItems.Count > 0) return;
        var version = ++_loadVersion;
        ErrorMessage = null;

        var cached = force ? null : await LibraryCache.LoadAsync(playlist.Id);
        if (version != _loadVersion) return;
        if (cached is { Count: > 0 })
        {
            SetPlaylistItems(cached, playlist.Id);
            if (!LibraryCache.IsStale(playlist.Id)) return;
        }
        else if (LoadedPlaylistId != playlist.Id)
        {
            SetPlaylistItems([], null);
        }

        IsLoading = true;
        Changed?.Invoke();
        try
        {
            var fetched = await PlaylistLoader.FetchAsync(playlist, passwordResolver);
            if (version != _loadVersion) return;
            SetPlaylistItems(fetched, playlist.Id);
            LibraryCache.Save(playlist.Id, fetched);
            if (fetched.Count == 0) ErrorMessage = "La playlist est vide ou illisible.";
        }
        catch (Exception ex)
        {
            if (version == _loadVersion) ErrorMessage = FriendlyError(ex);
        }
        finally
        {
            if (version == _loadVersion)
            {
                IsLoading = false;
                Changed?.Invoke();
            }
        }
    }

    public void ResetPlaylist()
    {
        _loadVersion++;
        IsLoading = false;
        ErrorMessage = null;
        SetPlaylistItems([], null);
    }

    /// <summary>Recherche insensible à la casse et aux accents (noms et catégories).</summary>
    public Task<Dictionary<MediaKind, List<MediaItem>>> SearchAsync(string query)
    {
        var term = query.Trim();
        var snapshot = Items;
        return Task.Run(() =>
        {
            var results = new Dictionary<MediaKind, List<MediaItem>>();
            if (term.Length < 2) return results;
            foreach (var item in snapshot)
            {
                if (TextUtil.ContainsLoose(item.Name, term) || TextUtil.ContainsLoose(item.Group, term))
                {
                    if (!results.TryGetValue(item.Kind, out var list)) results[item.Kind] = list = [];
                    list.Add(item);
                }
            }
            return results;
        });
    }

    public static string FriendlyError(Exception ex) => ex switch
    {
        XtreamException => ex.Message,
        TaskCanceledException => "Le serveur ne répond pas (délai dépassé).",
        HttpRequestException => "Impossible de joindre le serveur. Vérifie le lien et ta connexion.",
        FileNotFoundException or DirectoryNotFoundException => "Fichier de playlist introuvable.",
        _ => ex.Message,
    };

    // ── Privé ─────────────────────────────────────────────────────────────

    private void SetPlaylistItems(List<MediaItem> items, Guid? playlistId)
    {
        _playlistItems = items;
        LoadedPlaylistId = playlistId;
        Rebuild();
    }

    private void Rebuild()
    {
        var seen = new HashSet<string>();
        var visible = new List<MediaItem>(_customItems.Count + _playlistItems.Count);
        var hidden = new List<MediaItem>();
        var custom = new List<MediaItem>();
        var byKind = new Dictionary<MediaKind, List<MediaItem>>();
        var groups = new Dictionary<MediaKind, List<string>>();
        var groupSeen = new Dictionary<MediaKind, HashSet<string>>();
        var index = new Dictionary<string, MediaItem>();
        var baseIndex = new Dictionary<string, MediaItem>();

        foreach (var original in _customItems.Concat(_playlistItems))
        {
            if (!seen.Add(original.Id)) continue;
            baseIndex[original.Id] = original;
            var item = original;
            if (_overrides.TryGetValue(original.Id, out var change))
            {
                item = change.Apply(original);
                if (change.Hidden == true)
                {
                    hidden.Add(item);
                    continue;
                }
            }

            visible.Add(item);
            if (item.IsCustomLink) custom.Add(item);
            if (!byKind.TryGetValue(item.Kind, out var list)) byKind[item.Kind] = list = [];
            list.Add(item);
            index[item.Id] = item;
            if (!groupSeen.TryGetValue(item.Kind, out var set)) groupSeen[item.Kind] = set = [];
            if (set.Add(item.Group))
            {
                if (!groups.TryGetValue(item.Kind, out var names)) groups[item.Kind] = names = [];
                names.Add(item.Group);
            }
        }

        Items = visible;
        HiddenItems = hidden;
        CustomLinkItems = custom;
        _byKind = byKind;
        _groups = groups;
        _index = index;
        _base = baseIndex;
        Changed?.Invoke();
    }
}
