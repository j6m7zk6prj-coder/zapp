using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using ZappTV.Core;

namespace ZappTV.Controls;

public enum TileGridMode { Auto, Posters, Landscape, List }

/// <summary>
/// Grille virtualisée : les cartes sont regroupées en rangées selon la largeur de la fenêtre,
/// seules les rangées visibles sont créées (fluide même avec des milliers de chaînes).
/// </summary>
public sealed class TileGrid : Grid
{
    private const double Gap = 18;
    private const double SidePadding = 40;

    private readonly ListBox _list;
    private readonly TextBlock _empty;
    private readonly DispatcherTimer _resizeTimer = new() { Interval = TimeSpan.FromMilliseconds(120) };
    private IReadOnlyList<MediaItem> _items = [];
    private TileGridMode _mode;
    private int _columns;
    private double _lastWidth;

    public TileGrid()
    {
        _list = new ListBox
        {
            Style = (Style)Application.Current.FindResource("PlainList"),
            Padding = new Thickness(SidePadding, 8, 16, 30),
        };
        _empty = new TextBlock
        {
            Style = (Style)Application.Current.FindResource("Caption"),
            FontSize = 16,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            MaxWidth = 460,
            Visibility = Visibility.Collapsed,
        };
        Children.Add(_list);
        Children.Add(_empty);

        _resizeTimer.Tick += (_, _) =>
        {
            _resizeTimer.Stop();
            Rebuild(force: false);
        };
        SizeChanged += (_, e) =>
        {
            if (Math.Abs(e.NewSize.Width - _lastWidth) < 1) return;
            _resizeTimer.Stop();
            _resizeTimer.Start();
        };
    }

    public void SetItems(IReadOnlyList<MediaItem> items, TileGridMode mode, string emptyText)
    {
        _items = items;
        _mode = mode;
        _empty.Text = emptyText;
        _empty.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        Rebuild(force: true);
    }

    public void ScrollToTop()
    {
        if (_list.Items.Count > 0) _list.ScrollIntoView(_list.Items[0]);
    }

    private void Rebuild(bool force)
    {
        var width = ActualWidth > 0 ? ActualWidth : 1100;
        _lastWidth = width;

        if (_mode == TileGridMode.List)
        {
            _list.ItemTemplate = (DataTemplate)Application.Current.FindResource("ListRow");
            _list.ItemsSource = Tile.Build(_items, 0, true);
            _columns = 0;
            return;
        }

        var landscape = _mode switch
        {
            TileGridMode.Landscape => true,
            TileGridMode.Posters => false,
            _ => _items.Count > 0 && _items.All(i => i.Kind == MediaKind.Live),
        };
        var poster = Services.Settings.Data.PosterSize.Width();
        var minimum = landscape ? poster * 1.45 : poster;
        var available = Math.Max(200, width - SidePadding - 16 - 14);
        var columns = Math.Max(1, (int)((available + Gap) / (minimum + Gap)));
        _columns = columns;
        var tileWidth = Math.Floor((available - Gap * columns) / columns);

        var tiles = Tile.Build(_items, tileWidth, landscape, Gap);
        var rows = new List<TileRow>((tiles.Count + columns - 1) / columns);
        for (var i = 0; i < tiles.Count; i += columns)
        {
            rows.Add(new TileRow { Tiles = tiles.GetRange(i, Math.Min(columns, tiles.Count - i)) });
        }
        _list.ItemTemplate = (DataTemplate)Application.Current.FindResource("TileRowTemplate");
        _list.ItemsSource = rows;
    }
}
