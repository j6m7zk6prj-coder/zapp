using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using ZappTV.Core;
using ZappTV.Core.Tmdb;

namespace ZappTV.Controls;

/// <summary>Grande bannière en haut de l'accueil, qui défile toute seule.</summary>
public partial class HeroBanner : UserControl
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(8) };
    private IReadOnlyList<MediaItem> _items = [];
    private IReadOnlyDictionary<string, TmdbTrend> _trends = new Dictionary<string, TmdbTrend>();
    private int _index;

    public HeroBanner()
    {
        InitializeComponent();
        _timer.Tick += (_, _) => Move(1);
        Unloaded += (_, _) => _timer.Stop();
        Loaded += (_, _) => { if (_items.Count > 1 && Services.Settings.Data.HeroAutoplay) _timer.Start(); };
    }

    public void SetItems(IReadOnlyList<MediaItem> items, IReadOnlyDictionary<string, TmdbTrend>? trends = null)
    {
        _trends = trends ?? new Dictionary<string, TmdbTrend>();
        var current = _items.Count > 0 ? _items[Math.Min(_index, _items.Count - 1)].Id : null;
        _items = items;
        _index = Math.Max(0, items.ToList().FindIndex(i => i.Id == current));
        Visibility = items.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        BuildDots();
        Show(animate: false);
        _timer.Stop();
        if (items.Count > 1 && IsLoaded && Services.Settings.Data.HeroAutoplay) _timer.Start();
    }

    private MediaItem? Current => _items.Count > 0 ? _items[_index] : null;

    private void Show(bool animate)
    {
        if (Current is not { } item) return;
        var isLive = item.Kind == MediaKind.Live;

        _trends.TryGetValue(item.Id, out var trend);
        KindText.Text = trend != null ? $"Tendance cette semaine · {(item.Kind == MediaKind.Movie ? "Film" : "Série")}" : item.Kind.Title() switch
        {
            "En direct" => "En direct",
            "Films" => "Film",
            _ => "Série",
        };
        TitleText.Text = trend?.Title is { Length: > 0 } t ? t : item.DisplayName;
        TitleLogo.Visibility = Visibility.Collapsed;
        var parts = new List<string>();
        if (trend?.Year is { } year) parts.Add(year.ToString());
        var rating = trend?.Rating ?? item.Rating;
        if (rating is > 0) parts.Add($"★ {rating:0.0}");
        if (trend is null) parts.Insert(0, item.Group);
        SubtitleText.Text = string.Join("  ·  ", parts);
        OverviewText.Text = trend?.Overview ?? "";
        OverviewText.Visibility = string.IsNullOrWhiteSpace(trend?.Overview) ? Visibility.Collapsed : Visibility.Visible;
        PlayLabel.Text = isLive ? "Regarder" : item.OpensDetail ? "Épisodes" : "Lire";
        PlayGlyph.Text = item.OpensDetail ? "" : "";
        RefreshFavorite();

        Fallback.Background = ThemeManager.GradientFor(item.Name);
        var image = ImageUrlConverter.Load(item.LogoUrl, isLive ? 600 : 900);
        var backdrop = ImageUrlConverter.Load(trend?.Backdrop, 1600);
        // Sans image de fond TMDB : l'affiche décodée en 24 px et agrandie donne un flou doux, sans effet coûteux.
        Backdrop.Source = isLive ? null : backdrop ?? ImageUrlConverter.Load(item.LogoUrl, 24);
        if (ImageUrlConverter.Load(trend?.Poster, 400) is { } poster) image = poster;
        LiveLogo.Source = isLive ? image : null;
        LiveLogo.Visibility = isLive ? Visibility.Visible : Visibility.Collapsed;
        PosterBrush.ImageSource = isLive ? null : image;
        Poster.Visibility = !isLive && image != null ? Visibility.Visible : Visibility.Collapsed;

        for (var i = 0; i < Dots.Children.Count; i++)
        {
            if (Dots.Children[i] is Border dot)
            {
                dot.Width = i == _index ? 22 : 8;
                dot.Opacity = i == _index ? 1 : 0.45;
            }
        }

        if (animate)
        {
            Root.BeginAnimation(OpacityProperty, new DoubleAnimation(0.55, 1, TimeSpan.FromMilliseconds(380)));
        }
    }

    public void RefreshFavorite()
    {
        if (Current is not { } item) return;
        var favorite = Services.Favorites.Contains(item.Id);
        FavGlyph.Text = favorite ? "" : "";
        FavButton.ToolTip = favorite ? "Retirer des favoris" : "Ajouter aux favoris";
    }

    private void BuildDots()
    {
        Dots.Children.Clear();
        if (_items.Count < 2) return;
        for (var i = 0; i < _items.Count; i++)
        {
            Dots.Children.Add(new Border
            {
                Height = 8,
                Width = 8,
                CornerRadius = new CornerRadius(4),
                Background = Brushes.White,
                Margin = new Thickness(4, 0, 0, 0),
            });
        }
    }

    private void Move(int delta)
    {
        if (_items.Count < 2) return;
        _index = (_index + delta + _items.Count) % _items.Count;
        Show(animate: true);
    }

    private void Root_SizeChanged(object sender, SizeChangedEventArgs e) =>
        Root.Clip = new RectangleGeometry(new Rect(e.NewSize), 22, 22);

    private void Root_MouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _timer.Stop();
        if (_items.Count > 1) PrevButton.Visibility = NextButton.Visibility = Visibility.Visible;
    }

    private void Root_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        PrevButton.Visibility = NextButton.Visibility = Visibility.Hidden;
        if (_items.Count > 1 && Services.Settings.Data.HeroAutoplay) _timer.Start();
    }

    private void Play_Click(object sender, RoutedEventArgs e)
    {
        if (Current is { } item) Actions.Play(item);
    }

    private void Fav_Click(object sender, RoutedEventArgs e)
    {
        if (Current is { } item) Services.Favorites.Toggle(item.Id);
    }

    private void Info_Click(object sender, RoutedEventArgs e)
    {
        if (Current is { } item) Actions.ShowDetails(item);
    }

    private void Prev_Click(object sender, RoutedEventArgs e) => Move(-1);
    private void Next_Click(object sender, RoutedEventArgs e) => Move(1);
}
