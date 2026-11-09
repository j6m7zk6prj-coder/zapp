using System.Windows;
using System.Windows.Media;
using ZappTV.Controls;
using ZappTV.Core;
using ZappTV.Player;

namespace ZappTV.Dialogs;

/// <summary>Ajout / modification d'un lien de flux, un par un.</summary>
public partial class LinkEditorWindow : Window
{
    private readonly CustomLink? _existing;
    private MediaKind _kind = MediaKind.Live;
    private bool _kindChosen;
    private bool _saved;

    public LinkEditorWindow(CustomLink? link, string? prefillUrl = null)
    {
        InitializeComponent();
        Owner = MainWindow.Instance;
        WindowSizing.FitDialog(this);
        DarkTitleBar.Attach(this);
        _existing = link;

        if (link != null)
        {
            Title = Heading.Text = "Modifier le lien";
            SaveButton.Content = "Enregistrer";
            DeleteButton.Visibility = Visibility.Visible;
            UrlBox.Text = link.Url;
            NameBox.Text = link.Name;
            CategoryInput.Text = link.Group;
            _kind = link.Kind;
            _kindChosen = true;
            Logo.Load(new LogoDraft { UrlText = link.LogoUrl ?? "", File = link.LogoFile });
        }
        else
        {
            UrlBox.Text = prefillUrl ?? "";
            Logo.Load(new LogoDraft());
        }

        CategoryInput.Placeholder = CustomLink.DefaultGroup;
        UpdateKind();
        UpdateUrlState();
        Logo.PreviewName = NameBox.Text;
        Loaded += (_, _) => (string.IsNullOrEmpty(UrlBox.Text) ? UrlBox : NameBox).Focus();
        Closed += (_, _) =>
        {
            if (!_saved) Logo.Draft.DiscardUnused(null);
        };
    }

    private string? ParsedUrl => LinkInspector.Normalize(UrlBox.Text);

    private void Url_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) => UpdateUrlState();

    private void Name_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        Logo.PreviewName = NameBox.Text;

    private void UpdateUrlState()
    {
        if (FormatText is null) return;
        var url = ParsedUrl;
        if (url != null)
        {
            FormatText.Text = $"✓  {LinkInspector.Format(url).Label()} détecté — lu par VLC";
            FormatText.Foreground = new SolidColorBrush(Color.FromRgb(0x4A, 0xDE, 0x80));
            if (!_kindChosen)
            {
                _kind = LinkInspector.GuessKind(url);
                UpdateKind();
            }
        }
        else
        {
            FormatText.Text = string.IsNullOrWhiteSpace(UrlBox.Text) ? "" : "✗  Lien non reconnu";
            FormatText.Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0xB3, 0x47));
        }
        PlaylistBanner.Visibility = url != null && LinkInspector.LooksLikePlaylist(url) ? Visibility.Visible : Visibility.Collapsed;
        SaveButton.IsEnabled = TestButton.IsEnabled = url != null;
    }

    private void UpdateKind()
    {
        KindLive.IsChecked = _kind == MediaKind.Live;
        KindMovie.IsChecked = _kind != MediaKind.Live;
        CategoryInput.SetSuggestions(new[] { CustomLink.DefaultGroup }.Concat(Services.Library.Groups(_kind)));
    }

    private void Kind_Click(object sender, RoutedEventArgs e)
    {
        _kind = sender == KindMovie ? MediaKind.Movie : MediaKind.Live;
        _kindChosen = true;
        UpdateKind();
    }

    private void Test_Click(object sender, RoutedEventArgs e)
    {
        if (ParsedUrl is not { } url) return;
        var name = NameBox.Text.Trim();
        PlayerWindow.Open([new Playable($"test-{TextUtil.StableHash(url):x}", name.Length > 0 ? name : "Test du lien", url, url, Logo.Draft.PreviewUrl, _kind == MediaKind.Live)], 0);
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (ParsedUrl is not { } url)
        {
            ErrorText.Text = "Lien invalide.";
            ErrorText.Visibility = Visibility.Visible;
            return;
        }
        var name = NameBox.Text.Trim();
        if (name.Length == 0) name = Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Host.Length > 0 ? uri.Host : "Mon lien";

        var draft = Logo.Draft;
        // Nouvel objet : le store compare l'ancien et le nouveau logo pour faire le ménage.
        var link = new CustomLink
        {
            Id = _existing?.Id ?? Guid.NewGuid(),
            CreatedAt = _existing?.CreatedAt ?? DateTimeOffset.Now,
            Name = name,
            Url = url,
            Kind = _kind,
            Group = CategoryInput.Text.Length > 0 ? CategoryInput.Text : CustomLink.DefaultGroup,
            LogoFile = draft.Removed ? null : draft.File,
            LogoUrl = draft.Removed ? null : draft.CustomUrl,
        };
        Services.Customization.SaveLink(link);
        draft.DiscardUnused(link.LogoFile);
        _saved = true;
        MainWindow.Instance.ShowToast(_existing is null ? $"« {name} » ajouté à Mes liens." : "Lien enregistré.");
        DialogResult = true;
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_existing is null) return;
        if (MessageBox.Show(this, $"Supprimer « {_existing.Name} » ?", "iTv", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        Services.Customization.DeleteLink(_existing);
        _saved = true;
        DialogResult = true;
    }

    private void AddAsPlaylist_Click(object sender, RoutedEventArgs e)
    {
        if (ParsedUrl is not { } url) return;
        _saved = true;
        Close();
        new AddPlaylistWindow(prefillUrl: url, prefillName: NameBox.Text.Trim()).ShowDialog();
    }
}
