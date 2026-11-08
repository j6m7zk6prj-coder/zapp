using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using ZappTV.Core;
using ZappTV.Dialogs;
using ZappTV.Pages;
using ZappTV.Player;

namespace ZappTV;

/// <summary>Une carte affichée (chaîne, film, série) avec sa liste de contexte (pour le zapping).</summary>
public sealed class Tile
{
    public required MediaItem Item { get; init; }
    public required IReadOnlyList<MediaItem> Context { get; init; }
    public double Width { get; init; }
    public bool IsLandscape { get; init; }
    public bool IsFavorite { get; init; }
    public Thickness Margin { get; init; } = new(0, 0, 18, 0);

    public double ArtHeight => IsLandscape ? Width * 9 / 16 : Width * 1.5;
    public bool HasLogo => !string.IsNullOrWhiteSpace(Item.LogoUrl);
    public string FavoriteLabel => IsFavorite ? "Retirer des favoris" : "Ajouter aux favoris";
    public string Subtitle => Item.Kind == MediaKind.Live ? Item.Group : $"{Item.Kind.Label().ToLowerInvariant()} · {Item.Group}";
    public string ActionGlyph => Item.Kind == MediaKind.Live ? "" : "";

    public static List<Tile> Build(IReadOnlyList<MediaItem> items, double width, bool? landscape = null, double gap = 18)
    {
        var favorites = Services.Favorites;
        return items.Select(item => new Tile
        {
            Item = item,
            Context = items,
            Width = width,
            IsLandscape = landscape ?? item.Kind == MediaKind.Live,
            IsFavorite = favorites.Contains(item.Id),
            Margin = new Thickness(0, 0, gap, 0),
        }).ToList();
    }
}

public sealed class TileRow
{
    public required List<Tile> Tiles { get; init; }
}

public sealed class SearchHeader
{
    public required string Title { get; init; }
}

public sealed class TileTemplateSelector : DataTemplateSelector
{
    public DataTemplate? PosterTemplate { get; set; }
    public DataTemplate? LandscapeTemplate { get; set; }

    public override DataTemplate? SelectTemplate(object item, DependencyObject container) =>
        item is Tile { IsLandscape: true } ? LandscapeTemplate : PosterTemplate;
}

/// <summary>Écrans « Tout voir ».</summary>
public sealed record BrowseRoute(string Kind, MediaKind? MediaKind = null, string? Group = null)
{
    public static BrowseRoute OfKind(MediaKind kind) => new("kind", kind);
    public static readonly BrowseRoute Favorites = new("favorites");
    public static readonly BrowseRoute CustomLinks = new("links");
    public static BrowseRoute OfGroup(MediaKind kind, string group) => new("group", kind, group);

    public string Title => Kind switch
    {
        "kind" => MediaKind!.Value.Title(),
        "favorites" => "Mes favoris",
        "links" => CustomLink.DefaultGroup,
        _ => Group ?? "",
    };

    public IReadOnlyList<MediaItem> Resolve(Library library) => Kind switch
    {
        "kind" => library.All(MediaKind!.Value),
        "favorites" => library.Lookup(Services.Favorites.Ids),
        "links" => library.CustomLinkItems,
        _ => library.All(MediaKind ?? Core.MediaKind.Live).Where(i => i.Group == Group).ToList(),
    };
}

public sealed class RelayCommand(Action<object?> execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute(parameter);
}

public static class AppCommands
{
    public static ICommand Open { get; } = new RelayCommand(p => Actions.Open(p));
    public static ICommand Play { get; } = new RelayCommand(p => Actions.Play(p));
    public static ICommand Details { get; } = new RelayCommand(p => Actions.ShowDetails(p));
    public static ICommand ToggleFavorite { get; } = new RelayCommand(p => Actions.ToggleFavorite(p));
    public static ICommand Edit { get; } = new RelayCommand(p => Actions.Edit(p));
    public static ICommand Hide { get; } = new RelayCommand(p => Actions.Hide(p));
}

/// <summary>Actions communes à tous les écrans.</summary>
public static class Actions
{
    private static (MediaItem? Item, IReadOnlyList<MediaItem> Context) Resolve(object? parameter) => parameter switch
    {
        Tile tile => (tile.Item, tile.Context),
        MediaItem item => (item, new[] { item }),
        _ => (null, Array.Empty<MediaItem>()),
    };

    /// <summary>Une chaîne se lance directement (avec zapping), le reste ouvre sa fiche.</summary>
    public static void Open(object? parameter)
    {
        var (item, context) = Resolve(parameter);
        if (item is null) return;
        if (item.Kind == MediaKind.Live) PlayItem(item, context);
        else ShowDetails(item);
    }

    public static void ShowDetails(object? parameter)
    {
        var (item, _) = Resolve(parameter);
        if (item is null) return;
        MainWindow.Instance.Push(new DetailPage(item));
    }

    public static void Play(object? parameter)
    {
        var (item, context) = Resolve(parameter);
        if (item is null) return;
        if (item.OpensDetail) ShowDetails(item);
        else PlayItem(item, context);
    }

    public static void PlayItem(MediaItem item, IReadOnlyList<MediaItem> context)
    {
        var playable = item.ToPlayable();
        if (playable is null) return;
        if (item.Kind != MediaKind.Live)
        {
            PlayerWindow.Open([playable], 0);
            return;
        }
        var queue = context.Where(i => i.Kind == MediaKind.Live)
            .Select(i => i.ToPlayable())
            .OfType<Playable>()
            .ToList();
        var index = queue.FindIndex(p => p.Id == playable.Id);
        if (index < 0) PlayerWindow.Open([playable], 0);
        else PlayerWindow.Open(queue, index);
    }

    public static void ToggleFavorite(object? parameter)
    {
        var (item, _) = Resolve(parameter);
        if (item != null) Services.Favorites.Toggle(item.Id);
    }

    public static void Edit(object? parameter)
    {
        var (item, _) = Resolve(parameter);
        if (item is null) return;
        if (item.IsCustomLink && Services.Customization.LinkForItem(item.Id) is { } link)
        {
            new LinkEditorWindow(link).ShowDialog();
        }
        else
        {
            var original = Services.Library.BaseItem(item.Id) ?? item;
            new OverrideEditorWindow(original, Services.Customization.OverrideFor(item.Id)).ShowDialog();
        }
    }

    public static void Hide(object? parameter)
    {
        var (item, _) = Resolve(parameter);
        if (item is null) return;
        Services.Customization.SetHidden(item.Id, true);
        MainWindow.Instance.ShowToast($"« {item.Name} » est masqué. Réaffiche-le dans Réglages.");
    }

    /// <summary>Lien collé (Ctrl+V) ou déposé : flux unique → éditeur de lien, playlist → ajout de playlist.</summary>
    public static bool AddFromText(string? text)
    {
        var url = LinkInspector.Normalize(text?.Split('\n').FirstOrDefault(l => l.Trim().Length > 0));
        if (url is null) return false;
        if (LinkInspector.LooksLikePlaylist(url)) new AddPlaylistWindow(prefillUrl: url).ShowDialog();
        else new LinkEditorWindow(null, url).ShowDialog();
        return true;
    }

    public static void AddPlaylistFile(string path) => new AddPlaylistWindow(prefillFile: path).ShowDialog();
}
