using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Pages;

namespace ZappTV.Controls;

/// <summary>Rangée horizontale façon Apple TV, avec « Tout voir » et flèches.</summary>
public partial class ShelfView : UserControl
{
    private readonly BrowseRoute? _route;

    public ShelfView(string title, IReadOnlyList<MediaItem> items, BrowseRoute? route, bool? landscape = null)
    {
        InitializeComponent();
        _route = route;
        TitleText.Text = title;
        Chevron.Visibility = route is null ? Visibility.Collapsed : Visibility.Visible;
        TitleButton.Cursor = route is null ? Cursors.Arrow : Cursors.Hand;

        var poster = Services.Settings.Data.PosterSize.Width();
        var isLandscape = landscape ?? items.All(i => i.Kind == MediaKind.Live);
        var width = isLandscape ? poster * 1.55 : poster;
        // Dans une rangée mixte (favoris), chaque carte garde son format naturel.
        ItemsHost.ItemsSource = landscape is null && !isLandscape
            ? Tile.Build(items, poster).Select(t => t.IsLandscape ? WithWidth(t, poster * 1.55) : t).ToList()
            : Tile.Build(items, width, isLandscape);
    }

    private static Tile WithWidth(Tile tile, double width) => new()
    {
        Item = tile.Item,
        Context = tile.Context,
        Width = width,
        IsLandscape = tile.IsLandscape,
        IsFavorite = tile.IsFavorite,
        Margin = tile.Margin,
    };

    private void Title_Click(object sender, RoutedEventArgs e)
    {
        if (_route == BrowseRoute.CustomLinks) MainWindow.Instance.ShowSection("links");
        else if (_route != null) MainWindow.Instance.Push(new BrowsePage(_route));
    }

    private void Left_Click(object sender, RoutedEventArgs e) =>
        Scroller.ScrollToHorizontalOffset(Math.Max(0, Scroller.HorizontalOffset - Scroller.ViewportWidth * 0.8));

    private void Right_Click(object sender, RoutedEventArgs e) =>
        Scroller.ScrollToHorizontalOffset(Scroller.HorizontalOffset + Scroller.ViewportWidth * 0.8);

    /// <summary>Molette : défile la page ; Maj + molette : défile la rangée.</summary>
    private void Scroller_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        e.Handled = true;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
        {
            Scroller.ScrollToHorizontalOffset(Scroller.HorizontalOffset - e.Delta);
            return;
        }
        if (VisualTreeHelper.GetParent(this) is UIElement parent)
        {
            parent.RaiseEvent(new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta)
            {
                RoutedEvent = MouseWheelEvent,
                Source = this,
            });
        }
    }
}
