using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Controls;
using ZappTV.Core;
using ZappTV.Core.Football;
using ZappTV.Core.Tmdb;
using ZappTV.Foot;
using ZappTV.Player;

namespace ZappTV.Pages;

/// <summary>« Pour toi » : sections dans l'ordre choisi dans les réglages.</summary>
public partial class HomePage : UserControl
{
    private List<Match>? _upcoming;
    private List<Match>? _results;
    private bool _footLoading;
    private DateTime _footLoadedAt;
    private string _footKey = "";
    private List<(MediaItem Item, TmdbTrend Trend)>? _trending;
    private bool _trendingLoading;
    private int _trendingLibraryCount = -1;

    public HomePage()
    {
        InitializeComponent();
        PageRefresh.Attach(this, Refresh);

        // Scores en direct rafraîchis tant que l'accueil est affiché.
        var timer = new System.Windows.Threading.DispatcherTimer();
        timer.Tick += (_, _) =>
        {
            if (_upcoming?.Any(m => m.State == MatchState.Live || (m.State == MatchState.Scheduled && m.Date <= DateTimeOffset.Now)) != true) return;
            Services.Foot.Invalidate();
            _footLoadedAt = DateTime.MinValue;
            LoadFootAsync();
        };
        Loaded += (_, _) =>
        {
            timer.Interval = TimeSpan.FromSeconds(Math.Max(30, Services.Settings.Data.FootRefreshSeconds));
            timer.Start();
        };
        Unloaded += (_, _) => timer.Stop();
    }

    private void Refresh()
    {
        var library = Services.Library;
        var sections = Services.Settings.Data.OrderedHomeSections().Where(s => s.Visible).Select(s => s.Key).ToList();

        Hero.Visibility = sections.Contains("hero") ? Visibility.Visible : Visibility.Collapsed;
        if ((sections.Contains("hero") || sections.Contains("trending")) && Services.Tmdb != null && (_trending is null || _trendingLibraryCount != library.Items.Count)) LoadTrendingAsync();
        if (sections.Contains("hero"))
        {
            var trends = _trending?.Where(t => t.Trend.Backdrop != null).Take(6).ToList();
            if (trends is { Count: > 0 })
                Hero.SetItems(trends.Select(t => t.Item).ToList(), trends.ToDictionary(t => t.Item.Id, t => t.Trend));
            else
                Hero.SetItems(Featured());
        }
        Sections.Children.Clear();
        if (!sections.Contains("hero")) Sections.Children.Add(new Border { Height = 24 });

        if (library.IsLoading && library.Items.Count == 0)
            Sections.Children.Add(UiFactory.StatusLine("Chargement de la playlist…"));
        if (library.ErrorMessage is { } error)
            Sections.Children.Add(UiFactory.ErrorBanner(error, () => Services.LoadActivePlaylist(force: true)));

        foreach (var key in sections)
        {
            if (Section(key) is { } element) Sections.Children.Add(element);
        }

        if (library.Items.Count == 0 && !library.IsLoading)
            Sections.Children.Add(UiFactory.StatusLine("Rien à regarder pour l'instant : ajoute un lien ou une playlist avec le bouton « + » en haut."));

        if (sections.Contains("foot") || sections.Contains("results")) LoadFootAsync();
    }

    private UIElement? Section(string key)
    {
        var library = Services.Library;
        switch (key)
        {
            case "trending":
                return _trending is { Count: > 0 } trending
                    ? new ShelfView("Tendances dans ta playlist", trending.Select(t => t.Item).Take(30).ToList(), null, landscape: false)
                    : null;
            case "continue":
                var resume = Services.Profiles.ContinueWatching();
                return resume.Count > 0 ? ContinueShelf(resume) : null;
            case "foot":
                return FootShelf("Matchs à suivre", _upcoming, "Aucun match aujourd'hui ni demain dans tes compétitions.");
            case "results":
                return _results is { Count: 0 } ? null : FootShelf("Derniers résultats", _results, null);
            case "favorites":
                var favorites = library.Lookup(Services.Favorites.Ids);
                return favorites.Count > 0 ? new ShelfView("Mes favoris", favorites.Take(30).ToList(), BrowseRoute.Favorites) : null;
            case "recent":
                var recent = Services.Profiles.RecentChannels(30).Select(h => library.Item(h.Id)).OfType<MediaItem>().ToList();
                return recent.Count > 0 ? new ShelfView("Chaînes récentes", recent, null, landscape: true) : null;
            case "links":
                return library.CustomLinkItems.Count > 0 ? new ShelfView("Mes liens", library.CustomLinkItems.Take(30).ToList(), BrowseRoute.CustomLinks) : null;
            case "live":
                var channels = library.All(MediaKind.Live).Take(30).ToList();
                return channels.Count > 0 ? new ShelfView("En direct", channels, BrowseRoute.OfKind(MediaKind.Live), landscape: true) : null;
            case "categories":
                var groups = library.Groups(MediaKind.Live);
                return groups.Count > 1 ? CategoryLinks("Catégories en direct", MediaKind.Live, groups.Take(30)) : null;
            case "movies":
                var movies = library.RecentlyAdded(MediaKind.Movie, 30);
                return movies.Count > 0 ? new ShelfView("Films récemment ajoutés", movies, BrowseRoute.OfKind(MediaKind.Movie), landscape: false) : null;
            case "series":
                var series = library.RecentlyAdded(MediaKind.Series, 30);
                return series.Count > 0 ? new ShelfView("Séries récemment ajoutées", series, BrowseRoute.OfKind(MediaKind.Series), landscape: false) : null;
            default:
                return null;
        }
    }

    // ── Tendances (TMDB) ──────────────────────────────────────────────────

    private async void LoadTrendingAsync()
    {
        if (_trendingLoading) return;
        _trendingLoading = true;
        _trendingLibraryCount = Services.Library.Items.Count;
        try
        {
            _trending = await Services.TrendingInPlaylistAsync();
        }
        catch
        {
            _trending = [];
        }
        finally
        {
            _trendingLoading = false;
        }
        if (IsLoaded) Refresh();
    }

    // ── Foot ──────────────────────────────────────────────────────────────

    private async void LoadFootAsync()
    {
        var data = Services.Profiles.Current;
        var slugs = data.Leagues.Union(data.Teams.Select(t => t.League)).Where(s => s.Length > 0).Distinct().ToList();
        var key = string.Join(",", slugs) + "|" + string.Join(",", data.Teams.Select(t => t.Id));
        var fresh = key == _footKey && DateTime.Now - _footLoadedAt < TimeSpan.FromSeconds(Math.Max(30, Services.Settings.Data.FootRefreshSeconds));
        if (_footLoading || fresh) return;
        _footLoading = true;
        try
        {
            var today = DateTime.Today;
            var days = await Task.WhenAll(
                Services.Foot.DayAsync(slugs, today.AddDays(-1)),
                Services.Foot.DayAsync(slugs, today),
                Services.Foot.DayAsync(slugs, today.AddDays(1)));
            var all = days.SelectMany(d => d).DistinctBy(m => m.Id).ToList();
            var teams = data.Teams.Select(t => t.Id).ToHashSet();
            int Priority(Match m) => teams.Contains(m.Home.Id) || teams.Contains(m.Away.Id) ? 0 : 1;
            int LeagueRank(Match m) => data.Leagues.IndexOf(m.LeagueSlug) is var i and >= 0 ? i : 99;

            _upcoming = all.Where(m => m.State is MatchState.Live or MatchState.Scheduled && m.Date.ToLocalTime().Date >= today)
                .OrderBy(m => m.State == MatchState.Live ? 0 : 1).ThenBy(Priority).ThenBy(m => m.Date).ThenBy(LeagueRank)
                .Take(24).ToList();
            _results = all.Where(m => m.State == MatchState.Finished)
                .OrderBy(Priority).ThenByDescending(m => m.Date)
                .Take(20).ToList();
        }
        catch
        {
            _upcoming ??= [];
            _results ??= [];
        }
        finally
        {
            _footLoading = false;
            _footKey = key;
            _footLoadedAt = DateTime.Now;
        }
        if (IsLoaded) Refresh();
    }

    private UIElement FootShelf(string title, List<Match>? matches, string? emptyText)
    {
        var panel = new StackPanel { Margin = new Thickness(40, 0, 0, 26) };
        var header = new DockPanel { Margin = new Thickness(0, 0, 40, 10) };
        var all = new Button { Style = (Style)FindResource("GhostButton"), Content = "Tout le foot", Padding = new Thickness(14, 6, 14, 6) };
        all.Click += (_, _) => MainWindow.Instance.ShowSection("foot");
        DockPanel.SetDock(all, Dock.Right);
        header.Children.Add(all);
        header.Children.Add(new TextBlock { Text = title, FontSize = 21, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
        panel.Children.Add(header);

        if (matches is null)
        {
            panel.Children.Add(new TextBlock { Text = "Chargement des matchs…", Style = (Style)FindResource("Caption") });
        }
        else if (matches.Count == 0)
        {
            panel.Children.Add(new TextBlock { Text = emptyText ?? "", Style = (Style)FindResource("Caption") });
        }
        else
        {
            panel.Children.Add(FootUi.Shelf(matches.Select(m => (UIElement)FootUi.MatchCard(m))));
        }
        return panel;
    }

    // ── Reprendre la lecture ──────────────────────────────────────────────

    private UIElement ContinueShelf(List<HistoryEntry> entries)
    {
        var panel = new StackPanel { Margin = new Thickness(40, 0, 0, 26) };
        panel.Children.Add(new TextBlock { Text = "Reprendre la lecture", FontSize = 21, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 10) });
        panel.Children.Add(FootUi.Shelf(entries.Select(e => (UIElement)ContinueCard(e))));
        return panel;
    }

    private static Button ContinueCard(HistoryEntry entry)
    {
        const double width = 280;
        var image = new Grid { Height = 158, ClipToBounds = true };
        image.Children.Add(new Border { Background = ThemeManager.GradientFor(entry.Title), CornerRadius = new CornerRadius(14) });
        if (ImageUrlConverter.Load(entry.Artwork, 560) is { } artwork)
        {
            image.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(14),
                Background = new ImageBrush(artwork) { Stretch = Stretch.UniformToFill },
            });
        }
        var progress = new Grid { Height = 4, Margin = new Thickness(12, 0, 12, 12), VerticalAlignment = VerticalAlignment.Bottom };
        progress.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, entry.Progress), GridUnitType.Star) });
        progress.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, 1 - entry.Progress), GridUnitType.Star) });
        progress.Children.Add(new Border { Background = (Brush)Application.Current.FindResource("AccentBrush"), CornerRadius = new CornerRadius(2) });
        var rest = new Border { Background = new SolidColorBrush(Color.FromArgb(0x55, 0xFF, 0xFF, 0xFF)), CornerRadius = new CornerRadius(2) };
        Grid.SetColumn(rest, 1);
        progress.Children.Add(rest);
        image.Children.Add(progress);

        var panel = new StackPanel { Width = width };
        panel.Children.Add(image);
        panel.Children.Add(new TextBlock { Text = entry.Title, FontSize = 15, FontWeight = FontWeights.SemiBold, Margin = new Thickness(2, 10, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis });
        var remaining = TimeSpan.FromMilliseconds(Math.Max(0, entry.DurationMs - entry.PositionMs));
        var left = remaining.TotalHours >= 1 ? $"{(int)remaining.TotalHours} h {remaining.Minutes:00}" : $"{Math.Max(1, remaining.Minutes)} min";
        panel.Children.Add(new TextBlock
        {
            Text = string.IsNullOrEmpty(entry.Subtitle) ? $"Encore {left}" : $"{entry.Subtitle} · encore {left}",
            Style = (Style)Application.Current.FindResource("Caption"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap,
            Margin = new Thickness(2, 2, 0, 0),
        });

        var button = new Button { Style = (Style)Application.Current.FindResource("TileButton"), Content = panel, Margin = new Thickness(0, 0, 18, 0) };
        button.Click += (_, _) => PlayerWindow.Open([entry.ToPlayable()], 0);
        var menu = new ContextMenu();
        var remove = new MenuItem { Header = "Retirer de « Reprendre »" };
        remove.Click += (_, _) => Services.Profiles.RemoveHistory(entry.Id);
        menu.Items.Add(remove);
        button.ContextMenu = menu;
        return button;
    }

    // ── Autres sections ───────────────────────────────────────────────────

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
                Style = (Style)Application.Current.FindResource("PillButton"),
                Margin = new Thickness(0, 0, 10, 10),
            };
            button.Click += (_, _) => MainWindow.Instance.Push(new BrowsePage(BrowseRoute.OfGroup(kind, group)));
            wrap.Children.Add(button);
        }
        panel.Children.Add(wrap);
        return panel;
    }
}
