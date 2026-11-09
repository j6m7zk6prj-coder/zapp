using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using ZappTV.Core;
using ZappTV.Core.Football;
using static ZappTV.Foot.FootUi;

namespace ZappTV.Foot;

/// <summary>Centre Foot : calendrier par jour, classements, équipes suivies.</summary>
public sealed class FootPage : UserControl
{
    public enum Tab { Matches, Standings, Teams }

    private enum Filter { All, MyTeams, Live, League }

    private readonly StackPanel _root = new() { Margin = new Thickness(56, 76, 56, 48) };
    private readonly DispatcherTimer _timer = new();
    private Tab _tab;
    private DateTime _day = DateTime.Today;
    private Filter _filter = Filter.All;
    private string? _filterLeague;
    private string? _standingsLeague;

    private List<Match>? _matches;
    private DateTime _matchesDay;
    private string? _matchesError;
    private int _loadVersion;

    private LeagueTable? _table;
    private string? _tableLeague;
    private string? _tableError;

    private readonly Dictionary<string, Match?> _nextByTeam = new();

    public FootPage(Tab tab = Tab.Matches, string? league = null)
    {
        _tab = tab;
        _standingsLeague = league;
        Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _root, Focusable = false };
        _timer.Tick += async (_, _) => await LoadMatchesAsync(silent: true);
        Loaded += async (_, _) =>
        {
            Services.Profiles.FootChanged += OnFootChanged;
            Services.Profiles.Switched += OnFootChanged;
            Services.Settings.Changed += Render;
            _timer.Interval = TimeSpan.FromSeconds(Math.Max(20, Services.Settings.Data.FootRefreshSeconds));
            _timer.Start();
            Render();
            await LoadCurrentTabAsync();
        };
        Unloaded += (_, _) =>
        {
            _timer.Stop();
            Services.Profiles.FootChanged -= OnFootChanged;
            Services.Profiles.Switched -= OnFootChanged;
            Services.Settings.Changed -= Render;
        };
    }

    private async void OnFootChanged()
    {
        _matches = null;
        _nextByTeam.Clear();
        Render();
        await LoadCurrentTabAsync();
    }

    private Task LoadCurrentTabAsync() => _tab switch
    {
        Tab.Matches => LoadMatchesAsync(),
        Tab.Standings => LoadTableAsync(),
        _ => LoadTeamsAsync(),
    };

    private IReadOnlyList<string> FollowedLeagues => Services.Profiles.Current.Leagues;

    // ── Chargements ───────────────────────────────────────────────────────

    private async Task LoadMatchesAsync(bool silent = false)
    {
        if (_tab != Tab.Matches) return;
        // Le rafraîchissement automatique n'a d'intérêt que pour aujourd'hui.
        if (silent && _day != DateTime.Today) return;
        var version = ++_loadVersion;
        var day = _day;
        var slugs = FollowedLeagues.Union(Services.Profiles.Current.Teams.Select(t => t.League)).Where(s => s.Length > 0).Distinct().ToList();
        if (silent) Services.Foot.Invalidate();
        try
        {
            var matches = await Services.Foot.DayAsync(slugs, day);
            if (version != _loadVersion) return;
            _matches = matches;
            _matchesDay = day;
            _matchesError = null;
        }
        catch (Exception ex)
        {
            if (version != _loadVersion) return;
            _matchesError = Library.FriendlyError(ex);
        }
        Render();
    }

    private async Task LoadTableAsync()
    {
        var league = _standingsLeague ??= FollowedLeagues.FirstOrDefault() ?? "fra.1";
        if (_tableLeague == league && _table != null) return;
        _table = null;
        _tableError = null;
        Render();
        try
        {
            var table = await Services.Foot.StandingsAsync(league);
            if (league != _standingsLeague) return;
            _table = table;
            _tableLeague = league;
        }
        catch (Exception ex)
        {
            _tableError = Library.FriendlyError(ex);
        }
        Render();
    }

    private async Task LoadTeamsAsync()
    {
        var teams = Services.Profiles.Current.Teams.Where(t => !_nextByTeam.ContainsKey(t.Id)).ToList();
        if (teams.Count == 0) return;
        var tasks = teams.Select(async t =>
        {
            try
            {
                var schedule = await Services.Foot.TeamScheduleAsync(t.Id, true);
                return (t.Id, Match: schedule.Where(m => m.State != MatchState.Finished).OrderBy(m => m.Date).FirstOrDefault());
            }
            catch
            {
                return (t.Id, Match: (Match?)null);
            }
        });
        foreach (var (id, match) in await Task.WhenAll(tasks)) _nextByTeam[id] = match;
        Render();
    }

    // ── Rendu ─────────────────────────────────────────────────────────────

    private void Render()
    {
        if (!IsLoaded) return;
        _root.Children.Clear();
        _root.Children.Add(Header());
        switch (_tab)
        {
            case Tab.Matches: RenderMatches(); break;
            case Tab.Standings: RenderStandings(); break;
            default: RenderTeams(); break;
        }
    }

    private FrameworkElement Header()
    {
        var panel = new StackPanel();
        var top = new DockPanel();
        var manage = new Button { Style = S("GhostButton"), Content = "⚙  Ligues et équipes suivies" };
        manage.Click += (_, _) => new FootFollowWindow().ShowDialog();
        DockPanel.SetDock(manage, Dock.Right);
        top.Children.Add(manage);
        top.Children.Add(ZappTV.Pages.UiFactory.AccentTitle("Le foot, ", "en direct."));
        panel.Children.Add(top);

        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 16, 0, 4) };
        foreach (var (tab, title) in new[] { (Tab.Matches, "Matchs"), (Tab.Standings, "Classements"), (Tab.Teams, "Mes équipes") })
        {
            tabs.Children.Add(Pill(title, _tab == tab, async () =>
            {
                _tab = tab;
                Render();
                await LoadCurrentTabAsync();
            }));
        }
        panel.Children.Add(tabs);
        return panel;
    }

    public static Button Pill(string title, bool selected, Action onClick, string? logo = null)
    {
        object content = title;
        if (logo != null)
        {
            var stack = new StackPanel { Orientation = Orientation.Horizontal };
            var crest = Crest(logo, 18, title);
            crest.Margin = new Thickness(0, 0, 8, 0);
            stack.Children.Add(crest);
            stack.Children.Add(new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center });
            content = stack;
        }
        var button = new Button
        {
            Style = S(selected ? "PillSelectedButton" : "PillButton"),
            Content = content,
            Margin = new Thickness(0, 0, 8, 8),
        };
        button.Click += (_, _) => onClick();
        return button;
    }

    // Matchs

    private void RenderMatches()
    {
        // Bandeau de jours
        var days = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 14, 0, 6) };
        for (var offset = -3; offset <= 7; offset++)
        {
            var day = DateTime.Today.AddDays(offset);
            var label = offset switch
            {
                -1 => "Hier",
                0 => "Aujourd'hui",
                1 => "Demain",
                _ => day.ToString("ddd d MMM", FootFormat.French),
            };
            days.Children.Add(Pill(label, day == _day, async () =>
            {
                _day = day;
                _matches = null;
                Render();
                await LoadMatchesAsync();
            }));
        }
        var picker = new DatePicker { SelectedDate = _day, Width = 130, Margin = new Thickness(6, 0, 0, 8), VerticalAlignment = VerticalAlignment.Center, ToolTip = "Choisir une date" };
        picker.SelectedDateChanged += async (_, _) =>
        {
            if (picker.SelectedDate is not { } date || date.Date == _day) return;
            _day = date.Date;
            _matches = null;
            Render();
            await LoadMatchesAsync();
        };
        days.Children.Add(picker);
        _root.Children.Add(Shelf([days]));

        // Filtres
        var filters = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        filters.Children.Add(Pill("Tous", _filter == Filter.All, () => SetFilter(Filter.All)));
        if (Services.Profiles.Current.Teams.Count > 0) filters.Children.Add(Pill("★ Mes équipes", _filter == Filter.MyTeams, () => SetFilter(Filter.MyTeams)));
        filters.Children.Add(Pill("● En direct", _filter == Filter.Live, () => SetFilter(Filter.Live)));
        foreach (var slug in FollowedLeagues)
            filters.Children.Add(Pill(LeagueCatalog.NameOf(slug), _filter == Filter.League && _filterLeague == slug, () => SetFilter(Filter.League, slug), LeagueCatalog.LogoFor(slug)));
        _root.Children.Add(filters);

        if (FollowedLeagues.Count == 0 && Services.Profiles.Current.Teams.Count == 0)
        {
            _root.Children.Add(Empty("Tu ne suis aucune compétition.", "Choisis tes ligues et tes équipes pour voir leurs matchs ici.", "Choisir mes ligues", () => new FootFollowWindow().ShowDialog()));
            return;
        }
        if (_matchesError != null && _matches is null)
        {
            _root.Children.Add(Empty("Impossible de charger les matchs.", _matchesError, "Réessayer", async () => await LoadMatchesAsync()));
            return;
        }
        if (_matches is null || _matchesDay != _day)
        {
            _root.Children.Add(Secondary("Chargement des matchs…", 14));
            return;
        }

        var teamIds = Services.Profiles.Current.Teams.Select(t => t.Id).ToHashSet();
        IEnumerable<Match> list = _matches;
        list = _filter switch
        {
            Filter.MyTeams => list.Where(m => teamIds.Contains(m.Home.Id) || teamIds.Contains(m.Away.Id)),
            Filter.Live => list.Where(m => m.State == MatchState.Live),
            Filter.League => list.Where(m => m.LeagueSlug == _filterLeague),
            _ => list,
        };
        var shown = list.ToList();
        if (shown.Count == 0)
        {
            var message = _filter == Filter.Live ? "Aucun match en direct pour le moment." : $"Aucun match {FootFormat.DayTitle(_day).ToLowerInvariant()} dans tes compétitions.";
            _root.Children.Add(Empty(message, "Essaie un autre jour ou ajoute des compétitions.", null, null));
            return;
        }

        // Mes équipes en premier, puis par compétition dans l'ordre suivi.
        var mine = shown.Where(m => teamIds.Contains(m.Home.Id) || teamIds.Contains(m.Away.Id)).ToList();
        if (mine.Count > 0 && _filter != Filter.MyTeams)
        {
            _root.Children.Add(SectionHeader("★ Mes équipes"));
            _root.Children.Add(Card(RowsOf(mine), new Thickness(12, 8, 12, 8)));
        }
        var order = FollowedLeagues.ToList();
        foreach (var group in shown.GroupBy(m => m.LeagueSlug).OrderBy(g => order.Contains(g.Key) ? order.IndexOf(g.Key) : 999))
        {
            var slug = group.Key;
            _root.Children.Add(SectionHeader(group.First().LeagueName, "Classement", () => ShowStandings(slug), LeagueCatalog.LogoFor(slug)));
            _root.Children.Add(Card(RowsOf(group.OrderBy(m => m.Date)), new Thickness(12, 8, 12, 8)));
        }
    }

    private static StackPanel RowsOf(IEnumerable<Match> matches)
    {
        var panel = new StackPanel();
        foreach (var m in matches) panel.Children.Add(MatchRow(m));
        return panel;
    }

    private void SetFilter(Filter filter, string? league = null)
    {
        _filter = filter;
        _filterLeague = league;
        Render();
    }

    private async void ShowStandings(string slug)
    {
        _tab = Tab.Standings;
        _standingsLeague = slug;
        Render();
        await LoadTableAsync();
    }

    // Classements

    private void RenderStandings()
    {
        var leagues = FollowedLeagues.ToList();
        if (_standingsLeague != null && !leagues.Contains(_standingsLeague)) leagues.Insert(0, _standingsLeague);
        var chips = new WrapPanel { Margin = new Thickness(0, 14, 0, 4) };
        foreach (var slug in leagues)
        {
            chips.Children.Add(Pill(LeagueCatalog.NameOf(slug), slug == _standingsLeague, async () =>
            {
                _standingsLeague = slug;
                await LoadTableAsync();
            }, LeagueCatalog.LogoFor(slug)));
        }
        _root.Children.Add(chips);

        if (_tableError != null)
        {
            _root.Children.Add(Empty("Classement indisponible.", _tableError, null, null));
            return;
        }
        if (_table is null)
        {
            _root.Children.Add(Secondary("Chargement du classement…", 14));
            return;
        }
        if (_table.Groups.Count == 0)
        {
            _root.Children.Add(Empty("Pas de classement pour cette compétition.", "Les coupes à élimination directe n'en ont pas.", null, null));
            return;
        }
        var teamIds = Services.Profiles.Current.Teams.Select(t => t.Id).ToList();
        foreach (var (group, rows) in _table.Groups)
        {
            _root.Children.Add(SectionHeader(group.Length > 0 ? group : _table.Title, null, null, _table.Groups.Count == 1 ? LeagueCatalog.LogoFor(_standingsLeague!) : null));
            _root.Children.Add(StandingsTable.Build(rows, teamIds, [], compact: false, _standingsLeague));
        }
        var legend = rows0Notes();
        if (legend.Length > 0)
        {
            var text = Secondary(legend, 12);
            text.Margin = new Thickness(4, 14, 0, 0);
            text.TextWrapping = TextWrapping.Wrap;
            _root.Children.Add(text);
        }

        string rows0Notes() => string.Join("   ·   ", _table.Groups.SelectMany(g => g.Rows).Select(r => r.NoteText).Where(n => !string.IsNullOrWhiteSpace(n)).Distinct());
    }

    // Équipes

    private void RenderTeams()
    {
        var teams = Services.Profiles.Current.Teams;
        if (teams.Count == 0)
        {
            _root.Children.Add(Empty("Tu ne suis aucune équipe.", "Suis tes équipes pour retrouver leurs matchs en premier, partout dans l'app.", "Choisir mes équipes", () => new FootFollowWindow(teamsTab: true).ShowDialog()));
            return;
        }
        var wrap = new WrapPanel { Margin = new Thickness(0, 18, 0, 0) };
        foreach (var team in teams)
        {
            var panel = new StackPanel { Width = 230 };
            var head = new StackPanel { Orientation = Orientation.Horizontal };
            head.Children.Add(Crest(team.Logo, 48, team.Name));
            var names = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            names.Children.Add(Text(team.Name, 16, FontWeights.Bold));
            names.Children.Add(Secondary(LeagueCatalog.NameOf(team.League), 12));
            head.Children.Add(names);
            panel.Children.Add(head);

            string next;
            if (!_nextByTeam.TryGetValue(team.Id, out var match)) next = "Chargement…";
            else if (match is null) next = "Pas de match programmé";
            else
            {
                var opponent = match.Home.Id == team.Id ? match.Away.Name : match.Home.Name;
                var where = match.Home.Id == team.Id ? "vs" : "à";
                next = match.State == MatchState.Live
                    ? $"● En direct {where} {opponent}  {match.HomeScore}-{match.AwayScore}"
                    : $"{FootFormat.Kickoff(match.Date)} · {where} {opponent}";
            }
            var nextText = Secondary(next, 12);
            nextText.Margin = new Thickness(0, 12, 0, 0);
            if (match?.State == MatchState.Live) nextText.Foreground = LiveBrush;
            panel.Children.Add(nextText);

            var card = Card(panel);
            card.Margin = new Thickness(0, 0, 14, 14);
            var button = new Button { Style = S("TileButton"), Content = card };
            var teamRef = new TeamRef(team.Id, team.Name, team.Name, "", team.Logo, null);
            button.Click += (_, _) => MainWindow.Instance.Push(new TeamPage(teamRef, team.League));
            wrap.Children.Add(button);
        }
        _root.Children.Add(wrap);
    }

    public static FrameworkElement Empty(string title, string detail, string? action, Action? onAction)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 40, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, MaxWidth = 560 };
        panel.Children.Add(Text(title, 20, FontWeights.Bold));
        var text = Secondary(detail, 14);
        text.TextWrapping = TextWrapping.Wrap;
        text.Margin = new Thickness(0, 6, 0, 16);
        panel.Children.Add(text);
        if (action != null && onAction != null)
        {
            var button = new Button { Style = S("AccentButton"), Content = action, HorizontalAlignment = HorizontalAlignment.Left };
            button.Click += (_, _) => onAction();
            panel.Children.Add(button);
        }
        return panel;
    }
}
