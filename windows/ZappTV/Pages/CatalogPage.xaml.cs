using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using ZappTV.Controls;
using ZappTV.Core;

namespace ZappTV.Pages;

/// <summary>En direct, Films ou Séries : catégories en puces + grille virtualisée.</summary>
public partial class CatalogPage : UserControl
{
    private const string AllFilter = "\u0001all";
    private const string FavoritesFilter = "\u0001fav";

    private readonly MediaKind _kind;
    private string _filter = AllFilter;
    private List<string> _shownGroups = [];

    public CatalogPage(MediaKind kind)
    {
        InitializeComponent();
        _kind = kind;
        TitleText.Text = kind.Title();
        LayoutPanel.Visibility = kind == MediaKind.Live ? Visibility.Visible : Visibility.Collapsed;
        PageRefresh.Attach(this, Refresh);
    }

    private void Refresh()
    {
        var library = Services.Library;
        var all = library.All(_kind);
        var groups = library.Groups(_kind).ToList();
        if (_filter != AllFilter && _filter != FavoritesFilter && !groups.Contains(_filter)) _filter = AllFilter;
        if (!groups.SequenceEqual(_shownGroups)) BuildChips(groups);
        foreach (var chip in Chips.Children.OfType<RadioButton>()) chip.IsChecked = (string)chip.Tag == _filter;

        IReadOnlyList<MediaItem> items = _filter switch
        {
            AllFilter => all,
            FavoritesFilter => all.Where(i => Services.Favorites.Contains(i.Id)).ToList(),
            _ => all.Where(i => i.Group == _filter).ToList(),
        };

        CountText.Text = library.IsLoading && all.Count == 0
            ? "Chargement…"
            : $"{all.Count:N0} {_kind.Unit()} · {groups.Count:N0} catégories";

        var listMode = _kind == MediaKind.Live && Services.Settings.Data.LiveLayout == LiveLayout.List;
        GridModeButton.IsChecked = !listMode;
        ListModeButton.IsChecked = listMode;

        var mode = listMode ? TileGridMode.List : _kind == MediaKind.Live ? TileGridMode.Landscape : TileGridMode.Posters;
        var empty = _filter == FavoritesFilter
            ? "Aucun favori ici. Clic droit sur une carte → « Ajouter aux favoris »."
            : $"Aucun contenu « {_kind.Title()} » pour l'instant.\nAjoute un lien ou une playlist avec le bouton « Ajouter ».";
        TilesView.SetItems(items, mode, empty);
    }

    private void BuildChips(List<string> groups)
    {
        _shownGroups = groups;
        Chips.Children.Clear();
        AddChip("Tout", AllFilter);
        AddChip("♥  Favoris", FavoritesFilter);
        foreach (var group in groups) AddChip(group, group);
    }

    private void AddChip(string title, string filter)
    {
        var chip = new RadioButton
        {
            Content = title,
            Tag = filter,
            Style = (Style)FindResource("Chip"),
        };
        chip.Click += (_, _) =>
        {
            _filter = filter;
            Refresh();
            TilesView.ScrollToTop();
        };
        Chips.Children.Add(chip);
    }

    private void Layout_Click(object sender, RoutedEventArgs e)
    {
        var layout = sender == ListModeButton ? LiveLayout.List : LiveLayout.Grid;
        Services.Settings.Update(s => s.LiveLayout = layout);
    }

    /// <summary>La molette fait défiler les catégories horizontalement.</summary>
    private void Chips_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        ChipsScroller.ScrollToHorizontalOffset(ChipsScroller.HorizontalOffset - e.Delta);
        e.Handled = true;
    }
}
