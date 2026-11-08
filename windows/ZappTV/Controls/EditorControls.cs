using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Microsoft.Win32;
using ZappTV.Core;

namespace ZappTV.Controls;

/// <summary>Logo en cours d'édition : image importée, URL, ou retiré.</summary>
public sealed class LogoDraft
{
    public string UrlText { get; set; } = "";
    public string? File { get; set; }
    public bool Removed { get; set; }
    /// <summary>Logo d'origine (playlist), affiché si rien d'autre n'est choisi.</summary>
    public string? Original { get; init; }
    /// <summary>Images importées pendant cette édition (pour faire le ménage).</summary>
    public List<string> CreatedFiles { get; } = [];

    public string? CustomUrl => string.IsNullOrWhiteSpace(UrlText) ? null : UrlText.Trim();

    public string? PreviewUrl => Removed ? null : File != null ? AppPaths.LogoFile(File) : CustomUrl ?? Original;

    public void DiscardUnused(string? kept)
    {
        foreach (var name in CreatedFiles.Where(n => n != kept)) LogoStorage.Delete(name);
    }
}

/// <summary>Aperçu + « Choisir une image… » + « Retirer » + champ URL.</summary>
public sealed class LogoPicker : StackPanel
{
    private readonly Border _fallback;
    private readonly TextBlock _initials;
    private readonly Border _logoBox;
    private readonly Image _logo;
    private readonly TextBox _url;
    private readonly Button _remove;
    private string _name = "";
    private bool _settingText;

    public LogoDraft Draft { get; private set; } = new();

    public string PreviewName
    {
        get => _name;
        set
        {
            _name = value;
            UpdatePreview();
        }
    }

    public LogoPicker()
    {
        _initials = new TextBlock { FontSize = 20, FontWeight = FontWeights.Black, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        _fallback = new Border { CornerRadius = new CornerRadius(10), Child = _initials };
        _logo = new Image { Stretch = Stretch.Uniform, Margin = new Thickness(10, 8, 10, 8) };
        _logoBox = new Border { CornerRadius = new CornerRadius(10), Background = (Brush)Application.Current.FindResource("SurfaceHighBrush"), Child = _logo, Visibility = Visibility.Collapsed };
        var preview = new Grid { Width = 128, Height = 72 };
        preview.Children.Add(_fallback);
        preview.Children.Add(_logoBox);

        var choose = new Button { Style = (Style)Application.Current.FindResource("GhostButton"), Content = "Choisir une image…" };
        choose.Click += (_, _) => ChooseFile();
        _remove = new Button { Style = (Style)Application.Current.FindResource("GhostButton"), Content = "Retirer le logo", Margin = new Thickness(0, 8, 0, 0) };
        _remove.Click += (_, _) =>
        {
            Draft.File = null;
            Draft.UrlText = "";
            Draft.Removed = true;
            SetUrlText("");
            UpdatePreview();
        };
        var buttons = new StackPanel { Margin = new Thickness(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        buttons.Children.Add(choose);
        buttons.Children.Add(_remove);

        var top = new StackPanel { Orientation = Orientation.Horizontal };
        top.Children.Add(preview);
        top.Children.Add(buttons);

        _url = new TextBox { Style = (Style)Application.Current.FindResource("Field"), Tag = "…ou adresse d'une image (https://…/logo.png)", Margin = new Thickness(0, 12, 0, 0) };
        _url.TextChanged += (_, _) =>
        {
            if (_settingText) return;
            Draft.UrlText = _url.Text;
            if (!string.IsNullOrWhiteSpace(_url.Text))
            {
                Draft.File = null;
                Draft.Removed = false;
            }
            UpdatePreview();
        };

        Children.Add(top);
        Children.Add(_url);
    }

    public void Load(LogoDraft draft)
    {
        Draft = draft;
        SetUrlText(draft.UrlText);
        UpdatePreview();
    }

    private void SetUrlText(string text)
    {
        _settingText = true;
        _url.Text = text;
        _settingText = false;
    }

    private void ChooseFile()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Choisir un logo",
            Filter = "Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp;*.ico|Tous les fichiers|*.*",
        };
        if (dialog.ShowDialog(Window.GetWindow(this)) != true) return;
        if (LogoStorage.Import(dialog.FileName) is not { } name) return;
        Draft.File = name;
        Draft.CreatedFiles.Add(name);
        Draft.UrlText = "";
        Draft.Removed = false;
        SetUrlText("");
        UpdatePreview();
    }

    private void UpdatePreview()
    {
        var url = Draft.PreviewUrl;
        var image = ImageUrlConverter.Load(url, 220);
        _logo.Source = image;
        _logoBox.Visibility = image != null ? Visibility.Visible : Visibility.Collapsed;
        _fallback.Background = ThemeManager.GradientFor(string.IsNullOrWhiteSpace(_name) ? "?" : _name);
        _initials.Text = TextUtil.Initials(_name);
        _remove.Visibility = url != null ? Visibility.Visible : Visibility.Collapsed;
    }
}

/// <summary>Champ catégorie avec liste des catégories existantes.</summary>
public sealed class CategoryBox : Grid
{
    private readonly TextBox _box;
    private readonly Button _pick;
    private readonly ContextMenu _menu = new();

    public CategoryBox()
    {
        ColumnDefinitions.Add(new ColumnDefinition());
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _box = new TextBox { Style = (Style)Application.Current.FindResource("Field") };
        _pick = new Button
        {
            Style = (Style)Application.Current.FindResource("GhostButton"),
            Margin = new Thickness(8, 0, 0, 0),
            Padding = new Thickness(14, 9, 14, 9),
            ToolTip = "Choisir une catégorie existante",
            Content = new TextBlock { Text = "", Style = (Style)Application.Current.FindResource("Icon"), FontSize = 12 },
        };
        _pick.Click += (_, _) =>
        {
            if (_menu.Items.Count == 0) return;
            _menu.PlacementTarget = _pick;
            _menu.Placement = PlacementMode.Bottom;
            _menu.IsOpen = true;
        };
        SetColumn(_pick, 1);
        Children.Add(_box);
        Children.Add(_pick);
    }

    public string Text
    {
        get => _box.Text.Trim();
        set => _box.Text = value;
    }

    public string Placeholder
    {
        set => _box.Tag = value;
    }

    public void SetSuggestions(IEnumerable<string> suggestions)
    {
        _menu.Items.Clear();
        foreach (var suggestion in suggestions.Distinct().Take(40))
        {
            var item = new MenuItem { Header = suggestion };
            var value = suggestion;
            item.Click += (_, _) => _box.Text = value;
            _menu.Items.Add(item);
        }
        _pick.IsEnabled = _menu.Items.Count > 0;
    }
}
