using System.Windows;
using System.Windows.Controls;
using ZappTV.Core;
using ZappTV.Dialogs;

namespace ZappTV.Pages;

public sealed class LinkRow
{
    public required CustomLink Link { get; init; }
    public string Name => Link.Name;
    public string Initials => TextUtil.Initials(Link.Name);
    public string Detail => $"{LinkInspector.Format(Link.Url).Label()}  ·  {(Link.Kind == MediaKind.Live ? "Chaîne en direct" : "Film / vidéo")}  ·  {Link.Group}";
    public string Url => Link.Url;
    public string? LogoUrl => Link.ResolvedLogoUrl;
    public bool HasLogo => !string.IsNullOrEmpty(LogoUrl);
}

public partial class LinksPage : UserControl
{
    public LinksPage()
    {
        InitializeComponent();
        UiFactory.SetAccentTitle(LinksTitle, "Mes liens, ", "à portée de main.");
        Loaded += (_, _) =>
        {
            Services.Customization.Changed += Refresh;
            Refresh();
        };
        Unloaded += (_, _) => Services.Customization.Changed -= Refresh;
    }

    private void Refresh()
    {
        var rows = Services.Customization.Links.Select(l => new LinkRow { Link = l }).ToList();
        LinksList.ItemsSource = rows;
        EmptyState.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private static CustomLink? LinkOf(object sender) => (sender as FrameworkElement)?.Tag is LinkRow row ? row.Link : null;

    private void Add_Click(object sender, RoutedEventArgs e) => new LinkEditorWindow(null).ShowDialog();

    private void Paste_Click(object sender, RoutedEventArgs e)
    {
        var text = Clipboard.ContainsText() ? Clipboard.GetText() : null;
        if (!Actions.AddFromText(text)) MainWindow.Instance.ShowToast("Le presse-papiers ne contient pas de lien de flux.");
    }

    private void Play_Click(object sender, RoutedEventArgs e)
    {
        if (LinkOf(sender) is not { } link) return;
        var items = Services.Library.CustomLinkItems;
        var item = items.FirstOrDefault(i => i.Id == link.ItemId) ?? link.ToMediaItem();
        Actions.PlayItem(item, items);
    }

    private void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (LinkOf(sender) is { } link) new LinkEditorWindow(link).ShowDialog();
    }

    private void Up_Click(object sender, RoutedEventArgs e)
    {
        if (LinkOf(sender) is { } link) Services.Customization.MoveLink(link, -1);
    }

    private void Down_Click(object sender, RoutedEventArgs e)
    {
        if (LinkOf(sender) is { } link) Services.Customization.MoveLink(link, 1);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (LinkOf(sender) is not { } link) return;
        var answer = MessageBox.Show(Window.GetWindow(this)!, $"Supprimer « {link.Name} » ?", "iTv",
            MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (answer == MessageBoxResult.Yes) Services.Customization.DeleteLink(link);
    }
}
