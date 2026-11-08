using System.Windows;
using Microsoft.Win32;
using ZappTV.Core;

namespace ZappTV.Dialogs;

public partial class AddPlaylistWindow : Window
{
    private PlaylistSourceType _mode = PlaylistSourceType.M3uUrl;
    private string? _filePath;

    public AddPlaylistWindow(string? prefillUrl = null, string? prefillFile = null, string? prefillName = null)
    {
        InitializeComponent();
        Owner = MainWindow.Instance;
        DarkTitleBar.Attach(this);

        NameBox.Text = prefillName ?? "";
        if (prefillFile != null)
        {
            _mode = PlaylistSourceType.M3uFile;
            SetFile(prefillFile);
        }
        else if (prefillUrl != null)
        {
            // Lien « get.php?username=…&password=… » : on propose directement le mode Xtream, plus complet.
            if (TryParseXtream(prefillUrl, out var server, out var user, out var password))
            {
                _mode = PlaylistSourceType.Xtream;
                ServerBox.Text = server;
                UserBox.Text = user;
                PasswordInput.Password = password;
            }
            UrlBox.Text = prefillUrl;
        }
        UpdateMode();
    }

    private void Mode_Click(object sender, RoutedEventArgs e)
    {
        _mode = sender == FileMode ? PlaylistSourceType.M3uFile
            : sender == XtreamMode ? PlaylistSourceType.Xtream
            : PlaylistSourceType.M3uUrl;
        UpdateMode();
    }

    private void UpdateMode()
    {
        UrlMode.IsChecked = _mode == PlaylistSourceType.M3uUrl;
        FileMode.IsChecked = _mode == PlaylistSourceType.M3uFile;
        XtreamMode.IsChecked = _mode == PlaylistSourceType.Xtream;
        UrlPanel.Visibility = _mode == PlaylistSourceType.M3uUrl ? Visibility.Visible : Visibility.Collapsed;
        FilePanel.Visibility = _mode == PlaylistSourceType.M3uFile ? Visibility.Visible : Visibility.Collapsed;
        XtreamPanel.Visibility = _mode == PlaylistSourceType.Xtream ? Visibility.Visible : Visibility.Collapsed;
        ErrorText.Visibility = Visibility.Collapsed;
    }

    private void ChooseFile_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Title = "Choisir une playlist", Filter = "Playlists|*.m3u;*.m3u8;*.txt|Tous les fichiers|*.*" };
        if (dialog.ShowDialog(this) == true) SetFile(dialog.FileName);
    }

    private void SetFile(string path)
    {
        _filePath = path;
        FileText.Text = System.IO.Path.GetFileName(path);
        if (NameBox.Text.Length == 0) NameBox.Text = System.IO.Path.GetFileNameWithoutExtension(path);
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        var name = NameBox.Text.Trim();
        try
        {
            Playlist playlist;
            switch (_mode)
            {
                case PlaylistSourceType.M3uUrl:
                {
                    var url = UrlBox.Text.Trim();
                    if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || (uri.Scheme != "http" && uri.Scheme != "https"))
                    {
                        ShowError("Adresse invalide : elle doit commencer par http:// ou https://.");
                        return;
                    }
                    playlist = new Playlist { Name = name.Length > 0 ? name : uri.Host, Type = PlaylistSourceType.M3uUrl, Url = url };
                    break;
                }
                case PlaylistSourceType.M3uFile:
                {
                    if (_filePath is null || !System.IO.File.Exists(_filePath))
                    {
                        ShowError("Choisis un fichier .m3u.");
                        return;
                    }
                    AppPaths.Folder("Playlists");
                    var fileName = Guid.NewGuid().ToString("N") + ".m3u";
                    System.IO.File.Copy(_filePath, AppPaths.PlaylistFile(fileName));
                    playlist = new Playlist { Name = name.Length > 0 ? name : "Playlist importée", Type = PlaylistSourceType.M3uFile, FileName = fileName };
                    break;
                }
                default:
                {
                    var server = XtreamCredentials.NormalizeServer(ServerBox.Text);
                    var user = UserBox.Text.Trim();
                    var password = PasswordInput.Password;
                    if (server is null || user.Length == 0 || password.Length == 0)
                    {
                        ShowError("Renseigne le serveur, l'identifiant et le mot de passe.");
                        return;
                    }
                    SaveButton.IsEnabled = false;
                    SaveButton.Content = "Vérification…";
                    await new XtreamClient(new XtreamCredentials(server, user, password)).AuthenticateAsync();
                    playlist = new Playlist
                    {
                        Name = name.Length > 0 ? name : new Uri(server).Host,
                        Type = PlaylistSourceType.Xtream,
                        Server = server,
                        Username = user,
                        ProtectedPassword = Passwords.Protect(password),
                    };
                    break;
                }
            }

            Services.Playlists.Add(playlist);
            MainWindow.Instance.ShowToast($"Playlist « {playlist.Name} » ajoutée. Chargement…");
            DialogResult = true;
        }
        catch (Exception ex)
        {
            ShowError(Library.FriendlyError(ex));
        }
        finally
        {
            SaveButton.IsEnabled = true;
            SaveButton.Content = "Ajouter";
        }
    }

    private void ShowError(string message)
    {
        ErrorText.Text = message;
        ErrorText.Visibility = Visibility.Visible;
    }

    private static bool TryParseXtream(string url, out string server, out string user, out string password)
    {
        server = user = password = "";
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || !uri.AbsolutePath.EndsWith("get.php", StringComparison.OrdinalIgnoreCase))
            return false;
        var query = uri.Query.TrimStart('?').Split('&')
            .Select(part => part.Split('=', 2))
            .Where(kv => kv.Length == 2)
            .ToDictionary(kv => kv[0].ToLowerInvariant(), kv => Uri.UnescapeDataString(kv[1]));
        if (!query.TryGetValue("username", out var u) || !query.TryGetValue("password", out var p)) return false;
        server = uri.GetLeftPart(UriPartial.Authority);
        user = u;
        password = p;
        return true;
    }
}
