using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Dialogs;

namespace ZappTV.Pages;

public partial class SettingsPage : UserControl
{
    public SettingsPage()
    {
        InitializeComponent();
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"iTv pour Windows — version {version?.ToString(3) ?? "1.0.0"}";
        BuildShortcuts();

        Loaded += (_, _) =>
        {
            Services.Playlists.Changed += Refresh;
            Services.Library.Changed += Refresh;
            Services.Settings.Changed += Refresh;
            Services.Profiles.ProfilesChanged += Refresh;
            Services.Profiles.Switched += Refresh;
            Services.Profiles.FootChanged += Refresh;
            Refresh();
        };
        Unloaded += (_, _) =>
        {
            Services.Playlists.Changed -= Refresh;
            Services.Library.Changed -= Refresh;
            Services.Settings.Changed -= Refresh;
            Services.Profiles.ProfilesChanged -= Refresh;
            Services.Profiles.Switched -= Refresh;
            Services.Profiles.FootChanged -= Refresh;
        };
    }

    private void Refresh()
    {
        BuildPlaylists();
        BuildProfile();
        BuildHome();
        BuildTmdb();
        BuildFoot();
        BuildPlayer();
        BuildAppearance();
        BuildHidden();
        RefreshButton.IsEnabled = !Services.Library.IsLoading && Services.Playlists.Active != null;
        RefreshLabel.Text = Services.Library.IsLoading ? "Actualisation…" : "Actualiser la playlist active";
    }

    // ── Playlists ─────────────────────────────────────────────────────────

    private void BuildPlaylists()
    {
        PlaylistRows.Children.Clear();
        var active = Services.Playlists.Active;
        if (Services.Playlists.Playlists.Count == 0)
        {
            PlaylistRows.Children.Add(new TextBlock { Text = "Aucune playlist. Tu peux aussi ajouter des liens un par un dans « Mes liens ».", Style = (Style)FindResource("Caption"), Margin = new Thickness(0, 0, 0, 8) });
            return;
        }
        foreach (var playlist in Services.Playlists.Playlists)
        {
            var isActive = playlist.Id == active?.Id;
            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(new TextBlock { Text = playlist.Name, FontSize = 15, FontWeight = FontWeights.SemiBold });
            var detail = playlist.Label + (isActive && Services.Library.ErrorMessage is { } error ? $"  ·  {error}" : isActive ? $"  ·  {Services.Library.Items.Count:N0} éléments" : "");
            texts.Children.Add(new TextBlock { Text = detail, Style = (Style)FindResource("Caption"), Margin = new Thickness(0, 2, 0, 0) });

            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            if (isActive)
            {
                actions.Children.Add(new Border
                {
                    Background = (Brush)FindResource("AccentBrush"),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(10, 4, 10, 4),
                    VerticalAlignment = VerticalAlignment.Center,
                    Child = new TextBlock { Text = "Active", FontWeight = FontWeights.SemiBold, Foreground = (Brush)FindResource("OnAccentBrush") },
                });
            }
            else
            {
                var activate = new Button { Content = "Activer", Style = (Style)FindResource("GhostButton") };
                activate.Click += (_, _) => Services.Playlists.SetActive(playlist.Id);
                actions.Children.Add(activate);
            }
            var delete = new Button { Style = (Style)FindResource("IconButton"), Content = UiFactory.Icon(""), ToolTip = "Supprimer", Margin = new Thickness(10, 0, 0, 0), Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x7A, 0x7A)) };
            delete.Click += (_, _) =>
            {
                var answer = MessageBox.Show(Window.GetWindow(this)!, $"Supprimer la playlist « {playlist.Name} » ?", "iTv", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (answer == MessageBoxResult.Yes) Services.Playlists.Remove(playlist);
            };
            actions.Children.Add(delete);

            var row = new DockPanel();
            DockPanel.SetDock(actions, Dock.Right);
            row.Children.Add(actions);
            row.Children.Add(texts);
            PlaylistRows.Children.Add(new Border
            {
                Background = (Brush)FindResource("SurfaceBrush"),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(18, 12, 12, 12),
                Margin = new Thickness(0, 0, 0, 8),
                Child = row,
            });
        }
    }

    private void AddPlaylist_Click(object sender, RoutedEventArgs e) => new AddPlaylistWindow().ShowDialog();
    private void Refresh_Click(object sender, RoutedEventArgs e) => Services.LoadActivePlaylist(force: true);

    // ── Apparence ─────────────────────────────────────────────────────────

    private void BuildAppearance()
    {
        var data = Services.Settings.Data;
        HexBox.Text = $"#{data.Accent:X6}";

        Swatches.Children.Clear();
        foreach (var (name, hex) in AppSettingsData.AccentPresets)
        {
            var selected = data.Accent == hex;
            var swatch = new Button
            {
                Style = (Style)FindResource("PlainButton"),
                ToolTip = name,
                Margin = new Thickness(0, 0, 12, 12),
                Content = new Grid
                {
                    Width = 44,
                    Height = 44,
                    Children =
                    {
                        new Border { CornerRadius = new CornerRadius(22), Background = new SolidColorBrush(ThemeManager.ColorOf(hex)) },
                        new Border { CornerRadius = new CornerRadius(22), BorderBrush = Brushes.White, BorderThickness = new Thickness(selected ? 3 : 0) },
                        new TextBlock
                        {
                            Text = selected ? "" : "",
                            Style = (Style)FindResource("Icon"),
                            HorizontalAlignment = HorizontalAlignment.Center,
                            Foreground = ThemeManager.IsLight(hex) ? Brushes.Black : Brushes.White,
                        },
                    },
                },
            };
            var value = hex;
            swatch.Click += (_, _) => Services.Settings.Update(s => s.Accent = value);
            Swatches.Children.Add(swatch);
        }

        Backgrounds.Children.Clear();
        foreach (var style in Enum.GetValues<BackgroundStyle>())
        {
            var palette = style.Palette();
            var selected = data.Background == style;
            var preview = new Border
            {
                Width = 120,
                Height = 68,
                CornerRadius = new CornerRadius(12),
                BorderBrush = selected ? (Brush)FindResource("AccentBrush") : new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(selected ? 3 : 1),
                Background = new LinearGradientBrush(ThemeManager.ColorOf(palette.Glow), ThemeManager.ColorOf(palette.Base), 90),
            };
            var content = new StackPanel();
            content.Children.Add(preview);
            content.Children.Add(new TextBlock { Text = style.Title(), FontSize = 13, Margin = new Thickness(2, 7, 0, 0), FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal });
            var button = new Button { Style = (Style)FindResource("TileButton"), Content = content, Margin = new Thickness(0, 0, 14, 12) };
            var value = style;
            button.Click += (_, _) => Services.Settings.Update(s => s.Background = value);
            Backgrounds.Children.Add(button);
        }

        PosterSizes.Children.Clear();
        foreach (var size in Enum.GetValues<PosterSize>())
        {
            var value = size;
            PosterSizes.Children.Add(Chip(size.Title(), data.PosterSize == size, () => Services.Settings.Update(s => s.PosterSize = value)));
        }

        LiveLayouts.Children.Clear();
        foreach (var layout in Enum.GetValues<LiveLayout>())
        {
            var value = layout;
            LiveLayouts.Children.Add(Chip(layout.Title(), data.LiveLayout == layout, () => Services.Settings.Update(s => s.LiveLayout = value)));
        }
    }

    private RadioButton Chip(string title, bool selected, Action onClick)
    {
        var chip = new RadioButton { Content = title, Style = (Style)FindResource("Chip"), IsChecked = selected };
        chip.Click += (_, _) => onClick();
        return chip;
    }

    private void ApplyHex_Click(object sender, RoutedEventArgs e)
    {
        if (ThemeManager.ParseHex(HexBox.Text) is { } hex) Services.Settings.Update(s => s.Accent = hex);
        else MainWindow.Instance.ShowToast("Couleur invalide : utilise le format #RRGGBB (ex. #FF8A1F).");
    }

    private void ResetAppearance_Click(object sender, RoutedEventArgs e) =>
        Services.Settings.Update(s =>
        {
            s.Accent = AppSettingsData.DefaultAccent;
            s.Background = BackgroundStyle.Night;
            s.PosterSize = PosterSize.Regular;
            s.LiveLayout = LiveLayout.Grid;
        });

    // ── Masqués ───────────────────────────────────────────────────────────

    private void BuildHidden()
    {
        var hidden = Services.Library.HiddenItems;
        HiddenCaption.Text = hidden.Count == 0
            ? "Rien de masqué. Clic droit sur une carte → « Masquer » pour cacher une chaîne ou un film."
            : $"{hidden.Count} élément(s) masqué(s).";
        HiddenRows.Children.Clear();
        foreach (var item in hidden.Take(200))
        {
            var show = new Button { Content = "Afficher", Style = (Style)FindResource("GhostButton") };
            var id = item.Id;
            show.Click += (_, _) => Services.Customization.SetHidden(id, false);
            var row = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
            DockPanel.SetDock(show, Dock.Right);
            row.Children.Add(show);
            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(new TextBlock { Text = item.Name, FontSize = 14 });
            texts.Children.Add(new TextBlock { Text = $"{item.Kind.Title()} · {item.Group}", Style = (Style)FindResource("Caption"), FontSize = 12 });
            row.Children.Add(texts);
            HiddenRows.Children.Add(new Border
            {
                Background = (Brush)FindResource("SurfaceBrush"),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(16, 8, 10, 8),
                Margin = new Thickness(0, 0, 0, 6),
                Child = row,
            });
        }
    }

    // ── Divers ────────────────────────────────────────────────────────────

    private void BuildShortcuts()
    {
        var shortcuts = new (string Keys, string Action)[]
        {
            ("Ctrl + V", "Coller un lien de flux ou de playlist"),
            ("Ctrl + N", "Ajouter un lien"),
            ("Ctrl + F", "Rechercher"),
            ("Ctrl + 1 … 6", "Pour toi · Direct · Films · Séries · Foot · Mes liens"),
            ("F5", "Actualiser la playlist"),
            ("Alt + ← / Retour arrière", "Revenir en arrière"),
            ("Espace", "Lecture / pause (lecteur)"),
            ("↑ ↓ / Pg préc. Pg suiv.", "Chaîne précédente / suivante (direct)"),
            ("← →", "Reculer / avancer de 10 s (films)"),
            ("F ou double-clic", "Plein écran"),
            ("M · L · Échap", "Muet · liste des chaînes · quitter"),
            ("R", "Enregistrer le flux / arrêter"),
            ("N", "Épisode suivant"),
        };
        foreach (var (keys, action) in shortcuts)
        {
            var row = new DockPanel { Margin = new Thickness(0, 6, 0, 6) };
            var keyText = new TextBlock { Text = keys, Width = 230, FontWeight = FontWeights.SemiBold, FontSize = 14 };
            DockPanel.SetDock(keyText, Dock.Left);
            row.Children.Add(keyText);
            row.Children.Add(new TextBlock { Text = action, FontSize = 14, Foreground = (Brush)FindResource("TextSecondaryBrush") });
            Shortcuts.Children.Add(row);
        }
    }

    private void OpenData_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{AppPaths.Root}\"") { UseShellExecute = true });
        }
        catch
        {
            MainWindow.Instance.ShowToast(AppPaths.Root);
        }
    }
}
