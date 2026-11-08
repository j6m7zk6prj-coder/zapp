using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Controls;
using ZappTV.Core;

namespace ZappTV.Pages;

public partial class HomePage : UserControl
{
    public HomePage()
    {
        InitializeComponent();
        PageRefresh.Attach(this, Refresh);
    }

    private void Refresh()
    {
        var library = Services.Library;
        Hero.SetItems(Featured());
        Sections.Children.Clear();

        if (library.IsLoading && library.Items.Count == 0)
            Sections.Children.Add(UiFactory.StatusLine("Chargement de la playlist…"));
        if (library.ErrorMessage is { } error)
            Sections.Children.Add(UiFactory.ErrorBanner(error, () => Services.LoadActivePlaylist(force: true)));

        Sections.Children.Add(QuickCards());

        var favorites = library.Lookup(Services.Favorites.Ids);
        if (favorites.Count > 0)
            Sections.Children.Add(new ShelfView("Mes favoris", favorites.Take(30).ToList(), BrowseRoute.Favorites));

        if (library.CustomLinkItems.Count > 0)
            Sections.Children.Add(new ShelfView("Mes liens", library.CustomLinkItems.Take(30).ToList(), BrowseRoute.CustomLinks));

        var channels = library.All(MediaKind.Live).Take(30).ToList();
        if (channels.Count > 0)
            Sections.Children.Add(new ShelfView("En direct", channels, BrowseRoute.OfKind(MediaKind.Live), landscape: true));

        var groups = library.Groups(MediaKind.Live);
        if (groups.Count > 1)
            Sections.Children.Add(CategoryLinks("Catégories en direct", MediaKind.Live, groups.Take(30)));

        var movies = library.RecentlyAdded(MediaKind.Movie, 30);
        if (movies.Count > 0)
            Sections.Children.Add(new ShelfView("Films récemment ajoutés", movies, BrowseRoute.OfKind(MediaKind.Movie), landscape: false));

        var series = library.RecentlyAdded(MediaKind.Series, 30);
        if (series.Count > 0)
            Sections.Children.Add(new ShelfView("Séries récemment ajoutées", series, BrowseRoute.OfKind(MediaKind.Series), landscape: false));

        if (library.Items.Count == 0 && !library.IsLoading)
            Sections.Children.Add(UiFactory.StatusLine("Rien à regarder pour l'instant : ajoute un lien ou une playlist avec le bouton « Ajouter »."));
    }

    /// <summary>Mise en avant : films/séries récents avec image, sinon favoris, sinon chaînes.</summary>
    private static List<MediaItem> Featured()
    {
        var library = Services.Library;
        var movies = library.RecentlyAdded(MediaKind.Movie, 40).Where(i => i.LogoUrl != null).Take(3);
        var series = library.RecentlyAdded(MediaKind.Series, 40).Where(i => i.LogoUrl != null).Take(3);
        var artwork = movies.Concat(series).ToList();
        if (artwork.Count > 0) return artwork;
        var favorites = library.Lookup(Services.Favorites.Ids);
        if (favorites.Count > 0) return favorites.Take(6).ToList();
        if (library.CustomLinkItems.Count > 0) return library.CustomLinkItems.Take(6).ToList();
        return library.All(MediaKind.Live).Take(6).ToList();
    }

    private static UIElement QuickCards()
    {
        var grid = new Grid { Margin = new Thickness(40, 0, 40, 34), MaxWidth = 1100, HorizontalAlignment = HorizontalAlignment.Left };
        var cards = new (string Title, string Subtitle, string Glyph, uint From, uint To, string Section)[]
        {
            ("En direct", $"{Services.Library.Count(MediaKind.Live):N0} chaînes", "", 0x4569FF, 0x2A44D8, "live"),
            ("Films", $"{Services.Library.Count(MediaKind.Movie):N0} films", "", 0x9B5CF6, 0x6227D9, "movies"),
            ("Séries", $"{Services.Library.Count(MediaKind.Series):N0} séries", "", 0xEC3B5E, 0xA3123A, "series"),
        };
        for (var i = 0; i < cards.Length; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var card = cards[i];
            var text = new StackPanel { Margin = new Thickness(14, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(new TextBlock { Text = card.Title, FontSize = 17, FontWeight = FontWeights.Black });
            text.Children.Add(new TextBlock { Text = card.Subtitle, FontSize = 12, Opacity = 0.85 });
            var content = new StackPanel { Orientation = Orientation.Horizontal };
            content.Children.Add(UiFactory.Icon(card.Glyph, 24));
            content.Children.Add(text);

            var button = new Button
            {
                Style = (Style)Application.Current.FindResource("TileButton"),
                Margin = new Thickness(i == 0 ? 0 : 8, 0, i == cards.Length - 1 ? 0 : 8, 0),
                Content = new Border
                {
                    Height = 88,
                    CornerRadius = new CornerRadius(16),
                    Padding = new Thickness(20, 0, 20, 0),
                    Background = new LinearGradientBrush(ThemeManager.ColorOf(card.From), ThemeManager.ColorOf(card.To), 30),
                    Child = content,
                },
            };
            var section = card.Section;
            button.Click += (_, _) => MainWindow.Instance.ShowSection(section);
            Grid.SetColumn(button, i);
            grid.Children.Add(button);
        }
        return grid;
    }

    private static UIElement CategoryLinks(string title, MediaKind kind, IEnumerable<string> groups)
    {
        var panel = new StackPanel { Margin = new Thickness(40, 0, 40, 30) };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 21, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 14) });
        var wrap = new WrapPanel();
        foreach (var group in groups)
        {
            var button = new Button
            {
                Content = group,
                Style = (Style)Application.Current.FindResource("GhostButton"),
                Margin = new Thickness(0, 0, 10, 10),
                FontWeight = FontWeights.SemiBold,
            };
            button.Click += (_, _) => MainWindow.Instance.Push(new BrowsePage(BrowseRoute.OfGroup(kind, group)));
            wrap.Children.Add(button);
        }
        panel.Children.Add(wrap);
        return panel;
    }
}
