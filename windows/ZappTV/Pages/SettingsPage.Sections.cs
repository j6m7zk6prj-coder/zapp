using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Core.Football;
using ZappTV.Dialogs;
using ZappTV.Foot;

namespace ZappTV.Pages;

/// <summary>Réglages : profil, accueil, foot et lecteur.</summary>
public partial class SettingsPage
{
    private static AppSettingsData Data => Services.Settings.Data;

    private Border Group(params UIElement[] children)
    {
        var panel = new StackPanel();
        for (var i = 0; i < children.Length; i++)
        {
            if (i > 0) panel.Children.Add(new Border { Height = 1, Background = (Brush)FindResource("HairlineBrush"), Margin = new Thickness(0, 4, 0, 4) });
            panel.Children.Add(children[i]);
        }
        return new Border
        {
            Background = (Brush)FindResource("SurfaceBrush"),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(20, 8, 16, 8),
            Margin = new Thickness(0, 12, 0, 0),
            Child = panel,
        };
    }

    private UIElement Row(string title, string? caption, UIElement control)
    {
        var row = new DockPanel { Margin = new Thickness(0, 8, 0, 8) };
        if (control is FrameworkElement fe) fe.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(control, Dock.Right);
        row.Children.Add(control);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 16, 0) };
        texts.Children.Add(new TextBlock { Text = title, FontSize = 15, FontWeight = FontWeights.SemiBold });
        if (caption != null) texts.Children.Add(new TextBlock { Text = caption, Style = (Style)FindResource("Caption"), FontSize = 12, Margin = new Thickness(0, 2, 0, 0) });
        row.Children.Add(texts);
        return row;
    }

    private UIElement Toggle(string title, string? caption, bool value, Action<AppSettingsData, bool> set)
    {
        var button = new Button
        {
            Style = (Style)FindResource(value ? "PillSelectedButton" : "PillButton"),
            Content = value ? "Activé" : "Désactivé",
            MinWidth = 110,
        };
        button.Click += (_, _) => Services.Settings.Update(s => set(s, !value));
        return Row(title, caption, button);
    }

    private UIElement Choices<T>(string title, string? caption, IEnumerable<(T Value, string Label)> options, T current, Action<AppSettingsData, T> set)
    {
        var panel = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
        foreach (var (value, label) in options)
        {
            var chip = Chip(label, EqualityComparer<T>.Default.Equals(value, current), () => Services.Settings.Update(s => set(s, value)));
            chip.Margin = new Thickness(6, 0, 0, 0);
            panel.Children.Add(chip);
        }
        return Row(title, caption, panel);
    }

    private Button ActionButton(string text, Action onClick, string style = "GhostButton")
    {
        var button = new Button { Style = (Style)FindResource(style), Content = text };
        button.Click += (_, _) => onClick();
        return button;
    }

    // ── Profil ────────────────────────────────────────────────────────────

    private void BuildProfile()
    {
        ProfileSection.Children.Clear();
        var profile = Services.Profiles.Active;
        var head = new DockPanel();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        buttons.Children.Add(ActionButton("Modifier", () => new ProfileEditWindow(profile).ShowDialog()));
        var manage = ActionButton("Changer / gérer les profils", () => new ProfilesWindow().ShowDialog(), "AccentButton");
        manage.Margin = new Thickness(10, 0, 0, 0);
        buttons.Children.Add(manage);
        DockPanel.SetDock(buttons, Dock.Right);
        head.Children.Add(buttons);
        var who = new StackPanel { Orientation = Orientation.Horizontal };
        who.Children.Add(ProfilesWindow.Avatar(profile.Initial, ThemeManager.ColorOf(profile.Color), false, 48));
        var texts = new StackPanel { Margin = new Thickness(14, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(new TextBlock { Text = profile.Name, FontSize = 17, FontWeight = FontWeights.Bold });
        var data = Services.Profiles.Current;
        texts.Children.Add(new TextBlock
        {
            Text = $"{data.Favorites.Count} favori(s) · {data.Leagues.Count} compétition(s) · {data.Teams.Count} équipe(s) · {Services.Profiles.Profiles.Count} profil(s) au total",
            Style = (Style)FindResource("Caption"),
            FontSize = 12,
        });
        who.Children.Add(texts);
        head.Children.Add(who);

        var history = ActionButton("Effacer l'historique", () =>
        {
            Services.Profiles.ClearHistory();
            MainWindow.Instance.ShowToast("Historique effacé pour ce profil.");
        });
        ProfileSection.Children.Add(Group(head, Row("Historique de lecture", "Chaînes récentes et « Reprendre la lecture » de ce profil.", history)));
    }

    // ── Accueil ───────────────────────────────────────────────────────────

    private void BuildHome()
    {
        HomeSection.Children.Clear();
        var start = Choices<string>("Onglet au démarrage", null,
            [("home", "Pour toi"), ("live", "Direct"), ("foot", "Foot"), ("movies", "Films"), ("series", "Séries"), ("links", "Mes liens")],
            Data.StartPage, (s, v) => s.StartPage = v);
        HomeSection.Children.Add(Group(
            start,
            Toggle("Défilement automatique de la bannière", "La bannière « à la une » change toute seule toutes les 8 s.", Data.HeroAutoplay, (s, v) => s.HeroAutoplay = v),
            Toggle("Afficher l'heure", "Horloge en haut à droite.", Data.ShowClock, (s, v) => s.ShowClock = v)));

        var caption = new TextBlock { Text = "Sections de « Pour toi » : coche celles à afficher et change leur ordre.", Style = (Style)FindResource("Caption"), Margin = new Thickness(2, 16, 0, 0) };
        HomeSection.Children.Add(caption);

        var sections = Data.OrderedHomeSections();
        var rows = new List<UIElement>();
        for (var i = 0; i < sections.Count; i++)
        {
            var index = i;
            var section = sections[i];
            var row = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
            var arrows = new StackPanel { Orientation = Orientation.Horizontal };
            var up = new Button { Style = (Style)FindResource("IconButton"), Content = UiFactory.Icon("", 12), ToolTip = "Monter", IsEnabled = i > 0 };
            up.Click += (_, _) => MoveSection(index, -1);
            var down = new Button { Style = (Style)FindResource("IconButton"), Content = UiFactory.Icon("", 12), ToolTip = "Descendre", IsEnabled = i < sections.Count - 1 };
            down.Click += (_, _) => MoveSection(index, 1);
            arrows.Children.Add(up);
            arrows.Children.Add(down);
            DockPanel.SetDock(arrows, Dock.Right);
            row.Children.Add(arrows);
            var check = new CheckBox
            {
                Content = new TextBlock { Text = HomeSectionCatalog.TitleOf(section.Key), FontSize = 14 },
                IsChecked = section.Visible,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center,
            };
            check.Click += (_, _) => Services.Settings.Update(s =>
            {
                var list = s.OrderedHomeSections();
                list[index].Visible = check.IsChecked == true;
                s.HomeSections = list;
            });
            row.Children.Add(check);
            rows.Add(row);
        }
        var reset = ActionButton("Ordre par défaut", () => Services.Settings.Update(s => s.HomeSections = []));
        reset.HorizontalAlignment = HorizontalAlignment.Left;
        reset.Margin = new Thickness(0, 8, 0, 4);
        rows.Add(reset);
        var listPanel = new StackPanel();
        foreach (var r in rows) listPanel.Children.Add(r);
        HomeSection.Children.Add(Group(listPanel));
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
        FootSection.Children.Clear();
        var data = Services.Profiles.Current;
        var follow = ActionButton("Choisir…", () => new FootFollowWindow().ShowDialog(), "AccentButton");
        var leagues = data.Leagues.Count == 0 ? "Aucune" : string.Join(", ", data.Leagues.Select(s => LeagueCatalog.NameOf(s)));
        var teams = data.Teams.Count == 0 ? "aucune équipe" : string.Join(", ", data.Teams.Select(t => t.Name));

        FootSection.Children.Add(Group(
            Row("Ligues et équipes suivies", $"{leagues} · {teams}", follow),
            Toggle("Mode anti-spoiler", "Masque les scores des matchs terminés (un clic sur le match pour les révéler).", Data.HideScores, (s, v) => s.HideScores = v),
            Toggle("Point « en direct » sur l'onglet Foot", "Signale qu'un match d'une compétition suivie est en cours.", Data.ShowLiveBadge, (s, v) => s.ShowLiveBadge = v),
            Choices<int>("Actualisation des scores en direct", null,
                [(30, "30 s"), (60, "1 min"), (120, "2 min"), (300, "5 min")],
                Data.FootRefreshSeconds, (s, v) => s.FootRefreshSeconds = v)));

        var caption = new TextBlock
        {
            Text = "Où regarder : diffuseur habituel de chaque compétition suivie et chaînes de ta playlist associées. « Modifier » pour épingler une chaîne ou changer les mots-clés de recherche.",
            Style = (Style)FindResource("Caption"),
            Margin = new Thickness(2, 16, 0, 0),
        };
        FootSection.Children.Add(caption);
        var rows = new List<UIElement>();
        foreach (var slug in data.Leagues)
        {
            var name = LeagueCatalog.NameOf(slug);
            var label = Data.BroadcasterLabel(slug);
            var channels = Services.ChannelsFor(slug, 3).Select(c => c.Name).ToList();
            var detail = (label.Length > 0 ? label : "Diffuseur non renseigné")
                + (channels.Count > 0 ? $"  →  {string.Join(", ", channels)}" : Services.Library.Count(MediaKind.Live) > 0 ? "  →  aucune chaîne trouvée" : "");
            var edit = ActionButton("Modifier", () => new ChannelPickerWindow(slug, name).ShowDialog());
            rows.Add(Row(name, detail, edit));
        }
        if (rows.Count > 0) FootSection.Children.Add(Group([.. rows]));

        var source = new TextBlock
        {
            Text = "Scores, calendriers, statistiques et classements : données publiques d'ESPN. Diffuseurs en France : saison 2026-2027, modifiables ci-dessus.",
            Style = (Style)FindResource("Caption"),
            FontSize = 12,
            Margin = new Thickness(2, 10, 0, 0),
        };
        FootSection.Children.Add(source);
    }

    // ── Lecteur ───────────────────────────────────────────────────────────

    private void BuildPlayer()
    {
        PlayerSection.Children.Clear();
        PlayerSection.Children.Add(Group(
            Toggle("Reprendre là où je me suis arrêté", "Films et épisodes repartent à la dernière position.", Data.ResumePlayback, (s, v) => s.ResumePlayback = v),
            Toggle("Ouvrir le lecteur en plein écran", null, Data.PlayerStartsFullscreen, (s, v) => s.PlayerStartsFullscreen = v),
            Toggle("Décodage matériel", "Plus fluide et moins gourmand. Désactive-le si l'image saccade ou reste noire.", Data.HardwareDecoding, (s, v) => s.HardwareDecoding = v),
            Choices<int>("Mémoire tampon réseau", "Plus elle est grande, moins ça coupe, mais le direct a plus de retard.",
                [(800, "Faible"), (1500, "Normale"), (3000, "Grande"), (6000, "Très grande")],
                Data.NetworkCacheMs, (s, v) => s.NetworkCacheMs = v)));
    }
}
