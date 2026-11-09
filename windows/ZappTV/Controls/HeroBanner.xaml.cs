using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using ZappTV.Core;

namespace ZappTV.Controls;

/// <summary>Grande bannière en haut de l'accueil, qui défile toute seule.</summary>
public partial class HeroBanner : UserControl
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(8) };
    private IReadOnlyList<MediaItem> _items = [];
    private int _index;

    public HeroBanner()
    {
        InitializeComponent();
        _timer.Tick += (_, _) => Move(1);
        Unloaded += (_, _) => _timer.Stop();
        Loaded += (_, _) => { if (_items.Count > 1 && Services.Settings.Data.HeroAutoplay) _timer.Start(); };
    }

    public void SetItems(IReadOnlyList<MediaItem> items)
    {
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

        KindText.Text = item.Kind.Label();
        TitleText.Text = item.DisplayName;
        SubtitleText.Text = item.Rating is > 0
            ? $"{item.Group}  ·  ★ {item.Rating:0.0}"
            : item.Group;
        PlayLabel.Text = isLive ? "Regarder" : item.OpensDetail ? "Épisodes" : "Lire";
        PlayGlyph.Text = item.OpensDetail ? "" : "";
        RefreshFavorite();

        Fallback.Background = ThemeManager.GradientFor(item.Name);
        var image = ImageUrlConverter.Load(item.LogoUrl, isLive ? 600 : 900);
        Backdrop.Source = isLive ? null : image;
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
