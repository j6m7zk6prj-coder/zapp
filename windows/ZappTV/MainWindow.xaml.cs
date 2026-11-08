using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using ZappTV.Core;
using ZappTV.Dialogs;
using ZappTV.Pages;

namespace ZappTV;

public partial class MainWindow : Window
{
    public static MainWindow Instance { get; private set; } = null!;

    private readonly Stack<FrameworkElement> _history = new();
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private string _section = "home";
    private bool _syncingNav;

    public MainWindow()
    {
        Instance = this;
        InitializeComponent();
        DarkTitleBar.Attach(this);

        _toastTimer.Tick += (_, _) =>
        {
            _toastTimer.Stop();
            Toast.Visibility = Visibility.Collapsed;
        };

        Services.Library.Changed += UpdateStatus;
        Services.Playlists.Changed += OnContentSourcesChanged;
        Services.Customization.Changed += OnContentSourcesChanged;

        Loaded += (_, _) =>
        {
            ShowSection("home");
            UpdateStatus();
        };
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
        foreach (var radio in new[] { NavHome, NavLive, NavMovies, NavSeries, NavSearch, NavLinks, NavSettings })
            radio.IsChecked = (string)radio.Tag == _section;
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
        var library = Services.Library;
        LoadingBar.Visibility = library.IsLoading ? Visibility.Visible : Visibility.Collapsed;
        var active = Services.Playlists.Active;
        StatusText.Text = library.IsLoading
            ? "Chargement de la playlist…"
            : active != null
                ? $"{active.Name} · {library.Items.Count:N0} éléments"
                : $"{Services.Customization.Links.Count} lien(s)";
        StatusText.ToolTip = library.ErrorMessage;
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
