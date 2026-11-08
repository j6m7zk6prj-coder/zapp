using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
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

        KindText.Text = item.Kind.Label();
        TitleText.Text = item.Name;
        var meta = new List<string> { item.Group };
        if (item.Rating is > 0) meta.Add($"★ {item.Rating:0.0}");
        if (_series?.Genre is { Length: > 0 } genre) meta.Add(genre);
        if (_series is { } detail && detail.Seasons.Count > 0)
            meta.Add(detail.Seasons.Count == 1 ? "1 saison" : $"{detail.Seasons.Count} saisons");
        MetaText.Text = string.Join("  ·  ", meta);

        BackdropFallback.Background = ThemeManager.GradientFor(item.Name);
        Backdrop.Source = image;

        ArtBox.Width = isLive ? 320 : 230;
        ArtBox.Height = isLive ? 180 : 345;
        ArtFallback.Background = ThemeManager.GradientFor(item.Name);
        ArtInitials.Text = item.Initials;
        ArtBrush.ImageSource = isLive ? null : image;
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
        var queue = episodes.Select(e => e.ToPlayable(_item.Name)).ToList();
        for (var i = 0; i < episodes.Count; i++)
        {
            EpisodesList.Children.Add(EpisodeRow(episodes[i], queue, i));
        }
    }

    private UIElement EpisodeRow(Episode episode, List<Playable> queue, int index)
    {
        var thumb = new Grid { Width = 176, Height = 99 };
        thumb.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(10),
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
                CornerRadius = new CornerRadius(10),
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
            var episodes = _series.Episodes.Where(ep => ep.Season == _season).Select(ep => ep.ToPlayable(_item.Name)).ToList();
            if (episodes.Count > 0) PlayerWindow.Open(episodes, 0);
            return;
        }
        Actions.PlayItem(_item, [_item]);
    }

    private void Fav_Click(object sender, RoutedEventArgs e) => Services.Favorites.Toggle(_item.Id);
    private void Edit_Click(object sender, RoutedEventArgs e) => Actions.Edit(_item);

    private void Hide_Click(object sender, RoutedEventArgs e)
    {
        Actions.Hide(_item);
        MainWindow.Instance.GoBack();
    }
}
