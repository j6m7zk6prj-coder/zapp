using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using ZappTV.Core;

namespace ZappTV.Pages;

public partial class SearchPage : UserControl
{
    private const int MaxPerSection = 80;
    private readonly DispatcherTimer _debounce = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private int _searchVersion;

    public SearchPage()
    {
        InitializeComponent();
        _debounce.Tick += async (_, _) =>
        {
            _debounce.Stop();
            await RunSearch();
        };
        Loaded += (_, _) =>
        {
            Services.Favorites.Changed += OnFavoritesChanged;
            Query.Focus();
            UpdateEmpty(Results.Items.Count);
        };
        Unloaded += (_, _) =>
        {
            _debounce.Stop();
            Services.Favorites.Changed -= OnFavoritesChanged;
        };
    }

    private void OnFavoritesChanged()
    {
        if (IsLoaded) _ = RunSearch();
    }

    private void Query_TextChanged(object sender, TextChangedEventArgs e)
    {
        _debounce.Stop();
        _debounce.Start();
    }

    private async Task RunSearch()
    {
        var version = ++_searchVersion;
        var query = Query.Text.Trim();
        var results = await Services.Library.SearchAsync(query);
        if (version != _searchVersion) return;

        var rows = new List<object>();
        var total = 0;
        foreach (var kind in new[] { MediaKind.Live, MediaKind.Movie, MediaKind.Series })
        {
            if (!results.TryGetValue(kind, out var found) || found.Count == 0) continue;
            total += found.Count;
            var shown = found.Take(MaxPerSection).ToList();
            var suffix = found.Count > MaxPerSection ? $" — {MaxPerSection} premiers" : "";
            rows.Add(new SearchHeader { Title = $"{kind.Title()} · {found.Count:N0}{suffix}" });
            rows.AddRange(Tile.Build(shown, 0));
        }
        Results.ItemsSource = rows;
        UpdateEmpty(total);
    }

    private void UpdateEmpty(int total)
    {
        var query = Query.Text.Trim();
        EmptyText.Text = query.Length < 2
            ? "Tape au moins 2 lettres : nom de chaîne, film, série ou catégorie.\nAstuce : Ctrl+F ouvre la recherche depuis n'importe où."
            : $"Aucun résultat pour « {query} ».";
        EmptyText.Visibility = total == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
}
