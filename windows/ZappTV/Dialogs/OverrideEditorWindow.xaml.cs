using System.Windows;
using ZappTV.Controls;
using ZappTV.Core;

namespace ZappTV.Dialogs;

/// <summary>Renommer, changer le logo ou la catégorie, masquer une chaîne / un film de playlist.</summary>
public partial class OverrideEditorWindow : Window
{
    private readonly MediaItem _original;
    private bool _saved;

    public OverrideEditorWindow(MediaItem original, ItemOverride current)
    {
        InitializeComponent();
        Owner = MainWindow.Instance;
        WindowSizing.FitDialog(this);
        DarkTitleBar.Attach(this);
        _original = original;

        Title = $"Modifier « {original.Name} »";
        OriginalText.Text = $"Original : {original.Name} · {original.Group}";
        NameBox.Tag = original.Name;
        NameBox.Text = current.Name ?? "";
        CategoryInput.Placeholder = original.Group;
        CategoryInput.Text = current.Group ?? "";
        CategoryInput.SetSuggestions(Services.Library.Groups(original.Kind));
        HiddenBox.IsChecked = current.Hidden == true;
        Logo.Load(new LogoDraft
        {
            UrlText = current.LogoUrl ?? "",
            File = current.LogoFile,
            Removed = current.RemoveLogo == true,
            Original = original.LogoUrl,
        });
        Logo.PreviewName = original.Name;

        Loaded += (_, _) => NameBox.Focus();
        Closed += (_, _) =>
        {
            if (!_saved) Logo.Draft.DiscardUnused(null);
        };
    }

    private void Name_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (Logo is null) return;
        Logo.PreviewName = NameBox.Text.Trim().Length > 0 ? NameBox.Text : _original.Name;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var draft = Logo.Draft;
        var value = new ItemOverride
        {
            Name = NameBox.Text.Trim() is { Length: > 0 } name ? name : null,
            Group = CategoryInput.Text is { Length: > 0 } group ? group : null,
            RemoveLogo = draft.Removed ? true : null,
            LogoFile = draft.Removed ? null : draft.File,
            LogoUrl = draft.Removed ? null : draft.CustomUrl,
            Hidden = HiddenBox.IsChecked == true ? true : null,
        };
        Services.Customization.SetOverride(_original.Id, value);
        draft.DiscardUnused(value.LogoFile);
        _saved = true;
        MainWindow.Instance.ShowToast("Modifications enregistrées.");
        DialogResult = true;
    }

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        Services.Customization.ResetOverride(_original.Id);
        Logo.Draft.DiscardUnused(null);
        _saved = true;
        MainWindow.Instance.ShowToast("Élément rétabli tel qu'à l'origine.");
        DialogResult = true;
    }
}
