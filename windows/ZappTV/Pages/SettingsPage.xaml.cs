using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Core.Football;
using ZappTV.Dialogs;
using ZappTV.Foot;

namespace ZappTV.Pages;

/// <summary>Réglages façon « Réglages Système » du Mac : catégories à gauche, rangées groupées à droite.</summary>
public partial class SettingsPage : UserControl
{
    private sealed record Category(string Key, string Title, string Glyph, uint Color);

    private static readonly Category[] All =
    [
        new("profile", "Profil", "", 0x8B7CFF),
        new("sources", "Playlists et liens", "", 0x0A84FF),
        new("home", "Accueil", "", 0xFF9F0A),
        new("foot", "Foot", "", 0x30D158),
        new("tmdb", "Films et séries", "", 0xBF5AF2),
        new("player", "Lecteur", "", 0xFF453A),
        new("appearance", "Apparence", "", 0x64D2FF),
        new("hidden", "Éléments masqués", "", 0x8E8E93),
        new("about", "À propos", "", 0x8E8E93),
    ];

    private static string _current = "profile";
    private static AppSettingsData Data => Services.Settings.Data;

    public SettingsPage()
    {
        InitializeComponent();
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
        BuildCategories();
        var offset = PaneScroller.VerticalOffset;
        Pane.Children.Clear();
        var category = All.First(c => c.Key == _current);
        Pane.Children.Add(new TextBlock
        {
            Text = category.Title,
            FontFamily = (FontFamily)FindResource("DisplayFont"),
            FontSize = 26,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(4, 0, 0, 18),
        });
        switch (_current)
        {
            case "profile": BuildProfile(); break;
            case "sources": BuildSources(); break;
            case "home": BuildHome(); break;
            case "foot": BuildFoot(); break;
            case "tmdb": BuildTmdb(); break;
            case "player": BuildPlayer(); break;
            case "appearance": BuildAppearance(); break;
            case "hidden": BuildHidden(); break;
            default: BuildAbout(); break;
        }
        PaneScroller.ScrollToVerticalOffset(offset);
    }

    private void Open(string key)
    {
        _current = key;
        PaneScroller.ScrollToVerticalOffset(0);
        Refresh();
    }

    private void BuildCategories()
    {
        Categories.Children.Clear();
        foreach (var category in All)
        {
            var selected = category.Key == _current;
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            // Même présentation que la barre latérale principale : icône simple + libellé.
            row.Children.Add(new TextBlock { Text = category.Glyph, Style = (Style)FindResource("NavIcon") });
            row.Children.Add(new TextBlock { Text = category.Title, FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
            var item = new RadioButton
            {
                Style = (Style)FindResource("SidebarItem"),
                Content = row,
                IsChecked = selected,
                GroupName = "SettingsCategories",
                Height = 34,
            };
            var key = category.Key;
            item.Checked += (_, _) => { if (_current != key) Open(key); };
            Categories.Children.Add(item);
        }
    }

    // ── Éléments d'interface ──────────────────────────────────────────────

    private static Border IconChip(string glyph, uint color, double size = 26) => new()
    {
        Width = size,
        Height = size,
        // Toutes les icônes ont la même forme : un cercle de verre.
        CornerRadius = new CornerRadius(size / 2),
        Background = (Brush)Application.Current.FindResource("GlassFill"),
        BorderBrush = (Brush)Application.Current.FindResource("GlassStroke"),
        BorderThickness = new Thickness(1),
        VerticalAlignment = VerticalAlignment.Center,
        Child = new TextBlock
        {
            Text = glyph,
            FontFamily = (FontFamily)Application.Current.FindResource("IconFont"),
            FontSize = size * 0.5,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        },
    };

    /// <summary>Groupe de rangées arrondi, séparées par un filet.</summary>
    private void Group(params UIElement[] rows) => Group(null, null, rows);

    private void Group(string? header, string? footer, params UIElement[] rows)
    {
        if (header != null)
            Pane.Children.Add(new TextBlock { Text = header, FontSize = 13, FontWeight = FontWeights.SemiBold, Margin = new Thickness(4, 6, 0, 8) });
        var panel = new StackPanel();
        for (var i = 0; i < rows.Length; i++)
        {
            if (i > 0) panel.Children.Add(new Border { Height = 1, Background = (Brush)FindResource("HairlineBrush"), Margin = new Thickness(14, 0, 0, 0) });
            panel.Children.Add(rows[i]);
        }
        Pane.Children.Add(new Border
        {
            Background = (Brush)FindResource("GlassPanel"),
            BorderBrush = (Brush)FindResource("GlassPanelStroke"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(16),
            Child = panel,
            Margin = new Thickness(0, 0, 0, footer == null ? 22 : 6),
        });
        if (footer != null)
        {
            Pane.Children.Add(new TextBlock
            {
                Text = footer,
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
                Foreground = (Brush)FindResource("TextSecondaryBrush"),
                Margin = new Thickness(4, 0, 0, 22),
            });
        }
    }

    private UIElement Row(string title, string? subtitle, UIElement? control, Action? onClick = null)
    {
        var row = new DockPanel { MinHeight = 44, Margin = new Thickness(14, 6, 12, 6) };
        if (control != null)
        {
            if (control is FrameworkElement element) element.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(control, Dock.Right);
            row.Children.Add(control);
        }
        else if (onClick != null)
        {
            var chevron = new TextBlock { Text = "", Style = (Style)FindResource("Icon"), FontSize = 11, Opacity = 0.45, VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(chevron, Dock.Right);
            row.Children.Add(chevron);
        }
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 16, 0) };
        texts.Children.Add(new TextBlock { Text = title, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis });
        if (subtitle != null)
        {
            texts.Children.Add(new TextBlock
            {
                Text = subtitle,
                FontSize = 12,
                Foreground = (Brush)FindResource("TextSecondaryBrush"),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 2, 0, 0),
            });
        }
        row.Children.Add(texts);
        if (onClick == null) return row;
        var button = new Button { Style = (Style)FindResource("PlainButton"), Content = row, HorizontalContentAlignment = HorizontalAlignment.Stretch };
        button.Click += (_, _) => onClick();
        return button;
    }

    private UIElement Toggle(string title, string? subtitle, bool value, Action<AppSettingsData, bool> set)
    {
        var toggle = new ToggleButton { Style = (Style)FindResource("Switch"), IsChecked = value };
        toggle.Click += (_, _) => Services.Settings.Update(s => set(s, toggle.IsChecked == true));
        return Row(title, subtitle, toggle);
    }

    /// <summary>Contrôle segmenté (comme sur Mac).</summary>
    private static Border Segmented<T>(IEnumerable<(T Value, string Label)> options, T current, Action<T> set)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (value, label) in options)
        {
            var selected = EqualityComparer<T>.Default.Equals(value, current);
            var segment = new Button
            {
                Style = (Style)Application.Current.FindResource("PlainButton"),
                Content = new Border
                {
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(12, 5, 12, 5),
                    Background = selected ? (Brush)Application.Current.FindResource("GlassFillPressed") : Brushes.Transparent,
                    BorderBrush = selected ? (Brush)Application.Current.FindResource("GlassStroke") : Brushes.Transparent,
                    BorderThickness = new Thickness(1),
                    Child = new TextBlock { Text = label, FontSize = 12, FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal },
                },
            };
            var v = value;
            segment.Click += (_, _) => set(v);
            panel.Children.Add(segment);
        }
        return new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(2),
            Child = panel,
        };
    }

    private Button Push(string text, Action onClick, bool prominent = false)
    {
        var button = new Button { Style = (Style)FindResource(prominent ? "AccentButton" : "GhostButton"), Content = text, Height = 30, Padding = new Thickness(14, 0, 14, 0) };
        button.Click += (_, _) => onClick();
        return button;
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { MainWindow.Instance.ShowToast(url); }
    }

    // ── Profil ────────────────────────────────────────────────────────────

    private void BuildProfile()
    {
        var profile = Services.Profiles.Active;
        var data = Services.Profiles.Current;
        var head = new DockPanel { Margin = new Thickness(14, 12, 12, 12) };
        var edit = Push("Modifier", () => new ProfileEditWindow(profile).ShowDialog());
        DockPanel.SetDock(edit, Dock.Right);
        head.Children.Add(edit);
        head.Children.Add(ProfilesWindow.Avatar(profile.Initial, ThemeManager.ColorOf(profile.Color), false, 44));
        var texts = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(new TextBlock { Text = profile.Name, FontSize = 15, FontWeight = FontWeights.SemiBold });
        texts.Children.Add(new TextBlock
        {
            Text = $"{data.Favorites.Count} dans ma liste · {data.Leagues.Count} compétitions · {data.Teams.Count} équipes",
            FontSize = 12,
            Foreground = (Brush)FindResource("TextSecondaryBrush"),
        });
        head.Children.Add(texts);
        Group(head, Row("Changer de profil", $"{Services.Profiles.Profiles.Count} profil(s)", null, () => new ProfilesWindow().ShowDialog()));

        Group(null, "Chaînes regardées récemment et « Reprendre la lecture ».",
            Row("Historique de lecture", null, Push("Effacer", () =>
            {
                Services.Profiles.ClearHistory();
                MainWindow.Instance.ShowToast("Historique effacé.");
            })));
    }

    // ── Playlists et liens ────────────────────────────────────────────────

    private void BuildSources()
    {
        var active = Services.Playlists.Active;
        var rows = new List<UIElement>();
        foreach (var playlist in Services.Playlists.Playlists)
        {
            var isActive = playlist.Id == active?.Id;
            var detail = playlist.Label + (isActive && Services.Library.ErrorMessage is { } error ? $" · {error}" : isActive ? $" · {Services.Library.Items.Count:N0} éléments" : "");
            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            if (isActive)
            {
                actions.Children.Add(new TextBlock { Text = "Active", FontSize = 12, Foreground = (Brush)FindResource("AccentBrush"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) });
            }
            else
            {
                var activate = Push("Activer", () => Services.Playlists.SetActive(playlist.Id));
                activate.Margin = new Thickness(0, 0, 6, 0);
                actions.Children.Add(activate);
            }
            var delete = new Button { Style = (Style)FindResource("IconButton"), Content = UiFactory.Icon("", 13), ToolTip = "Supprimer" };
            delete.Click += (_, _) =>
            {
                if (MessageBox.Show(Window.GetWindow(this)!, $"Supprimer la playlist « {playlist.Name} » ?", "iTv", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
                    Services.Playlists.Remove(playlist);
            };
            actions.Children.Add(delete);
            rows.Add(Row(playlist.Name, detail, actions));
        }
        if (rows.Count == 0) rows.Add(Row("Aucune playlist", "Tu peux aussi ajouter des liens un par un.", null));
        Group("Playlists", "La playlist active est rechargée toutes les 12 h (F5 pour forcer).", [.. rows]);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, -8, 0, 22) };
        buttons.Children.Add(Push("Ajouter une playlist…", () => new AddPlaylistWindow().ShowDialog(), prominent: true));
        var refresh = Push(Services.Library.IsLoading ? "Actualisation…" : "Actualiser", () => Services.LoadActivePlaylist(force: true));
        refresh.Margin = new Thickness(8, 0, 0, 0);
        refresh.IsEnabled = !Services.Library.IsLoading && active != null;
        buttons.Children.Add(refresh);
        Pane.Children.Add(buttons);

        Group("Mes liens", null,
            Row("Gérer mes liens", $"{Services.Customization.Links.Count} lien(s) ajouté(s) à la main", null, () => MainWindow.Instance.ShowSection("links")),
            Row("Ajouter un lien…", "N'importe quel format : m3u8, ts, mp4, rtmp…", null, () => new LinkEditorWindow(null).ShowDialog()));
    }

    // ── Accueil ───────────────────────────────────────────────────────────

    private void BuildHome()
    {
        Group(
            Row("Onglet au démarrage", null, Segmented<string>(
                [("home", "Accueil"), ("live", "Direct"), ("foot", "Foot"), ("movies", "Films"), ("series", "Séries"), ("links", "Liens")],
                Data.StartPage, v => Services.Settings.Update(s => s.StartPage = v))),
            Toggle("Défilement automatique de « À la une »", null, Data.HeroAutoplay, (s, v) => s.HeroAutoplay = v));

        var sections = Data.OrderedHomeSections();
        var rows = new List<UIElement>();
        for (var i = 0; i < sections.Count; i++)
        {
            var index = i;
            var section = sections[i];
            var controls = new StackPanel { Orientation = Orientation.Horizontal };
            var up = new Button { Style = (Style)FindResource("IconButton"), Content = UiFactory.Icon("", 11), ToolTip = "Monter", IsEnabled = i > 0, Width = 30, Height = 30 };
            up.Click += (_, _) => MoveSection(index, -1);
            var down = new Button { Style = (Style)FindResource("IconButton"), Content = UiFactory.Icon("", 11), ToolTip = "Descendre", IsEnabled = i < sections.Count - 1, Width = 30, Height = 30, Margin = new Thickness(0, 0, 10, 0) };
            down.Click += (_, _) => MoveSection(index, 1);
            var toggle = new ToggleButton { Style = (Style)FindResource("Switch"), IsChecked = section.Visible };
            toggle.Click += (_, _) => Services.Settings.Update(s =>
            {
                var list = s.OrderedHomeSections();
                list[index].Visible = toggle.IsChecked == true;
                s.HomeSections = list;
            });
            controls.Children.Add(up);
            controls.Children.Add(down);
            controls.Children.Add(toggle);
            rows.Add(Row(HomeSectionCatalog.TitleOf(section.Key), null, controls));
        }
        Group("Rangées de l'accueil", "Active ou désactive les rangées et change leur ordre avec les flèches.", [.. rows]);
        var reset = Push("Rétablir l'ordre par défaut", () => Services.Settings.Update(s => s.HomeSections = []));
        reset.HorizontalAlignment = HorizontalAlignment.Left;
        reset.Margin = new Thickness(0, -8, 0, 22);
        Pane.Children.Add(reset);
    }

    private static void MoveSection(int index, int delta) => Services.Settings.Update(s =>
    {
        var list = s.OrderedHomeSections();
        var target = index + delta;
        if (target < 0 || target >= list.Count) return;
        (list[index], list[target]) = (list[target], list[index]);
        s.HomeSections = list;
    });

    // ── Foot ──────────────────────────────────────────────────────────────

    private void BuildFoot()
    {
        var data = Services.Profiles.Current;
        Group(
            Row("Ligues et équipes suivies", $"{data.Leagues.Count} compétitions · {data.Teams.Count} équipes", null, () => new FootFollowWindow().ShowDialog()),
            Toggle("Masquer les scores (anti-spoiler)", null, Data.HideScores, (s, v) => s.HideScores = v),
            Toggle("Point « en direct » dans la barre latérale", null, Data.ShowLiveBadge, (s, v) => s.ShowLiveBadge = v),
            Row("Actualisation des scores", null, Segmented<int>([(30, "30 s"), (60, "1 min"), (120, "2 min"), (300, "5 min")],
                Data.FootRefreshSeconds, v => Services.Settings.Update(s => s.FootRefreshSeconds = v))));

        if (data.Leagues.Count == 0) return;
        var rows = new List<UIElement>();
        foreach (var slug in data.Leagues)
        {
            var name = LeagueCatalog.NameOf(slug);
            var channels = Services.ChannelsFor(slug, 2).Select(c => c.Name).ToList();
            var label = Data.BroadcasterLabel(slug);
            var detail = channels.Count > 0 ? string.Join(", ", channels) : label.Length > 0 ? label : "Non renseigné";
            rows.Add(Row(name, detail, null, () => new ChannelPickerWindow(slug, name).ShowDialog()));
        }
        Group("Où regarder", "Diffuseurs en France pour la saison 2026-2027. Choisis la bonne chaîne de ta playlist pour chaque compétition.", [.. rows]);
    }

    // ── Films et séries (TMDB) ────────────────────────────────────────────

    private void BuildTmdb()
    {
        var box = new TextBox { Style = (Style)FindResource("Field"), Text = Data.TmdbKey, Tag = "Clé d'API (v3) ou jeton de lecture (v4)", Width = 300, FontSize = 12 };
        var status = new TextBlock { FontSize = 12, Foreground = (Brush)FindResource("TextSecondaryBrush"), Margin = new Thickness(14, 0, 12, 10), TextWrapping = TextWrapping.Wrap };
        var save = Push("Enregistrer", async () =>
        {
            var key = box.Text.Trim();
            if (key.Length == 0)
            {
                Services.Settings.Update(s => s.TmdbKey = "");
                return;
            }
            status.Text = "Vérification…";
            if (await new ZappTV.Core.Tmdb.TmdbClient(key).ValidateAsync())
            {
                Services.Settings.Update(s => s.TmdbKey = key);
                MainWindow.Instance.ShowToast("Clé TMDB enregistrée : les fiches sont activées.");
            }
            else
            {
                status.Text = "Clé refusée par TMDB (ou pas de connexion).";
            }
        }, prominent: true);
        save.Margin = new Thickness(8, 0, 0, 0);
        var keyRow = new StackPanel { Orientation = Orientation.Horizontal };
        keyRow.Children.Add(box);
        keyRow.Children.Add(save);
        var block = new StackPanel();
        block.Children.Add(Row("Clé TMDB", Data.TmdbKey.Trim().Length > 0 ? "Fiches activées" : "Désactivées", keyRow));
        block.Children.Add(status);
        Group(null, "Grandes affiches, notes, résumés, distribution, bandes-annonces et tendances. Clé gratuite : crée un compte sur themoviedb.org → Paramètres → API → Créer (Développeur, usage personnel).",
            block,
            Row("Obtenir une clé gratuite", "themoviedb.org", null, () => OpenUrl("https://www.themoviedb.org/settings/api")),
            Row("Vider le cache des fiches", null, Push("Vider", () =>
            {
                Services.ClearTmdbCache();
                MainWindow.Instance.ShowToast("Cache des fiches vidé.");
            })));
    }

    // ── Lecteur ───────────────────────────────────────────────────────────

    private void BuildPlayer()
    {
        Group(
            Toggle("Reprendre là où je me suis arrêté", null, Data.ResumePlayback, (s, v) => s.ResumePlayback = v),
            Toggle("Épisode suivant automatique", null, Data.AutoPlayNext, (s, v) => s.AutoPlayNext = v),
            Toggle("Ouvrir en plein écran", null, Data.PlayerStartsFullscreen, (s, v) => s.PlayerStartsFullscreen = v));
        Group(null, "Désactive le décodage matériel si l'image saccade ou reste noire. Une mémoire tampon plus grande coupe moins mais retarde le direct.",
            Toggle("Décodage matériel", null, Data.HardwareDecoding, (s, v) => s.HardwareDecoding = v),
            Row("Mémoire tampon", null, Segmented<int>([(800, "Faible"), (1500, "Normale"), (3000, "Grande"), (6000, "Max")],
                Data.NetworkCacheMs, v => Services.Settings.Update(s => s.NetworkCacheMs = v))));
        Group(null, "Touche R ou bouton ⏺ dans le lecteur. Usage privé uniquement.",
            Row("Enregistrements", "Vidéos\\iTv", null, () =>
            {
                System.IO.Directory.CreateDirectory(ZappTV.Player.PlayerWindow.RecordingsFolder);
                OpenUrl(ZappTV.Player.PlayerWindow.RecordingsFolder);
            }));
    }

    // ── Apparence ─────────────────────────────────────────────────────────

    private void BuildAppearance()
    {
        var swatches = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (name, hex) in AppSettingsData.AccentPresets)
        {
            var selected = Data.Accent == hex;
            var dot = new Grid { Width = 22, Height = 22, Margin = new Thickness(0, 0, 8, 0) };
            dot.Children.Add(new Border { CornerRadius = new CornerRadius(11), Background = new SolidColorBrush(ThemeManager.ColorOf(hex)) });
            if (selected) dot.Children.Add(new Border { CornerRadius = new CornerRadius(11), BorderBrush = Brushes.White, BorderThickness = new Thickness(2) });
            var button = new Button { Style = (Style)FindResource("PlainButton"), Content = dot, ToolTip = name };
            var value = hex;
            button.Click += (_, _) => Services.Settings.Update(s => s.Accent = value);
            swatches.Children.Add(button);
        }
        Group(
            Row("Couleur d'accent", null, swatches),
            Row("Fond", null, Segmented(Enum.GetValues<BackgroundStyle>().Select(b => (b, b.Title())), Data.Background, v => Services.Settings.Update(s => s.Background = v))),
            Row("Taille des affiches", null, Segmented(Enum.GetValues<PosterSize>().Select(p => (p, p.Title())), Data.PosterSize, v => Services.Settings.Update(s => s.PosterSize = v))),
            Row("Chaînes en direct", null, Segmented(Enum.GetValues<LiveLayout>().Select(l => (l, l.Title())), Data.LiveLayout, v => Services.Settings.Update(s => s.LiveLayout = v))));
        var reset = Push("Rétablir l'apparence d'origine", () => Services.Settings.Update(s =>
        {
            s.Accent = AppSettingsData.DefaultAccent;
            s.Background = BackgroundStyle.Oled;
            s.PosterSize = PosterSize.Regular;
            s.LiveLayout = LiveLayout.Grid;
        }));
        reset.HorizontalAlignment = HorizontalAlignment.Left;
        Pane.Children.Add(reset);
    }

    // ── Masqués ───────────────────────────────────────────────────────────

    private void BuildHidden()
    {
        var hidden = Services.Library.HiddenItems;
        if (hidden.Count == 0)
        {
            Group(null, "Clic droit sur une chaîne ou un film → « Masquer » pour le cacher.", Row("Rien de masqué", null, null));
            return;
        }
        var rows = hidden.Take(200).Select(item =>
        {
            var id = item.Id;
            return Row(item.Name, $"{item.Kind.Title()} · {item.Group}", Push("Afficher", () => Services.Customization.SetHidden(id, false)));
        }).ToArray();
        Group(null, $"{hidden.Count} élément(s) masqué(s).", rows);
    }

    // ── À propos ──────────────────────────────────────────────────────────

    private void BuildAbout()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";
        Group(null, "iTv est uniquement un lecteur : il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des liens et des playlists auxquels tu as légalement accès.",
            Row("Version", null, new TextBlock { Text = version, FontSize = 13, Foreground = (Brush)FindResource("TextSecondaryBrush") }),
            Row("Dossier des données", "Liens, playlists, profils et réglages", null, () => OpenUrl(AppPaths.Root)));

        var shortcuts = new (string Keys, string Action)[]
        {
            ("Ctrl + 1 … 6", "Accueil · Direct · Films · Séries · Foot · Mes liens"),
            ("Ctrl + F", "Rechercher"),
            ("Ctrl + V", "Coller un lien"),
            ("F5", "Actualiser la playlist"),
            ("Alt + ←", "Retour"),
            ("Espace", "Lecture / pause"),
            ("↑ ↓", "Chaîne précédente / suivante"),
            ("← →", "Reculer / avancer de 10 s"),
            ("F", "Plein écran"),
            ("R", "Enregistrer le flux"),
            ("N", "Épisode suivant"),
        };
        Group("Raccourcis clavier", null, shortcuts.Select(s => Row(s.Action, null,
            new TextBlock { Text = s.Keys, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = (Brush)FindResource("TextSecondaryBrush") })).ToArray());
    }
}
