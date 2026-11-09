using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Core.Football;
using static ZappTV.Foot.FootUi;

namespace ZappTV.Foot;

/// <summary>Fenêtre de dialogue construite en code, au style de l'app.</summary>
public abstract class CodeDialog : Window
{
    protected CodeDialog(string title, double width, double height)
    {
        Title = title;
        Width = width;
        Height = height;
        MinWidth = 520;
        MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        Background = B("SurfaceBrush");
        Foreground = Brushes.White;
        FontFamily = (FontFamily)Application.Current.FindResource("UiFont");
        if (MainWindow.Instance is { IsLoaded: true } owner) Owner = owner;
        WindowSizing.FitDialog(this);
        if (Height > MaxHeight) Height = MaxHeight;
        DarkTitleBar.Attach(this);
    }

    protected static TextBox SearchBox(string placeholder) => new()
    {
        Style = S("Field"),
        Tag = placeholder,
        Margin = new Thickness(0, 14, 0, 12),
    };

    protected static CheckBox Check(string text, bool value, Action<bool> onChange, string? logo = null)
    {
        object content = text;
        if (logo != null)
        {
            var stack = new StackPanel { Orientation = Orientation.Horizontal };
            var crest = Crest(logo, 22, text);
            crest.Margin = new Thickness(4, 0, 10, 0);
            stack.Children.Add(crest);
            stack.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center, FontSize = 14 });
            content = stack;
        }
        var box = new CheckBox
        {
            Content = content,
            IsChecked = value,
            Foreground = Brushes.White,
            VerticalContentAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 5, 0, 5),
            Cursor = System.Windows.Input.Cursors.Hand,
        };
        box.Checked += (_, _) => onChange(true);
        box.Unchecked += (_, _) => onChange(false);
        return box;
    }

    protected static string Fold(string text) => ChannelMatcher.Normalize(text);
}

/// <summary>Choisir les compétitions et les équipes suivies (profil actif).</summary>
public sealed class FootFollowWindow : CodeDialog
{
    private readonly StackPanel _body = new();
    private bool _teamsTab;
    private string _teamsLeague;
    private readonly TextBox _search = SearchBox("Rechercher…");
    private List<TeamRef>? _teams;
    private string? _teamsError;

    public FootFollowWindow(bool teamsTab = false) : base("Ligues et équipes suivies", 760, 760)
    {
        _teamsTab = teamsTab;
        _teamsLeague = Services.Profiles.Current.Leagues.FirstOrDefault() ?? "fra.1";

        var root = new DockPanel { Margin = new Thickness(30, 24, 30, 22) };
        var header = new StackPanel();
        DockPanel.SetDock(header, Dock.Top);
        header.Children.Add(Text("Ligues et équipes suivies", 24, FontWeights.Black));
        header.Children.Add(Secondary($"Pour le profil « {Services.Profiles.Active.Name} ». Leurs matchs apparaissent dans l'accueil et l'onglet Foot.", 13));
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 16, 0, 0) };
        header.Children.Add(tabs);
        header.Children.Add(_search);
        root.Children.Add(header);

        var close = new Button { Style = S("AccentButton"), Content = "Terminé", MinWidth = 120, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0), IsDefault = true, IsCancel = true };
        close.Click += (_, _) => Close();
        DockPanel.SetDock(close, Dock.Bottom);
        root.Children.Add(close);

        root.Children.Add(new ScrollViewer { Content = _body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false });
        Content = root;

        void BuildTabs()
        {
            tabs.Children.Clear();
            tabs.Children.Add(FootPage.Pill("Compétitions", !_teamsTab, async () => { _teamsTab = false; BuildTabs(); await RenderAsync(); }));
            tabs.Children.Add(FootPage.Pill("Équipes", _teamsTab, async () => { _teamsTab = true; BuildTabs(); await RenderAsync(); }));
        }
        BuildTabs();
        _search.TextChanged += async (_, _) => await RenderAsync(reload: false);
        Loaded += async (_, _) =>
        {
            _search.Focus();
            await RenderAsync();
        };
    }

    private async Task RenderAsync(bool reload = true)
    {
        _body.Children.Clear();
        if (!_teamsTab)
        {
            RenderLeagues();
            return;
        }
        RenderTeamsHeader();
        if (reload && (_teams is null || _teamsError != null))
        {
            _body.Children.Add(Secondary("Chargement des équipes…", 14));
            try
            {
                _teams = await Services.Foot.TeamsAsync(_teamsLeague);
                _teamsError = null;
            }
            catch (Exception ex)
            {
                _teamsError = Library.FriendlyError(ex);
            }
            _body.Children.Clear();
            RenderTeamsHeader();
        }
        RenderTeams();
    }

    private void RenderLeagues()
    {
        var query = Fold(_search.Text);
        foreach (var area in LeagueCatalog.All.GroupBy(l => l.Area))
        {
            var leagues = area.Where(l => query.Length == 0 || Fold(l.Name + " " + l.Area).Contains(query)).ToList();
            if (leagues.Count == 0) continue;
            var title = Text(area.Key, 15, FontWeights.Bold);
            title.Margin = new Thickness(0, 14, 0, 4);
            _body.Children.Add(title);
            foreach (var league in leagues)
            {
                var label = league.Broadcaster.Length > 0 ? $"{league.Name}   ·   {league.Broadcaster}" : league.Name;
                _body.Children.Add(Check(label, Services.Profiles.FollowsLeague(league.Slug),
                    on => Services.Profiles.SetLeagueFollowed(league.Slug, on), league.Logo));
            }
        }
    }

    private void RenderTeamsHeader()
    {
        var chips = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        var leagues = LeagueCatalog.All.Where(l => Services.Profiles.FollowsLeague(l.Slug)).Concat(LeagueCatalog.All.Where(l => l.Slug.EndsWith(".1"))).DistinctBy(l => l.Slug);
        foreach (var league in leagues)
        {
            chips.Children.Add(FootPage.Pill(league.Name, league.Slug == _teamsLeague, async () =>
            {
                _teamsLeague = league.Slug;
                _teams = null;
                await RenderAsync();
            }, league.Logo));
        }
        _body.Children.Add(chips);
    }

    private void RenderTeams()
    {
        if (_teamsError != null)
        {
            _body.Children.Add(Secondary($"Impossible de charger les équipes : {_teamsError}", 14));
            return;
        }
        if (_teams is null) return;

        var followed = Services.Profiles.Current.Teams;
        if (followed.Count > 0)
        {
            var title = Text("Tes équipes", 15, FontWeights.Bold);
            title.Margin = new Thickness(0, 6, 0, 4);
            _body.Children.Add(title);
            foreach (var team in followed.ToList())
                _body.Children.Add(Check($"{team.Name}   ·   {LeagueCatalog.NameOf(team.League)}", true, on => Services.Profiles.SetTeamFollowed(team, on), team.Logo));
        }

        var query = Fold(_search.Text);
        var header = Text(LeagueCatalog.NameOf(_teamsLeague), 15, FontWeights.Bold);
        header.Margin = new Thickness(0, 14, 0, 4);
        _body.Children.Add(header);
        foreach (var team in _teams.Where(t => query.Length == 0 || Fold(t.Name).Contains(query)).OrderBy(t => t.Name))
        {
            var model = new FollowedTeam { Id = team.Id, Name = team.Name, Logo = team.Logo ?? TeamRef.LogoFor(team.Id), League = _teamsLeague };
            _body.Children.Add(Check(team.Name, Services.Profiles.FollowsTeam(team.Id), on => Services.Profiles.SetTeamFollowed(model, on), model.Logo));
        }
    }
}

/// <summary>Associer des chaînes de la playlist à une compétition et modifier ses mots-clés de diffuseur.</summary>
public sealed class ChannelPickerWindow : CodeDialog
{
    private readonly string _slug;
    private readonly StackPanel _list = new();
    private readonly TextBox _search = SearchBox("Rechercher une chaîne…");

    public ChannelPickerWindow(string slug, string leagueName) : base($"Chaînes · {leagueName}", 720, 760)
    {
        _slug = slug;
        var root = new DockPanel { Margin = new Thickness(30, 24, 30, 22) };

        var header = new StackPanel();
        DockPanel.SetDock(header, Dock.Top);
        header.Children.Add(Text($"Où regarder · {leagueName}", 24, FontWeights.Black));
        header.Children.Add(Secondary("Épingle les chaînes de ta playlist qui diffusent cette compétition : elles seront proposées en premier sur chaque match.", 13));
        ((TextBlock)header.Children[1]).TextWrapping = TextWrapping.Wrap;

        var keywordsLabel = Secondary("Diffuseurs / mots-clés de chaînes (séparés par des virgules)", 13);
        keywordsLabel.Margin = new Thickness(0, 18, 0, 6);
        header.Children.Add(keywordsLabel);
        var keywords = new TextBox { Style = S("Field"), Text = Services.Settings.Data.BroadcasterKeywords(slug), Tag = "Ex. : Canal+ Foot, beIN Sports 1" };
        keywords.LostFocus += (_, _) => SaveKeywords(keywords.Text);
        header.Children.Add(keywords);
        var reset = new Button { Style = S("GhostButton"), Content = "Rétablir les diffuseurs par défaut", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 8, 0, 0), Padding = new Thickness(12, 6, 12, 6) };
        reset.Click += (_, _) =>
        {
            Services.Settings.Update(s => s.FootBroadcasters.Remove(slug));
            keywords.Text = Services.Settings.Data.BroadcasterKeywords(slug);
            Render();
        };
        header.Children.Add(reset);
        header.Children.Add(_search);
        root.Children.Add(header);

        var close = new Button { Style = S("AccentButton"), Content = "Terminé", MinWidth = 120, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0), IsCancel = true };
        close.Click += (_, _) =>
        {
            SaveKeywords(keywords.Text);
            Close();
        };
        DockPanel.SetDock(close, Dock.Bottom);
        root.Children.Add(close);

        root.Children.Add(new ScrollViewer { Content = _list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false });
        Content = root;

        _search.TextChanged += (_, _) => Render();
        Loaded += (_, _) =>
        {
            Render();
            _search.Focus();
        };
    }

    private void SaveKeywords(string text)
    {
        var value = text.Trim();
        var defaults = LeagueCatalog.Find(_slug)?.ChannelKeywords ?? "";
        if (value == Services.Settings.Data.BroadcasterKeywords(_slug)) return;
        Services.Settings.Update(s =>
        {
            if (value.Length == 0 || value == defaults) s.FootBroadcasters.Remove(_slug);
            else s.FootBroadcasters[_slug] = value;
        });
        Render();
    }

    private void Render()
    {
        _list.Children.Clear();
        var channels = Services.Library.All(MediaKind.Live);
        if (channels.Count == 0)
        {
            _list.Children.Add(Secondary("Aucune chaîne en direct : ajoute d'abord une playlist ou des liens.", 14));
            return;
        }
        var pinned = Services.Profiles.PinnedChannels(_slug).ToHashSet();
        var query = Fold(_search.Text);
        IEnumerable<MediaItem> shown;
        if (query.Length > 0)
        {
            shown = channels.Where(c => Fold(c.Name + " " + c.Group).Contains(query)).Take(150);
        }
        else
        {
            // Sans recherche : épinglées puis suggestions selon les diffuseurs.
            var suggested = ChannelMatcher.Find(channels, Services.Settings.Data.BroadcasterKeywords(_slug), 30);
            shown = channels.Where(c => pinned.Contains(c.Id)).Concat(suggested).DistinctBy(c => c.Id);
            var hint = Secondary("Suggestions d'après les diffuseurs. Tape le nom d'une chaîne pour en chercher une autre.", 12);
            hint.Margin = new Thickness(0, 0, 0, 8);
            _list.Children.Add(hint);
        }
        var any = false;
        foreach (var channel in shown)
        {
            any = true;
            var isPinned = pinned.Contains(channel.Id);
            var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
            var pin = new Button
            {
                Style = S(isPinned ? "AccentButton" : "GhostButton"),
                Content = isPinned ? "📌 Épinglée" : "Épingler",
                Padding = new Thickness(12, 6, 12, 6),
                MinWidth = 110,
            };
            pin.Click += (_, _) =>
            {
                Services.Profiles.TogglePin(_slug, channel.Id);
                Render();
            };
            DockPanel.SetDock(pin, Dock.Right);
            row.Children.Add(pin);
            var play = new Button { Style = S("IconButton"), Content = new TextBlock { Text = "", Style = (Style)Application.Current.FindResource("Icon"), FontSize = 14 }, ToolTip = "Regarder", Margin = new Thickness(0, 0, 8, 0) };
            play.Click += (_, _) => Actions.PlayItem(channel, [channel]);
            DockPanel.SetDock(play, Dock.Right);
            row.Children.Add(play);

            var logo = new Border { Width = 56, Height = 32, CornerRadius = new CornerRadius(6), Background = B("SurfaceHighBrush"), Margin = new Thickness(0, 0, 12, 0) };
            if (ImageUrlConverter.Load(channel.LogoUrl, 112) is { } image) logo.Child = new Image { Source = image, Margin = new Thickness(4, 3, 4, 3) };
            DockPanel.SetDock(logo, Dock.Left);
            row.Children.Add(logo);
            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(Text(channel.Name, 14, FontWeights.SemiBold));
            texts.Children.Add(Secondary(channel.Group, 12));
            row.Children.Add(texts);
            _list.Children.Add(row);
        }
        if (!any) _list.Children.Add(Secondary(query.Length > 0 ? "Aucune chaîne ne correspond." : "Aucune chaîne ne correspond aux diffuseurs. Cherche-la par son nom.", 14));
    }
}
