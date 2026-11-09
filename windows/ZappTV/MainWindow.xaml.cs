using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using ZappTV.Core;
using ZappTV.Core.Football;
using ZappTV.Dialogs;
using ZappTV.Foot;
using ZappTV.Pages;

namespace ZappTV;

public partial class MainWindow : Window
{
    public static MainWindow Instance { get; private set; } = null!;

    private readonly Stack<FrameworkElement> _history = new();
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly DispatcherTimer _clockTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _liveTimer = new() { Interval = TimeSpan.FromMinutes(2) };
    private string _section = "home";
    private bool _syncingNav;

    public MainWindow()
    {
        Instance = this;
        InitializeComponent();
        WindowSizing.Fit(this, 1400, 860);
        DarkTitleBar.Attach(this);

        _toastTimer.Tick += (_, _) =>
        {
            _toastTimer.Stop();
            Toast.Visibility = Visibility.Collapsed;
        };

        Services.Library.Changed += UpdateStatus;
        Services.Playlists.Changed += OnContentSourcesChanged;
        Services.Customization.Changed += OnContentSourcesChanged;
        Services.Profiles.Switched += OnProfileSwitched;
        Services.Profiles.ProfilesChanged += UpdateAvatar;
        Services.Profiles.FootChanged += CheckLiveAsync;
        Services.Settings.Changed += OnSettingsChanged;

        _clockTimer.Tick += (_, _) => UpdateClock();
        _liveTimer.Tick += (_, _) => CheckLiveAsync();

        Loaded += (_, _) =>
        {
            ShowSection(StartSection());
            UpdateStatus();
            UpdateAvatar();
            OnSettingsChanged();
            _liveTimer.Start();
            CheckLiveAsync();
        };
    }

    private static string StartSection()
    {
        var start = Services.Settings.Data.StartPage;
        return start is "live" or "movies" or "series" or "foot" or "links" ? start : "home";
    }

    // ── Barre du haut ─────────────────────────────────────────────────────

    private void OnSettingsChanged()
    {
        var show = Services.Settings.Data.ShowClock;
        ClockText.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        if (show) _clockTimer.Start(); else _clockTimer.Stop();
        UpdateClock();
        if (!Services.Settings.Data.ShowLiveBadge) LiveDot.Visibility = Visibility.Collapsed;
    }

    private void UpdateClock() => ClockText.Text = DateTime.Now.ToString("HH:mm");

    private void UpdateAvatar()
    {
        var profile = Services.Profiles.Active;
        AvatarText.Text = profile.Initial;
        var color = ThemeManager.ColorOf(profile.Color);
        AvatarCircle.Background = new System.Windows.Media.SolidColorBrush(color);
        AvatarText.Foreground = ThemeManager.IsLight(profile.Color) ? System.Windows.Media.Brushes.Black : System.Windows.Media.Brushes.White;
        AvatarButton.ToolTip = $"Profil : {profile.Name}";
    }

    private void OnProfileSwitched()
    {
        UpdateAvatar();
        ShowSection(_section is "settings" or "search" ? "home" : _section);
        ShowToast($"Profil « {Services.Profiles.Active.Name} »");
        CheckLiveAsync();
    }

    /// <summary>Point rouge sur l'onglet Foot quand une compétition suivie a un match en cours.</summary>
    private async void CheckLiveAsync()
    {
        if (!Services.Settings.Data.ShowLiveBadge)
        {
            LiveDot.Visibility = Visibility.Collapsed;
            return;
        }
        try
        {
            var data = Services.Profiles.Current;
            var slugs = data.Leagues.Union(data.Teams.Select(t => t.League)).Where(s => s.Length > 0).ToList();
            var matches = await Services.Foot.DayAsync(slugs, DateTime.Today);
            var live = matches.Count(m => m.State == MatchState.Live);
            LiveDot.Visibility = live > 0 ? Visibility.Visible : Visibility.Collapsed;
            LiveDot.ToolTip = live == 1 ? "1 match en direct" : $"{live} matchs en direct";
        }
        catch
        {
            // Pas de réseau : on ne montre rien.
        }
    }

    private void Logo_Click(object sender, RoutedEventArgs e) => ShowSection("home");
    private void Search_Click(object sender, RoutedEventArgs e) => ShowSection("search");
    private void Settings_Click(object sender, RoutedEventArgs e) => ShowSection("settings");

    private void Avatar_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = AvatarButton, Placement = PlacementMode.Bottom };
        var header = new MenuItem { Header = $"{Services.Profiles.Active.Name}  ·  {StatusLine()}", IsEnabled = false };
        menu.Items.Add(header);
        menu.Items.Add(new Separator());
        foreach (var profile in Services.Profiles.Profiles)
        {
            var item = new MenuItem { Header = profile.Name, IsCheckable = true, IsChecked = profile.Id == Services.Profiles.Active.Id };
            item.Click += (_, _) => Services.Profiles.Switch(profile.Id);
            menu.Items.Add(item);
        }
        menu.Items.Add(Item("Gérer les profils…", () => new ProfilesWindow().ShowDialog()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Ligues et équipes suivies…", () => new FootFollowWindow().ShowDialog()));
        menu.Items.Add(Item("Ajouter une playlist…", () => new AddPlaylistWindow().ShowDialog()));
        var refresh = Item("Actualiser la playlist (F5)", () => Services.LoadActivePlaylist(force: true));
        refresh.IsEnabled = Services.Playlists.Active != null && !Services.Library.IsLoading;
        menu.Items.Add(refresh);
        menu.Items.Add(Item("Mes liens", () => ShowSection("links")));
        menu.Items.Add(Item("Réglages", () => ShowSection("settings")));
        menu.IsOpen = true;

        static MenuItem Item(string text, Action action)
        {
            var item = new MenuItem { Header = text };
            item.Click += (_, _) => action();
            return item;
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────

    public void ShowSection(string section)
    {
        _section = section;
        _history.Clear();
        Host.Content = CreatePage(section);
        SyncNav();
        UpdateBack();
    }

    public void Push(FrameworkElement page)
    {
        if (Host.Content is FrameworkElement current) _history.Push(current);
        Host.Content = page;
        UpdateBack();
    }

    public void GoBack()
    {
        if (_history.Count == 0) return;
        Host.Content = _history.Pop();
        UpdateBack();
    }

    private FrameworkElement CreatePage(string section) => section switch
    {
        "live" => new CatalogPage(MediaKind.Live),
        "foot" => new FootPage(),
        "movies" => new CatalogPage(MediaKind.Movie),
        "series" => new CatalogPage(MediaKind.Series),
        "search" => new SearchPage(),
        "links" => new LinksPage(),
        "settings" => new SettingsPage(),
        _ => Services.HasContent ? new HomePage() : new OnboardingPage(),
    };

    private void SyncNav()
    {
        _syncingNav = true;
        foreach (var radio in new[] { NavHome, NavLive, NavMovies, NavSeries, NavFoot, NavLinks })
            radio.IsChecked = (string)radio.Tag == _section;
        SearchButton.Opacity = _section == "search" ? 1 : 0.85;
        SettingsButton.Opacity = _section == "settings" ? 1 : 0.85;
        _syncingNav = false;
    }

    private void UpdateBack() =>
        BackButton.Visibility = _history.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

    private void Nav_Checked(object sender, RoutedEventArgs e)
    {
        if (_syncingNav || !IsLoaded) return;
        if (sender is RadioButton { Tag: string section }) ShowSection(section);
    }

    private void Back_Click(object sender, RoutedEventArgs e) => GoBack();

    /// <summary>Premier lien ou première playlist ajouté : on quitte l'écran d'accueil vide.</summary>
    private void OnContentSourcesChanged()
    {
        var onboarding = Host.Content is OnboardingPage;
        if (_section == "home" && _history.Count == 0 && onboarding == Services.HasContent) ShowSection("home");
        UpdateStatus();
    }

    // ── Statut et notifications ───────────────────────────────────────────

    private void UpdateStatus()
    {
        LoadingBar.Visibility = Services.Library.IsLoading ? Visibility.Visible : Visibility.Collapsed;
        LoadingBar.ToolTip = StatusLine();
    }

    private static string StatusLine()
    {
        var library = Services.Library;
        var active = Services.Playlists.Active;
        if (library.IsLoading) return "Chargement de la playlist…";
        if (library.ErrorMessage is { } error) return $"Erreur : {error}";
        return active != null
            ? $"{active.Name} · {library.Items.Count:N0} éléments"
            : $"{Services.Customization.Links.Count} lien(s)";
    }

    public void ShowToast(string message)
    {
        ToastText.Text = message;
        Toast.Visibility = Visibility.Visible;
        _toastTimer.Stop();
        _toastTimer.Start();
    }

    // ── Ajout ─────────────────────────────────────────────────────────────

    private void Add_Click(object sender, RoutedEventArgs e)
    {
        if (AddButton.ContextMenu is { } menu)
        {
            menu.PlacementTarget = AddButton;
            menu.Placement = PlacementMode.Top;
            menu.IsOpen = true;
        }
    }

    private void AddLink_Click(object sender, RoutedEventArgs e) => new LinkEditorWindow(null).ShowDialog();
    private void AddPlaylist_Click(object sender, RoutedEventArgs e) => new AddPlaylistWindow().ShowDialog();
    private void PasteLink_Click(object sender, RoutedEventArgs e) => PasteLink();

    private void PasteLink()
    {
        var text = Clipboard.ContainsText() ? Clipboard.GetText() : null;
        if (!Actions.AddFromText(text)) ShowToast("Le presse-papiers ne contient pas de lien de flux.");
    }

    // ── Clavier, souris, glisser-déposer ──────────────────────────────────

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        var typing = Keyboard.FocusedElement is TextBox;
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);

        if (ctrl && e.Key == Key.V && !typing)
        {
            PasteLink();
            e.Handled = true;
        }
        else if (ctrl && !typing && e.Key is >= Key.D1 and <= Key.D6)
        {
            ShowSection(new[] { "home", "live", "movies", "series", "foot", "links" }[e.Key - Key.D1]);
            e.Handled = true;
        }
        else if (ctrl && e.Key == Key.F)
        {
            ShowSection("search");
            e.Handled = true;
        }
        else if (ctrl && e.Key == Key.N)
        {
            new LinkEditorWindow(null).ShowDialog();
            e.Handled = true;
        }
        else if ((e.Key == Key.System && e.SystemKey == Key.Left) || e.Key == Key.BrowserBack || (e.Key == Key.Back && !typing))
        {
            GoBack();
            e.Handled = true;
        }
        else if (e.Key == Key.F5)
        {
            Services.LoadActivePlaylist(force: true);
            e.Handled = true;
        }
    }

    private void Window_PreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.XButton1)
        {
            GoBack();
            e.Handled = true;
        }
    }

    private void Window_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
        {
            var file = files[0];
            var extension = System.IO.Path.GetExtension(file).ToLowerInvariant();
            if (extension is ".m3u" or ".m3u8" or ".txt") Actions.AddPlaylistFile(file);
            else ShowToast("Glisse un fichier .m3u ou un lien de flux.");
        }
        else if (e.Data.GetData(DataFormats.UnicodeText) is string text && !Actions.AddFromText(text))
        {
            ShowToast("Ce texte n'est pas un lien de flux.");
        }
    }
}
