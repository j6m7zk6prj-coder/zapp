using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Core.Tmdb;
using ZappTV.Player;

namespace ZappTV.Pages;

/// <summary>Fiche d'une chaîne, d'un film ou d'une série (avec épisodes pour Xtream).</summary>
public partial class DetailPage : UserControl
{
    private readonly MediaItem _original;
    private MediaItem _item;
    private SeriesDetail? _series;
    private bool _seriesRequested;
    private int _season = 1;
    private TmdbInfo? _tmdb;
    private bool _tmdbRequested;

    public DetailPage(MediaItem item)
    {
        InitializeComponent();
        _original = item;
        _item = item;
        PageRefresh.Attach(this, Refresh);
    }

    private void Refresh()
    {
        var library = Services.Library;
        _item = library.Item(_original.Id)
            ?? library.HiddenItems.FirstOrDefault(i => i.Id == _original.Id)
            ?? _original;
        var item = _item;
        var isLive = item.Kind == MediaKind.Live;
        var image = ImageUrlConverter.Load(item.LogoUrl, isLive ? 500 : 700);

        if (!isLive && !_tmdbRequested && Services.Tmdb != null) _ = LoadTmdbAsync(item);
        var tmdb = _tmdb;

        KindText.Text = item.Kind.Label();
        TitleText.Text = tmdb?.Title is { Length: > 0 } tmdbTitle ? tmdbTitle : item.Name;
        var titleLogo = ImageUrlConverter.Load(tmdb?.Logo, 900);
        TitleLogo.Source = titleLogo;
        TitleLogo.Visibility = titleLogo != null ? Visibility.Visible : Visibility.Collapsed;
        TitleText.Visibility = titleLogo != null ? Visibility.Collapsed : Visibility.Visible;
        TaglineText.Text = tmdb?.Tagline ?? "";
        TaglineText.Visibility = tmdb?.Tagline != null ? Visibility.Visible : Visibility.Collapsed;

        var meta = new List<string>();
        if (tmdb?.Year is { } year) meta.Add(year.ToString());
        if (tmdb is { Runtime.Length: > 0 }) meta.Add(tmdb.Runtime);
        if (tmdb?.Genres.Count > 0) meta.Add(string.Join(", ", tmdb.Genres.Take(3)));
        else if (_series?.Genre is { Length: > 0 } genre) meta.Add(genre);
        var rating = tmdb?.Rating ?? item.Rating;
        if (rating is > 0) meta.Add($"★ {rating:0.0}");
        var seasons = _series?.Seasons.Count ?? tmdb?.Seasons ?? 0;
        if (seasons > 0) meta.Add(seasons == 1 ? "1 saison" : $"{seasons} saisons");
        if (meta.Count == 0 || tmdb is null) meta.Insert(0, item.Group);
        MetaText.Text = string.Join("  ·  ", meta);

        BackdropFallback.Background = ThemeManager.GradientFor(item.Name);
        var backdrop = ImageUrlConverter.Load(tmdb?.Backdrop, 1600);
        // Image TMDB nette et grande ; sinon l'image de playlist décodée en 24 px et agrandie (flou sans effet coûteux).
        Backdrop.Source = backdrop ?? ImageUrlConverter.Load(item.LogoUrl, 24);
        Backdrop.Opacity = backdrop != null ? 0.85 : 0.65;
        BackdropArea.Height = backdrop != null ? 700 : 600;
        TrailerButton.Visibility = tmdb?.TrailerUrl != null ? Visibility.Visible : Visibility.Collapsed;
        BuildCast(tmdb);
        if (tmdb?.Overview is { } overview && string.IsNullOrWhiteSpace(_series?.Plot))
        {
            PlotText.Text = overview;
            PlotText.Visibility = Visibility.Visible;
        }

        ArtBox.Width = isLive ? 320 : 230;
        ArtBox.Height = isLive ? 180 : 345;
        ArtFallback.Background = ThemeManager.GradientFor(item.Name);
        ArtInitials.Text = item.Initials;
        ArtBrush.ImageSource = isLive ? null : ImageUrlConverter.Load(tmdb?.Poster, 600) ?? image;
        ArtLogo.Source = isLive ? image : null;
        ArtLogoBox.Visibility = isLive && image != null ? Visibility.Visible : Visibility.Collapsed;

        var favorite = Services.Favorites.Contains(item.Id);
        FavGlyph.Text = favorite ? "" : "";
        FavButton.ToolTip = favorite ? "Retirer des favoris" : "Ajouter aux favoris";
        PlayLabel.Text = isLive ? "Regarder" : "Lire";
        PlayButton.IsEnabled = item.StreamUrl != null || (item.OpensDetail && _series?.Episodes.Count > 0);

        BuildInfo(item);

        if (item.OpensDetail)
        {
            EpisodesSection.Visibility = Visibility.Visible;
            if (!_seriesRequested) _ = LoadSeriesAsync(item);
            else BuildEpisodes();
        }
    }

    private void BuildInfo(MediaItem item)
    {
        var rows = new List<(string, string)> { ("Catégorie", item.Group) };
        if (item.StreamUrl is { } url)
        {
            rows.Add(("Format", LinkInspector.Format(url).Label()));
            rows.Add(("Lecteur", "VLC (tous formats)"));
        }
        if (_tmdb is { } tmdb)
        {
            if (tmdb.OriginalTitle is { } original) rows.Insert(0, ("Titre original", original));
            if (tmdb.Director is { } director) rows.Insert(0, (tmdb.Kind == TmdbKind.Movie ? "Réalisation" : "Création", director));
            if (tmdb.Votes is > 0 and var votes && tmdb.Rating is { } r) rows.Add(("Note TMDB", $"{r:0.0} / 10 ({votes:N0} votes)"));
        }
        rows.Add(("Source", item.IsCustomLink ? "Lien ajouté à la main" : "Playlist"));
        if (Services.Customization.Overrides.ContainsKey(item.Id)) rows.Add(("Modifié", "Oui (nom, logo ou catégorie)"));

        InfoRows.Children.Clear();
        for (var i = 0; i < rows.Count; i++)
        {
            var (label, value) = rows[i];
            var row = new DockPanel { Margin = new Thickness(0, 11, 0, 11) };
            var left = new TextBlock { Text = label, Foreground = (Brush)FindResource("TextSecondaryBrush"), FontSize = 14, Width = 140 };
            DockPanel.SetDock(left, Dock.Left);
            row.Children.Add(left);
            row.Children.Add(new TextBlock { Text = value, FontSize = 14, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Right });
            InfoRows.Children.Add(row);
            if (i < rows.Count - 1) InfoRows.Children.Add(new Border { Height = 1, Background = (Brush)FindResource("HairlineBrush") });
        }
    }

    // ── TMDB ──────────────────────────────────────────────────────────────

    private async Task LoadTmdbAsync(MediaItem item)
    {
        _tmdbRequested = true;
        try
        {
            _tmdb = await Services.Tmdb!.FindAsync(item.Name, item.Kind);
        }
        catch
        {
            // Pas de fiche : on garde les infos de la playlist.
        }
        if (_tmdb != null && IsLoaded) Refresh();
    }

    private void BuildCast(TmdbInfo? tmdb)
    {
        CastList.Children.Clear();
        if (tmdb is null || tmdb.Cast.Count == 0)
        {
            CastSection.Visibility = Visibility.Collapsed;
            return;
        }
        CastSection.Visibility = Visibility.Visible;
        foreach (var person in tmdb.Cast)
        {
            var photo = new Border
            {
                Width = 96,
                Height = 96,
                CornerRadius = new CornerRadius(48),
                Background = ThemeManager.GradientFor(person.Name),
                HorizontalAlignment = HorizontalAlignment.Center,
                Child = new TextBlock { Text = TextUtil.Initials(person.Name), FontSize = 24, FontWeight = FontWeights.Black, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            };
            if (ImageUrlConverter.Load(person.Photo, 200) is { } image)
                photo.Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill };
            if (photo.Background is ImageBrush) photo.Child = null;
            var panel = new StackPanel { Width = 116, Margin = new Thickness(0, 0, 14, 0) };
            panel.Children.Add(photo);
            panel.Children.Add(new TextBlock { Text = person.Name, FontSize = 13, FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 2) });
            if (person.Character is { Length: > 0 } character)
                panel.Children.Add(new TextBlock { Text = character, FontSize = 12, Foreground = (Brush)FindResource("TextSecondaryBrush"), TextAlignment = TextAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
            CastList.Children.Add(panel);
        }
    }

    private void Trailer_Click(object sender, RoutedEventArgs e)
    {
        if (_tmdb?.TrailerUrl is not { } url) return;
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
            MainWindow.Instance.ShowToast("Impossible d'ouvrir le navigateur.");
        }
    }

    // ── Séries ────────────────────────────────────────────────────────────

    private async Task LoadSeriesAsync(MediaItem item)
    {
        _seriesRequested = true;
        EpisodesStatus.Text = "Chargement des épisodes…";
        var playlist = Services.Playlists.Active;
        var password = playlist is null ? null : Passwords.Resolve(playlist);
        if (item.SeriesId is null || playlist?.Server is null || playlist.Username is null || password is null)
        {
            EpisodesStatus.Text = "Cette playlist ne fournit pas la liste des épisodes.";
            return;
        }
        try
        {
            var client = new XtreamClient(new XtreamCredentials(playlist.Server, playlist.Username, password));
            _series = await client.SeriesDetailAsync(item.SeriesId);
            _season = _series.Seasons.FirstOrDefault(1);
            if (_series.Plot is { Length: > 0 } plot)
            {
                PlotText.Text = plot;
                PlotText.Visibility = Visibility.Visible;
            }
            Refresh();
        }
        catch (Exception ex)
        {
            EpisodesStatus.Text = Library.FriendlyError(ex);
        }
    }

    private void BuildEpisodes()
    {
        if (_series is null) return;
        SeasonChips.Children.Clear();
        if (_series.Seasons.Count > 1)
        {
            foreach (var season in _series.Seasons)
            {
                var chip = new RadioButton
                {
                    Content = $"Saison {season}",
                    Style = (Style)FindResource("Chip"),
                    IsChecked = season == _season,
                    Margin = new Thickness(0, 0, 8, 8),
                };
                var number = season;
                chip.Click += (_, _) =>
                {
                    _season = number;
                    BuildEpisodes();
                };
                SeasonChips.Children.Add(chip);
            }
        }

        var episodes = _series.Episodes.Where(e => e.Season == _season).ToList();
        EpisodesStatus.Text = episodes.Count == 0 ? "Aucun épisode." : $"{episodes.Count} épisode(s)";
        EpisodesList.Children.Clear();
        // File de lecture de toute la série : l'épisode suivant enchaîne même d'une saison à l'autre.
        var all = AllEpisodes();
        var queue = all.Select(e => e.ToPlayable(_item.Name)).ToList();
        foreach (var episode in episodes)
        {
            EpisodesList.Children.Add(EpisodeRow(episode, queue, all.IndexOf(episode)));
        }
    }

    private UIElement EpisodeRow(Episode episode, List<Playable> queue, int index)
    {
        var thumb = new Grid { Width = 176, Height = 99 };
        thumb.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(14),
            Background = ThemeManager.GradientFor(_item.Name + episode.Season),
            Child = new TextBlock
            {
                Text = $"E{episode.Number}",
                FontSize = 22,
                FontWeight = FontWeights.Black,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        });
        if (ImageUrlConverter.Load(episode.ImageUrl, 360) is { } image)
        {
            thumb.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(14),
                Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill },
            });
        }

        var texts = new StackPanel { Margin = new Thickness(18, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(new TextBlock { Text = $"ÉPISODE {episode.Number}", FontSize = 11, FontWeight = FontWeights.Black, Foreground = (Brush)FindResource("TextSecondaryBrush") });
        texts.Children.Add(new TextBlock { Text = episode.Title, FontSize = 15, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 3) });
        var extra = string.Join("  ·  ", new[] { episode.Duration, episode.Plot }.Where(s => !string.IsNullOrWhiteSpace(s)));
        if (extra.Length > 0)
        {
            texts.Children.Add(new TextBlock
            {
                Text = extra,
                FontSize = 12,
                Foreground = (Brush)FindResource("TextSecondaryBrush"),
                TextTrimming = TextTrimming.CharacterEllipsis,
                MaxHeight = 34,
                TextWrapping = TextWrapping.Wrap,
            });
        }

        var layout = new DockPanel();
        DockPanel.SetDock(thumb, Dock.Left);
        var play = UiFactory.Icon("", 16);
        DockPanel.SetDock(play, Dock.Right);
        play.Margin = new Thickness(0, 0, 12, 0);
        layout.Children.Add(thumb);
        layout.Children.Add(play);
        layout.Children.Add(texts);

        var button = new Button
        {
            Style = (Style)FindResource("RowButton"),
            Content = layout,
            Margin = new Thickness(-10, 0, 0, 6),
        };
        button.Click += (_, _) => PlayerWindow.Open(queue, index);
        return button;
    }

    // ── Actions ───────────────────────────────────────────────────────────

    private void Play_Click(object sender, RoutedEventArgs e)
    {
        if (_item.OpensDetail)
        {
            if (_series is null) return;
            var all = AllEpisodes();
            if (all.Count == 0) return;
            var queue = all.Select(ep => ep.ToPlayable(_item.Name)).ToList();
            // Reprend au dernier épisode commencé, sinon au début de la saison affichée.
            var resume = queue.FindIndex(p => Services.Profiles.HistoryFor(p.Id) is { CanResume: true });
            var start = resume >= 0 ? resume : Math.Max(0, all.FindIndex(ep => ep.Season == _season));
            PlayerWindow.Open(queue, start);
            return;
        }
        Actions.PlayItem(_item, [_item]);
    }

    private List<Episode> AllEpisodes() =>
        _series?.Episodes.OrderBy(e => e.Season).ThenBy(e => e.Number).ToList() ?? [];

    private void Fav_Click(object sender, RoutedEventArgs e) => Services.Favorites.Toggle(_item.Id);
    private void Edit_Click(object sender, RoutedEventArgs e) => Actions.Edit(_item);

    private void Hide_Click(object sender, RoutedEventArgs e)
    {
        Actions.Hide(_item);
        MainWindow.Instance.GoBack();
    }
}
