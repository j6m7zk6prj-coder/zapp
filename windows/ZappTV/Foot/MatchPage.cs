using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using ZappTV.Core;
using ZappTV.Core.Football;
using static ZappTV.Foot.FootUi;

namespace ZappTV.Foot;

/// <summary>Fiche d'un match : score, où regarder, événements, statistiques, compositions, classement.</summary>
public sealed class MatchPage : UserControl
{
    private readonly StackPanel _root = new() { Margin = new Thickness(0, 0, 0, 48) };
    private readonly DispatcherTimer _timer = new();
    private Match _match;
    private MatchDetail? _detail;
    private bool _revealScore;
    private bool _loading;

    public MatchPage(Match match)
    {
        _match = match;
        Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _root, Focusable = false };
        _timer.Tick += async (_, _) => await LoadAsync();
        Loaded += async (_, _) =>
        {
            Services.Profiles.FootChanged += Render;
            Services.Library.Changed += Render;
            Render();
            await LoadAsync();
        };
        Unloaded += (_, _) =>
        {
            _timer.Stop();
            Services.Profiles.FootChanged -= Render;
            Services.Library.Changed -= Render;
        };
    }

    private async Task LoadAsync()
    {
        if (_loading) return;
        _loading = true;
        try
        {
            _detail = await Services.Foot.SummaryAsync(_match.Id, _match.LeagueSlug, _match.State == MatchState.Live);
            _match = _detail.Match with { Events = _match.Events };
        }
        catch (Exception)
        {
            // On garde les infos du calendrier si le détail n'est pas disponible.
        }
        finally
        {
            _loading = false;
        }
        if (!IsLoaded) return;
        Render();
        var live = _match.State == MatchState.Live || (_match.State == MatchState.Scheduled && _match.Date - DateTimeOffset.Now < TimeSpan.FromMinutes(15));
        _timer.Interval = TimeSpan.FromSeconds(Math.Max(20, Services.Settings.Data.FootRefreshSeconds / 2));
        if (live) _timer.Start(); else _timer.Stop();
    }

    private void Render()
    {
        if (!IsLoaded) return;
        _root.Children.Clear();
        _root.Children.Add(Hero());

        var body = new StackPanel { Margin = new Thickness(56, 0, 56, 0), MaxWidth = 1150, HorizontalAlignment = HorizontalAlignment.Left };
        _root.Children.Add(body);

        body.Children.Add(SectionHeader("Où regarder"));
        body.Children.Add(WhereToWatch());

        if (_detail is null)
        {
            var status = Secondary(_loading ? "Chargement des détails du match…" : "Détails indisponibles pour ce match.", 14);
            status.Margin = new Thickness(0, 24, 0, 0);
            body.Children.Add(status);
            return;
        }

        var hideDetails = ScoresHidden && _match.State == MatchState.Finished && !_revealScore;
        if (hideDetails)
        {
            body.Children.Add(SectionHeader("Résumé"));
            body.Children.Add(Secondary("Score, buts et statistiques masqués (mode anti-spoiler). Clique sur « Afficher le score » en haut pour les voir.", 14));
        }
        else
        {
            if (_detail.Events.Count > 0)
            {
                body.Children.Add(SectionHeader("Événements"));
                body.Children.Add(Card(EventsList(_detail.Events)));
            }
            if (_detail.Stats.Count > 0)
            {
                body.Children.Add(SectionHeader("Statistiques"));
                body.Children.Add(Card(StatsList(_detail.Stats), new Thickness(28, 18, 28, 18)));
            }
        }

        if (_detail.Lineups.Count == 2 && _detail.Lineups.Any(l => l.Players.Count > 0))
        {
            body.Children.Add(SectionHeader("Compositions"));
            body.Children.Add(Lineups(_detail.Lineups));
        }

        if (_detail.Standings.Count > 0)
        {
            body.Children.Add(SectionHeader($"Classement · {_match.LeagueName}", "Classement complet", () =>
                MainWindow.Instance.Push(new FootPage(FootPage.Tab.Standings, _match.LeagueSlug))));
            body.Children.Add(StandingsTable.Build(_detail.Standings, [_match.Home.Id, _match.Away.Id], [_match.Home.Name, _match.Away.Name], compact: true));
        }

        var info = new List<string>();
        if (_match.Venue is { Length: > 0 } venue) info.Add($"Stade : {venue}");
        if (_detail.Attendance is { } attendance) info.Add($"Spectateurs : {attendance}");
        if (info.Count > 0)
        {
            var footer = Secondary(string.Join("   ·   ", info), 13);
            footer.Margin = new Thickness(0, 26, 0, 0);
            body.Children.Add(footer);
        }
    }

    // ── En-tête ───────────────────────────────────────────────────────────

    private FrameworkElement Hero()
    {
        var m = _match;
        var bg = ThemeManager.Background;
        var background = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(1, 1),
            GradientStops =
            {
                new GradientStop(((SolidColorBrush)TeamBrush(m.Home.Color, Color.FromRgb(0x2A, 0x44, 0xD8))).Color, 0),
                new GradientStop(bg, 0.5),
                new GradientStop(((SolidColorBrush)TeamBrush(m.Away.Color, Color.FromRgb(0xA3, 0x12, 0x3A))).Color, 1),
            },
        };

        var grid = new Grid { Margin = new Thickness(56, 76, 56, 34), MaxWidth = 1000 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());

        grid.Children.Add(TeamBlock(m.Home));
        var away = TeamBlock(m.Away);
        Grid.SetColumn(away, 2);
        grid.Children.Add(away);

        var center = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var league = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 10) };
        league.Children.Add(Crest(LeagueCatalog.LogoFor(m.LeagueSlug), 20, m.LeagueName));
        var leagueName = Text(m.LeagueName, 13, FontWeights.SemiBold, opacity: 0.85);
        leagueName.Margin = new Thickness(8, 0, 0, 0);
        league.Children.Add(leagueName);
        center.Children.Add(league);

        if (m.State == MatchState.Scheduled || m.HomeScore is null)
        {
            var time = Text(m.Date.ToLocalTime().ToString("HH:mm"), 46, FontWeights.Black);
            time.HorizontalAlignment = HorizontalAlignment.Center;
            center.Children.Add(time);
            var day = Text(FootFormat.DayTitle(m.Date.ToLocalTime().Date), 15, opacity: 0.8);
            day.HorizontalAlignment = HorizontalAlignment.Center;
            center.Children.Add(day);
            if (m.State == MatchState.Postponed)
            {
                var badge = StatusBadge(m);
                badge.HorizontalAlignment = HorizontalAlignment.Center;
                badge.Margin = new Thickness(0, 8, 0, 0);
                center.Children.Add(badge);
            }
        }
        else
        {
            var (home, awayScore) = Score(m, _revealScore);
            var score = Text($"{home}  –  {awayScore}", 52, FontWeights.Black, m.State == MatchState.Live ? LiveBrush : null);
            score.HorizontalAlignment = HorizontalAlignment.Center;
            center.Children.Add(score);
            var badge = StatusBadge(m);
            badge.HorizontalAlignment = HorizontalAlignment.Center;
            badge.Margin = new Thickness(0, 6, 0, 0);
            center.Children.Add(badge);
            if (m.State == MatchState.Finished && ScoresHidden && !_revealScore)
            {
                var reveal = new Button { Style = S("GhostButton"), Content = "Afficher le score", Margin = new Thickness(0, 12, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
                reveal.Click += (_, _) =>
                {
                    _revealScore = true;
                    Render();
                };
                center.Children.Add(reveal);
            }
        }
        Grid.SetColumn(center, 1);
        grid.Children.Add(center);

        // Buteurs sous l'en-tête
        if (!(ScoresHidden && m.State == MatchState.Finished && !_revealScore))
        {
            var goals = (_detail?.Events ?? m.Events).Where(e => e.IsGoal).ToList();
            if (goals.Count > 0)
            {
                var scorers = new Grid { Margin = new Thickness(0, 0, 0, 0) };
                scorers.ColumnDefinitions.Add(new ColumnDefinition());
                scorers.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
                scorers.ColumnDefinitions.Add(new ColumnDefinition());
                var homeGoals = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
                var awayGoals = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
                foreach (var goal in goals)
                {
                    var line = Text($"⚽  {goal.Text} {goal.Clock}{(goal.Kind == MatchEventKind.Penalty ? " (pén.)" : goal.Kind == MatchEventKind.OwnGoal ? " (c.s.c.)" : "")}", 13, opacity: 0.85);
                    line.HorizontalAlignment = HorizontalAlignment.Center;
                    (goal.IsHome ? homeGoals : awayGoals).Children.Add(line);
                }
                scorers.Children.Add(homeGoals);
                Grid.SetColumn(awayGoals, 2);
                scorers.Children.Add(awayGoals);
                var stack = new StackPanel();
                stack.Children.Add(grid);
                scorers.Margin = new Thickness(56, -18, 56, 30);
                scorers.MaxWidth = 1000;
                stack.Children.Add(scorers);
                return new Border { Background = background, Child = stack };
            }
        }
        return new Border { Background = background, Child = grid };
    }

    private FrameworkElement TeamBlock(TeamRef team)
    {
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        panel.Children.Add(Crest(team.Logo, 104, team.Name));
        var name = Text(team.Name, 20, FontWeights.Bold);
        name.HorizontalAlignment = HorizontalAlignment.Center;
        name.TextAlignment = TextAlignment.Center;
        name.TextWrapping = TextWrapping.Wrap;
        name.MaxWidth = 280;
        name.Margin = new Thickness(0, 14, 0, 4);
        panel.Children.Add(name);
        var follow = Services.Profiles.FollowsTeam(team.Id);
        var star = Secondary(follow ? "★ Équipe suivie" : "Voir l'équipe ›", 12);
        star.HorizontalAlignment = HorizontalAlignment.Center;
        panel.Children.Add(star);
        var button = new Button { Style = S("TileButton"), Content = panel, ToolTip = $"Ouvrir la fiche de {team.Name}" };
        button.Click += (_, _) => MainWindow.Instance.Push(new TeamPage(team, _match.LeagueSlug));
        return button;
    }

    // ── Où regarder ───────────────────────────────────────────────────────

    private FrameworkElement WhereToWatch()
    {
        var panel = new StackPanel();
        var label = Services.Settings.Data.BroadcasterLabel(_match.LeagueSlug);
        panel.Children.Add(Text(label.Length > 0
            ? $"Diffuseur habituel en France : {label}"
            : "Diffuseur en France non renseigné pour cette compétition.", 15, FontWeights.SemiBold));

        var channels = Services.ChannelsFor(_match.LeagueSlug);
        var hint = Secondary(channels.Count > 0
            ? "Chaînes de ta playlist :"
            : Services.Library.All(MediaKind.Live).Count == 0
                ? "Ajoute une playlist pour voir les chaînes correspondantes."
                : "Aucune chaîne correspondante dans ta playlist. Choisis-la une fois : elle sera retenue pour toute la compétition.", 13);
        hint.TextWrapping = TextWrapping.Wrap;
        hint.Margin = new Thickness(0, 6, 0, 12);
        panel.Children.Add(hint);

        var wrap = new WrapPanel();
        foreach (var channel in channels) wrap.Children.Add(ChannelButton(channel, channels));
        var choose = new Button { Style = S("GhostButton"), Content = "Choisir la chaîne…", Margin = new Thickness(0, 0, 10, 10) };
        choose.Click += (_, _) => new ChannelPickerWindow(_match.LeagueSlug, _match.LeagueName).ShowDialog();
        wrap.Children.Add(choose);
        panel.Children.Add(wrap);
        return Card(panel);
    }

    // ── Événements ────────────────────────────────────────────────────────

    private static FrameworkElement EventsList(IReadOnlyList<MatchEvent> events)
    {
        var panel = new StackPanel();
        foreach (var e in events)
        {
            var row = new Grid { Margin = new Thickness(0, 4, 0, 4) };
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            var clock = Text(e.Clock, 14, FontWeights.Bold);
            clock.HorizontalAlignment = HorizontalAlignment.Center;
            Grid.SetColumn(clock, 1);
            row.Children.Add(clock);
            var text = Text(e.IsHome ? $"{e.Text}   {e.Icon}" : $"{e.Icon}   {e.Text}", 14, e.IsGoal ? FontWeights.SemiBold : FontWeights.Normal);
            text.HorizontalAlignment = e.IsHome ? HorizontalAlignment.Right : HorizontalAlignment.Left;
            Grid.SetColumn(text, e.IsHome ? 0 : 2);
            row.Children.Add(text);
            panel.Children.Add(row);
        }
        return panel;
    }

    // ── Statistiques ──────────────────────────────────────────────────────

    private static FrameworkElement StatsList(IReadOnlyList<StatLine> stats)
    {
        var panel = new StackPanel();
        var accent = B("AccentBrush");
        foreach (var stat in stats)
        {
            var total = stat.HomeValue + stat.AwayValue;
            var homeShare = total > 0 ? stat.HomeValue / total : 0.5;

            var labels = new DockPanel();
            var home = Text(stat.Home, 15, FontWeights.Bold);
            DockPanel.SetDock(home, Dock.Left);
            var away = Text(stat.Away, 15, FontWeights.Bold);
            DockPanel.SetDock(away, Dock.Right);
            labels.Children.Add(home);
            labels.Children.Add(away);
            var label = Secondary(stat.Label, 13);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            labels.Children.Add(label);

            var bars = new Grid { Height = 6, Margin = new Thickness(0, 6, 0, 0) };
            bars.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, homeShare), GridUnitType.Star) });
            bars.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            bars.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.001, 1 - homeShare), GridUnitType.Star) });
            var homeBar = new Border { CornerRadius = new CornerRadius(3), Background = stat.HomeValue >= stat.AwayValue ? accent : B("SurfaceHighBrush") };
            var awayBar = new Border { CornerRadius = new CornerRadius(3), Background = stat.AwayValue > stat.HomeValue ? accent : B("SurfaceHighBrush") };
            Grid.SetColumn(awayBar, 2);
            bars.Children.Add(homeBar);
            bars.Children.Add(awayBar);

            var block = new StackPanel { Margin = new Thickness(0, 8, 0, 10) };
            block.Children.Add(labels);
            block.Children.Add(bars);
            panel.Children.Add(block);
        }
        return panel;
    }

    // ── Compositions ──────────────────────────────────────────────────────

    private static FrameworkElement Lineups(IReadOnlyList<Lineup> lineups)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        for (var i = 0; i < 2; i++)
        {
            var lineup = lineups[i];
            var panel = new StackPanel();
            var title = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
            if (lineup.Formation is { Length: > 0 } formation)
            {
                var f = Badge(formation, B("SurfaceHighBrush"));
                DockPanel.SetDock(f, Dock.Right);
                title.Children.Add(f);
            }
            title.Children.Add(Text(lineup.TeamName, 16, FontWeights.Bold));
            panel.Children.Add(title);
            AddPlayers(panel, lineup.Players.Where(p => p.Starter));
            var subs = lineup.Players.Where(p => !p.Starter).ToList();
            if (subs.Count > 0)
            {
                var label = Secondary("Remplaçants", 12);
                label.Margin = new Thickness(0, 12, 0, 4);
                panel.Children.Add(label);
                AddPlayers(panel, subs);
            }
            var card = Card(panel);
            Grid.SetColumn(card, i * 2);
            grid.Children.Add(card);
        }
        return grid;
    }

    private static void AddPlayers(Panel panel, IEnumerable<LineupPlayer> players)
    {
        foreach (var p in players)
        {
            var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
            var number = Secondary(p.Jersey, 13);
            number.Width = 30;
            DockPanel.SetDock(number, Dock.Left);
            row.Children.Add(number);
            var marks = (p.SubbedIn ? " ↑" : "") + (p.SubbedOut ? " ↓" : "");
            var position = Secondary(p.Position + marks, 12);
            DockPanel.SetDock(position, Dock.Right);
            row.Children.Add(position);
            row.Children.Add(Text(p.Name, 14, opacity: p.Starter ? 1 : 0.8));
            panel.Children.Add(row);
        }
    }
}

/// <summary>Tableau de classement (équipes cliquables, mise en avant de certaines équipes).</summary>
public static class StandingsTable
{
    public static FrameworkElement Build(IReadOnlyList<StandingRow> rows, IReadOnlyCollection<string> highlightIds, IReadOnlyCollection<string> highlightNames, bool compact, string? leagueSlug = null)
    {
        var panel = new StackPanel();
        panel.Children.Add(Row(null, false, compact, leagueSlug));
        var shown = rows;
        if (compact && rows.Count > 12)
        {
            // Autour des équipes du match.
            var indexes = rows.Select((r, i) => (r, i)).Where(x => highlightIds.Contains(x.r.TeamId) || highlightNames.Contains(x.r.TeamName)).Select(x => x.i).ToList();
            if (indexes.Count > 0)
            {
                var from = Math.Max(0, indexes.Min() - 2);
                var to = Math.Min(rows.Count - 1, indexes.Max() + 2);
                shown = rows.Skip(from).Take(to - from + 1).ToList();
            }
        }
        foreach (var row in shown)
        {
            var highlight = highlightIds.Contains(row.TeamId) || highlightNames.Contains(row.TeamName);
            panel.Children.Add(Row(row, highlight, compact, leagueSlug));
        }
        return Card(panel, new Thickness(12, 8, 12, 8));
    }

    private static FrameworkElement Row(StandingRow? row, bool highlight, bool compact, string? leagueSlug)
    {
        var grid = new Grid { Height = row is null ? 30 : 40 };
        var widths = compact
            ? new double[] { 6, 34, 0, 40, 40, 40, 40, 50, 46 }
            : new double[] { 6, 34, 0, 44, 44, 44, 44, 50, 50, 56, 52 };
        foreach (var w in widths)
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = w == 0 ? new GridLength(1, GridUnitType.Star) : new GridLength(w) });

        string[] values = row is null
            ? compact ? ["", "#", "Équipe", "J", "G", "N", "P", "Diff", "Pts"] : ["", "#", "Équipe", "J", "G", "N", "P", "BP", "BC", "Diff", "Pts"]
            : compact
                ? ["", row.Rank.ToString(), row.TeamName, row.Played.ToString(), row.Won.ToString(), row.Drawn.ToString(), row.Lost.ToString(), row.GoalDiff, row.Points.ToString()]
                : ["", row.Rank.ToString(), row.TeamName, row.Played.ToString(), row.Won.ToString(), row.Drawn.ToString(), row.Lost.ToString(), row.GoalsFor.ToString(), row.GoalsAgainst.ToString(), row.GoalDiff, row.Points.ToString()];

        for (var i = 1; i < values.Length; i++)
        {
            FrameworkElement cell;
            if (i == 2 && row != null)
            {
                var team = new StackPanel { Orientation = Orientation.Horizontal };
                team.Children.Add(Crest(row.Logo, 22, row.TeamName));
                var name = Text(row.TeamName, 14, highlight ? FontWeights.Bold : FontWeights.Normal);
                name.Margin = new Thickness(10, 0, 0, 0);
                team.Children.Add(name);
                cell = team;
            }
            else
            {
                var text = row is null ? Secondary(values[i], 12) : Text(values[i], 14, i == values.Length - 1 || highlight ? FontWeights.Bold : FontWeights.Normal);
                if (i != 2) text.HorizontalAlignment = HorizontalAlignment.Center;
                cell = text;
            }
            cell.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(cell, i);
            grid.Children.Add(cell);
        }

        if (row?.NoteColor is { } color && ThemeManager.ParseHex(color) is { } hex)
        {
            var bar = new Border { Width = 4, Margin = new Thickness(0, 8, 0, 8), CornerRadius = new CornerRadius(2), Background = new SolidColorBrush(ThemeManager.ColorOf(hex)), ToolTip = row.NoteText };
            grid.Children.Add(bar);
        }

        var container = new Border
        {
            Child = grid,
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(4, 0, 4, 0),
            Background = highlight ? new SolidColorBrush(Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF)) : Brushes.Transparent,
        };
        if (row is null || row.TeamId.Length == 0) return container;

        var button = new Button { Style = S("PlainButton"), Content = container, Cursor = System.Windows.Input.Cursors.Hand, HorizontalContentAlignment = HorizontalAlignment.Stretch };
        button.Click += (_, _) => MainWindow.Instance.Push(new TeamPage(new TeamRef(row.TeamId, row.TeamName, row.TeamName, "", row.Logo, null), leagueSlug ?? ""));
        return button;
    }
}
