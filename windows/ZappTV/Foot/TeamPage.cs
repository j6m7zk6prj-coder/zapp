using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Core.Football;
using static ZappTV.Foot.FootUi;

namespace ZappTV.Foot;

/// <summary>Fiche d'une équipe : suivre, prochains matchs, résultats, classement.</summary>
public sealed class TeamPage : UserControl
{
    private readonly TeamRef _team;
    private string _league;
    private readonly StackPanel _root = new() { Margin = new Thickness(0, 0, 0, 48) };
    private List<Match>? _upcoming;
    private List<Match>? _results;
    private LeagueTable? _table;
    private string? _error;

    public TeamPage(TeamRef team, string leagueSlug)
    {
        _team = team;
        _league = leagueSlug;
        Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _root, Focusable = false };
        Loaded += async (_, _) =>
        {
            Services.Profiles.FootChanged += Render;
            Services.Settings.Changed += Render;
            Render();
            await LoadAsync();
        };
        Unloaded += (_, _) =>
        {
            Services.Profiles.FootChanged -= Render;
            Services.Settings.Changed -= Render;
        };
    }

    private async Task LoadAsync()
    {
        try
        {
            var upcoming = Services.Foot.TeamScheduleAsync(_team.Id, true);
            var results = Services.Foot.TeamScheduleAsync(_team.Id, false);
            _upcoming = (await upcoming).Where(m => m.State != MatchState.Finished).OrderBy(m => m.Date).Take(12).ToList();
            _results = (await results).Where(m => m.State == MatchState.Finished).OrderByDescending(m => m.Date).Take(12).ToList();
            if (_league.Length == 0)
            {
                // Championnat national : la compétition la plus fréquente dans le calendrier.
                _league = _results.Concat(_upcoming).GroupBy(m => m.LeagueSlug)
                    .Where(g => System.Text.RegularExpressions.Regex.IsMatch(g.Key, @"^[a-z]+\.\d$"))
                    .OrderByDescending(g => g.Count()).Select(g => g.Key).FirstOrDefault() ?? "";
            }
        }
        catch (Exception ex)
        {
            _error = Library.FriendlyError(ex);
        }
        if (_league.Length > 0)
        {
            try { _table = await Services.Foot.StandingsAsync(_league); }
            catch { /* classement facultatif */ }
        }
        Render();
    }

    private void Render()
    {
        if (!IsLoaded) return;
        _root.Children.Clear();
        _root.Children.Add(Hero());

        var body = new StackPanel { Margin = new Thickness(56, 0, 56, 0) };
        _root.Children.Add(body);

        if (_error != null)
        {
            body.Children.Add(SectionHeader("Calendrier"));
            body.Children.Add(Secondary($"Impossible de charger le calendrier : {_error}", 14));
            return;
        }
        if (_upcoming is null)
        {
            var loading = Secondary("Chargement du calendrier…", 14);
            loading.Margin = new Thickness(0, 30, 0, 0);
            body.Children.Add(loading);
            return;
        }

        var live = _upcoming.FirstOrDefault(m => m.State == MatchState.Live);
        if (live != null)
        {
            body.Children.Add(SectionHeader("En ce moment"));
            body.Children.Add(Shelf([MatchCard(live, 340)]));
        }

        body.Children.Add(SectionHeader("Prochains matchs"));
        var next = _upcoming.Where(m => m.State != MatchState.Live).ToList();
        if (next.Count == 0) body.Children.Add(Secondary("Aucun match programmé pour l'instant.", 14));
        else body.Children.Add(Card(Rows(next), new Thickness(12, 8, 12, 8)));

        if (_results!.Count > 0)
        {
            body.Children.Add(SectionHeader("Derniers résultats"));
            body.Children.Add(Form(_results));
            body.Children.Add(Card(Rows(_results), new Thickness(12, 8, 12, 8)));
        }

        if (_table is { Groups.Count: > 0 })
        {
            var group = _table.Groups.FirstOrDefault(g => g.Rows.Any(r => r.TeamId == _team.Id || r.TeamName == _team.Name));
            if (group.Rows is null) group = _table.Groups[0];
            body.Children.Add(SectionHeader(group.Group is { Length: > 0 } title ? $"Classement · {title}" : $"Classement · {LeagueCatalog.NameOf(_league)}", null, null, LeagueCatalog.LogoFor(_league)));
            body.Children.Add(StandingsTable.Build(group.Rows, [_team.Id], [_team.Name], compact: false, _league));
        }
    }

    private static StackPanel Rows(IEnumerable<Match> matches)
    {
        var panel = new StackPanel();
        foreach (var m in matches)
        {
            var day = Secondary($"{FootFormat.DayTitle(m.Date.ToLocalTime().Date)} · {m.LeagueName}", 12);
            day.Margin = new Thickness(12, 8, 0, 0);
            panel.Children.Add(day);
            panel.Children.Add(MatchRow(m));
        }
        return panel;
    }

    /// <summary>Forme récente : V / N / D (masquée en mode anti-spoiler).</summary>
    private FrameworkElement Form(List<Match> results)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 14) };
        row.Children.Add(Secondary("Forme  ", 13));
        if (ScoresHidden)
        {
            row.Children.Add(Secondary("masquée (anti-spoiler)", 13));
            return row;
        }
        foreach (var m in results.Take(5).Reverse())
        {
            var home = m.Home.Id == _team.Id;
            var won = home ? m.HomeWinner : m.AwayWinner;
            var lost = home ? m.AwayWinner : m.HomeWinner;
            var (label, brush) = won ? ("V", WinBrush) : lost ? ("D", LiveBrush) : ("N", B("SurfaceHighBrush"));
            var badge = Badge(label, brush, won ? Brushes.Black : Brushes.White);
            badge.Margin = new Thickness(0, 0, 6, 0);
            badge.MinWidth = 26;
            badge.ToolTip = $"{m.Home.Name} {m.HomeScore} - {m.AwayScore} {m.Away.Name}";
            row.Children.Add(badge);
        }
        return row;
    }

    private FrameworkElement Hero()
    {
        var color = ((SolidColorBrush)TeamBrush(_team.Color, Color.FromRgb(0x2A, 0x44, 0xD8))).Color;
        var background = new LinearGradientBrush(color, ThemeManager.Background, new Point(0, 0), new Point(0.9, 1));

        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(56, 76, 56, 34) };
        panel.Children.Add(Crest(_team.Logo ?? TeamRef.LogoFor(_team.Id), 120, _team.Name));
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(28, 0, 0, 0) };
        texts.Children.Add(Text(_team.Name, 34, FontWeights.Black));
        if (_league.Length > 0) texts.Children.Add(Text(LeagueCatalog.NameOf(_league), 15, opacity: 0.8));

        var follows = Services.Profiles.FollowsTeam(_team.Id);
        var follow = new Button
        {
            Style = S(follows ? "GhostButton" : "AccentButton"),
            Content = follows ? "★  Équipe suivie" : "☆  Suivre cette équipe",
            Margin = new Thickness(0, 16, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        follow.Click += (_, _) =>
        {
            Services.Profiles.SetTeamFollowed(new FollowedTeam { Id = _team.Id, Name = _team.Name, Logo = _team.Logo ?? TeamRef.LogoFor(_team.Id), League = _league }, !follows);
            MainWindow.Instance.ShowToast(follows ? $"Tu ne suis plus {_team.Name}." : $"{_team.Name} ajoutée à tes équipes.");
        };
        texts.Children.Add(follow);
        panel.Children.Add(texts);
        return new Border { Background = background, Child = panel };
    }
}
