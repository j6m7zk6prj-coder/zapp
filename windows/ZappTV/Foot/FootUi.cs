using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ZappTV.Core.Football;

namespace ZappTV.Foot;

/// <summary>Briques visuelles communes aux écrans Foot (cartes de match, écussons, badges…).</summary>
public static class FootUi
{
    public static Style S(string key) => (Style)Application.Current.FindResource(key);
    public static Brush B(string key) => (Brush)Application.Current.FindResource(key);

    public static readonly Brush LiveBrush = Frozen(new SolidColorBrush(Color.FromRgb(0xE5, 0x48, 0x4D)));
    public static readonly Brush WinBrush = Frozen(new SolidColorBrush(Color.FromRgb(0x4A, 0xDE, 0x80)));
    public static readonly Brush CardBrush = Frozen(new SolidColorBrush(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF)));

    private static T Frozen<T>(T f) where T : Freezable
    {
        f.Freeze();
        return f;
    }

    public static TextBlock Text(string text, double size = 14, FontWeight? weight = null, Brush? brush = null, double opacity = 1)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight ?? FontWeights.Normal,
            Opacity = opacity,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (brush != null) block.Foreground = brush;
        return block;
    }

    public static TextBlock Secondary(string text, double size = 13)
    {
        var block = Text(text, size);
        block.Foreground = B("TextSecondaryBrush");
        return block;
    }

    /// <summary>Écusson d'équipe ou logo de compétition (initiales si l'image manque).</summary>
    public static FrameworkElement Crest(string? url, double size, string name)
    {
        var grid = new Grid { Width = size, Height = size };
        var image = ImageUrlConverter.Load(url, (int)Math.Max(64, size * 2));
        if (image != null)
        {
            grid.Children.Add(new Image { Source = image, Stretch = Stretch.Uniform });
            RenderOptions.SetBitmapScalingMode(grid, BitmapScalingMode.HighQuality);
        }
        else
        {
            grid.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(size / 2),
                Background = ThemeManager.GradientFor(name),
                Child = new TextBlock
                {
                    Text = ZappTV.Core.TextUtil.Initials(name),
                    FontSize = Math.Max(9, size * 0.34),
                    FontWeight = FontWeights.Black,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            });
        }
        return grid;
    }

    public static Border Badge(string text, Brush background, Brush? foreground = null, bool pulse = false)
    {
        var badge = new Border
        {
            Background = background,
            CornerRadius = new CornerRadius(5),
            Padding = new Thickness(7, 2, 7, 2),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock { Text = text, FontSize = 11, FontWeight = FontWeights.Black, Foreground = foreground ?? Brushes.White },
        };
        if (pulse)
        {
            badge.Loaded += (_, _) => badge.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(1, 0.55, TimeSpan.FromSeconds(0.9)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        }
        return badge;
    }

    public static bool ScoresHidden => Services.Settings.Data.HideScores;

    /// <summary>Score à afficher (masqué en mode anti-spoiler pour les matchs terminés).</summary>
    public static (string Home, string Away) Score(Match m, bool reveal = false)
    {
        if (m.State == MatchState.Scheduled || m.HomeScore is null) return ("", "");
        if (m.State == MatchState.Finished && ScoresHidden && !reveal) return ("•", "•");
        return (m.HomeScore ?? "", m.AwayScore ?? "");
    }

    public static FrameworkElement StatusBadge(Match m)
    {
        return m.State switch
        {
            MatchState.Live => Badge(m.StatusText == "Mi-temps" ? "MI-TEMPS" : $"EN DIRECT · {m.StatusText}", LiveBrush, pulse: true),
            MatchState.Postponed => Badge(m.StatusText.ToUpperInvariant(), B("SurfaceHighBrush")),
            MatchState.Finished => Secondary(m.StatusText, 12),
            _ => Text(m.StatusText, 12, FontWeights.SemiBold),
        };
    }

    /// <summary>Carte de match pour les rangées horizontales (accueil, équipe).</summary>
    public static Button MatchCard(Match m, double width = 300)
    {
        var (homeScore, awayScore) = Score(m);
        var panel = new StackPanel();

        var top = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var badge = StatusBadge(m);
        DockPanel.SetDock(badge, Dock.Right);
        top.Children.Add(badge);
        var league = new StackPanel { Orientation = Orientation.Horizontal };
        league.Children.Add(Crest(LeagueCatalog.LogoFor(m.LeagueSlug), 18, m.LeagueName));
        var leagueName = Secondary(m.LeagueName, 12);
        leagueName.Margin = new Thickness(7, 0, 8, 0);
        league.Children.Add(leagueName);
        top.Children.Add(league);
        panel.Children.Add(top);

        panel.Children.Add(TeamLine(m.Home, homeScore, m.HomeWinner && m.State == MatchState.Finished && !ScoresHidden));
        panel.Children.Add(TeamLine(m.Away, awayScore, m.AwayWinner && m.State == MatchState.Finished && !ScoresHidden));

        var channels = m.State is MatchState.Scheduled or MatchState.Live ? Services.ChannelsFor(m.LeagueSlug, 1) : new List<ZappTV.Core.MediaItem>();
        var bottom = channels.Count > 0
            ? $"▶  {channels[0].Name}"
            : Services.Settings.Data.BroadcasterLabel(m.LeagueSlug) is { Length: > 0 } label && m.State != MatchState.Finished ? $"📺  {label}" : m.Venue ?? "";
        if (bottom.Length > 0)
        {
            var footer = Secondary(bottom, 12);
            footer.Margin = new Thickness(0, 10, 0, 0);
            panel.Children.Add(footer);
        }

        var card = new Border
        {
            Width = width,
            CornerRadius = new CornerRadius(16),
            Padding = new Thickness(16, 14, 16, 14),
            Background = B("SurfaceBrush"),
            BorderBrush = m.State == MatchState.Live ? LiveBrush : B("HairlineBrush"),
            BorderThickness = new Thickness(1),
            Child = panel,
        };
        var button = new Button { Style = S("TileButton"), Content = card, Margin = new Thickness(0, 0, 16, 0), ToolTip = $"{m.Home.Name} – {m.Away.Name}" };
        button.Click += (_, _) => MainWindow.Instance.Push(new MatchPage(m));
        return button;
    }

    private static FrameworkElement TeamLine(TeamRef team, string score, bool winner)
    {
        var line = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
        var scoreText = Text(score, 17, FontWeights.Black);
        scoreText.MinWidth = 22;
        scoreText.TextAlignment = TextAlignment.Right;
        DockPanel.SetDock(scoreText, Dock.Right);
        line.Children.Add(scoreText);
        var crest = Crest(team.Logo, 26, team.Name);
        DockPanel.SetDock(crest, Dock.Left);
        line.Children.Add(crest);
        var name = Text(team.ShortName, 15, winner ? FontWeights.Bold : FontWeights.SemiBold);
        name.Margin = new Thickness(10, 0, 8, 0);
        line.Children.Add(name);
        return line;
    }

    /// <summary>Ligne de match pleine largeur (calendrier).</summary>
    public static Button MatchRow(Match m)
    {
        var (homeScore, awayScore) = Score(m);
        var grid = new Grid { Height = 64 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });

        var time = m.State == MatchState.Scheduled
            ? Text(m.Date.ToLocalTime().ToString("HH:mm"), 16, FontWeights.Bold)
            : StatusBadge(m);
        time.HorizontalAlignment = HorizontalAlignment.Left;
        grid.Children.Add(time);

        var home = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var homeName = Text(m.Home.Name, 15, m.HomeWinner && !ScoresHidden ? FontWeights.Bold : FontWeights.SemiBold);
        homeName.Margin = new Thickness(0, 0, 12, 0);
        home.Children.Add(homeName);
        home.Children.Add(Crest(m.Home.Logo, 30, m.Home.Name));
        Grid.SetColumn(home, 1);
        grid.Children.Add(home);

        var middle = m.State == MatchState.Scheduled
            ? Secondary("–", 18)
            : Text($"{homeScore}  -  {awayScore}", 19, FontWeights.Black, m.State == MatchState.Live ? LiveBrush : null);
        middle.HorizontalAlignment = HorizontalAlignment.Center;
        Grid.SetColumn(middle, 2);
        grid.Children.Add(middle);

        var away = new StackPanel { Orientation = Orientation.Horizontal };
        away.Children.Add(Crest(m.Away.Logo, 30, m.Away.Name));
        var awayName = Text(m.Away.Name, 15, m.AwayWinner && !ScoresHidden ? FontWeights.Bold : FontWeights.SemiBold);
        awayName.Margin = new Thickness(12, 0, 0, 0);
        away.Children.Add(awayName);
        Grid.SetColumn(away, 3);
        grid.Children.Add(away);

        if (m.State is MatchState.Scheduled or MatchState.Live)
        {
            var channels = Services.ChannelsFor(m.LeagueSlug, 1);
            var label = channels.Count > 0 ? $"▶  {channels[0].Name}" : Services.Settings.Data.BroadcasterLabel(m.LeagueSlug);
            if (label.Length > 0)
            {
                var channel = Secondary(label, 12);
                channel.HorizontalAlignment = HorizontalAlignment.Right;
                channel.Margin = new Thickness(12, 0, 6, 0);
                Grid.SetColumn(channel, 4);
                grid.Children.Add(channel);
            }
        }

        var button = new Button { Style = S("RowButton"), Content = grid, Margin = new Thickness(0, 0, 0, 2) };
        button.Click += (_, _) => MainWindow.Instance.Push(new MatchPage(m));
        return button;
    }

    public static FrameworkElement SectionHeader(string title, string? action = null, Action? onAction = null, string? logo = null)
    {
        var header = new DockPanel { Margin = new Thickness(0, 30, 0, 12) };
        if (action != null && onAction != null)
        {
            var button = new Button { Style = S("GhostButton"), Content = action, Padding = new Thickness(14, 7, 14, 7) };
            button.Click += (_, _) => onAction();
            DockPanel.SetDock(button, Dock.Right);
            header.Children.Add(button);
        }
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        if (logo != null)
        {
            var crest = Crest(logo, 26, title);
            crest.Margin = new Thickness(0, 0, 10, 0);
            left.Children.Add(crest);
        }
        left.Children.Add(Text(title, 20, FontWeights.Bold));
        header.Children.Add(left);
        return header;
    }

    /// <summary>Rangée horizontale défilante (la molette fait défiler la page, Maj + molette la rangée).</summary>
    public static ScrollViewer Shelf(IEnumerable<UIElement> children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 10) };
        foreach (var child in children) panel.Children.Add(child);
        var scroller = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = panel,
            Focusable = false,
        };
        scroller.PreviewMouseWheel += (_, e) =>
        {
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
            {
                scroller.ScrollToHorizontalOffset(scroller.HorizontalOffset - e.Delta);
                e.Handled = true;
                return;
            }
            e.Handled = true;
            if (VisualTreeHelper.GetParent(scroller) is UIElement parent)
                parent.RaiseEvent(new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta) { RoutedEvent = UIElement.MouseWheelEvent, Source = scroller });
        };
        return scroller;
    }

    public static Border Card(UIElement child, Thickness? padding = null) => new()
    {
        Background = B("SurfaceBrush"),
        CornerRadius = new CornerRadius(16),
        Padding = padding ?? new Thickness(20, 16, 20, 16),
        Child = child,
    };

    public static Button ChannelButton(ZappTV.Core.MediaItem channel, IReadOnlyList<ZappTV.Core.MediaItem> context)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        var logo = new Border { Width = 64, Height = 36, CornerRadius = new CornerRadius(7), Background = B("SurfaceHighBrush"), Margin = new Thickness(0, 0, 12, 0) };
        if (ImageUrlConverter.Load(channel.LogoUrl, 128) is { } image) logo.Child = new Image { Source = image, Margin = new Thickness(5, 4, 5, 4) };
        else logo.Child = new TextBlock { Text = channel.Initials, FontWeight = FontWeights.Black, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        content.Children.Add(logo);
        content.Children.Add(Text(channel.Name, 14, FontWeights.SemiBold));
        var play = Text("  ▶", 13);
        play.Foreground = B("AccentBrush");
        content.Children.Add(play);
        var button = new Button { Style = S("GhostButton"), Content = content, Padding = new Thickness(8, 7, 16, 7), Margin = new Thickness(0, 0, 10, 10), ToolTip = "Regarder" };
        button.Click += (_, _) => Actions.PlayItem(channel, context);
        return button;
    }

    public static Brush TeamBrush(string? hex, Color fallback)
    {
        if (hex != null && ThemeManager.ParseHex(hex) is { } value)
        {
            var color = ThemeManager.ColorOf(value);
            // Couleurs trop claires assombries pour garder le texte lisible.
            var luminance = (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) / 255;
            if (luminance > 0.6) color = Color.FromRgb((byte)(color.R * 0.45), (byte)(color.G * 0.45), (byte)(color.B * 0.45));
            return new SolidColorBrush(color);
        }
        return new SolidColorBrush(fallback);
    }
}
