using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using ZappTV.Controls;
using ZappTV.Core;

namespace ZappTV.Pages;

public static class PageRefresh
{
    /// <summary>
    /// Rafraîchit la page quand la bibliothèque, les favoris ou les réglages changent,
    /// tant qu'elle est affichée (plusieurs changements d'affilée = un seul rafraîchissement).
    /// </summary>
    public static void Attach(FrameworkElement page, Action refresh)
    {
        var pending = false;
        void Schedule()
        {
            if (pending) return;
            pending = true;
            page.Dispatcher.InvokeAsync(() =>
            {
                pending = false;
                if (page.IsLoaded) refresh();
            }, DispatcherPriority.Background);
        }

        page.Loaded += (_, _) =>
        {
            Services.Library.Changed += Schedule;
            Services.Favorites.Changed += Schedule;
            Services.Settings.Changed += Schedule;
            Services.Profiles.HistoryChanged += Schedule;
            Services.Profiles.FootChanged += Schedule;
            refresh();
        };
        page.Unloaded += (_, _) =>
        {
            Services.Library.Changed -= Schedule;
            Services.Favorites.Changed -= Schedule;
            Services.Settings.Changed -= Schedule;
            Services.Profiles.HistoryChanged -= Schedule;
            Services.Profiles.FootChanged -= Schedule;
        };
    }
}

public static class UiFactory
{
    public static TextBlock Icon(string glyph, double size = 15) => new()
    {
        Text = glyph,
        Style = (Style)Application.Current.FindResource("Icon"),
        FontSize = size,
    };

    public static Border ErrorBanner(string message, Action retry)
    {
        var button = new Button
        {
            Content = "Réessayer",
            Style = (Style)Application.Current.FindResource("GhostButton"),
            Margin = new Thickness(16, 0, 0, 0),
        };
        button.Click += (_, _) => retry();
        var panel = new DockPanel();
        var icon = Icon("", 18);
        icon.Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0xA5, 0x3D));
        icon.Margin = new Thickness(0, 0, 14, 0);
        DockPanel.SetDock(icon, Dock.Left);
        DockPanel.SetDock(button, Dock.Right);
        panel.Children.Add(icon);
        panel.Children.Add(button);
        panel.Children.Add(new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, FontSize = 14 });
        return new Border
        {
            Child = panel,
            Padding = new Thickness(18, 14, 18, 14),
            CornerRadius = new CornerRadius(14),
            Background = (Brush)Application.Current.FindResource("SurfaceBrush"),
            Margin = new Thickness(40, 0, 40, 24),
            MaxWidth = 900,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
    }

    public static TextBlock StatusLine(string text) => new()
    {
        Text = text,
        Style = (Style)Application.Current.FindResource("Caption"),
        FontSize = 15,
        Margin = new Thickness(42, 0, 40, 24),
    };
}

/// <summary>Écran « Tout voir ».</summary>
public sealed class BrowsePage : Grid
{
    private readonly BrowseRoute _route;
    private readonly TextBlock _title = new() { Style = (Style)Application.Current.FindResource("PageTitle") };
    private readonly TextBlock _count = new() { Style = (Style)Application.Current.FindResource("Caption"), Margin = new Thickness(2, 2, 0, 0) };
    private readonly TileGrid _grid = new();

    public BrowsePage(BrowseRoute route)
    {
        _route = route;
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition());
        var header = new StackPanel { Margin = new Thickness(84, 22, 40, 12) };
        header.Children.Add(_title);
        header.Children.Add(_count);
        Children.Add(header);
        SetRow(_grid, 1);
        Children.Add(_grid);
        PageRefresh.Attach(this, Refresh);
    }

    private void Refresh()
    {
        var items = _route.Resolve(Services.Library);
        _title.Text = _route.Title;
        _count.Text = $"{items.Count:N0} élément(s)";
        var mode = Services.Settings.Data.LiveLayout == LiveLayout.List && items.All(i => i.Kind == MediaKind.Live)
            ? TileGridMode.List
            : TileGridMode.Auto;
        _grid.SetItems(items, mode, "Rien ici pour l'instant.");
    }
}
