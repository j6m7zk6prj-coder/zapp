using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ZappTV.Core;
using ZappTV.Foot;
using static ZappTV.Foot.FootUi;

namespace ZappTV.Dialogs;

/// <summary>Créer, renommer, colorer, supprimer et choisir les profils.</summary>
public sealed class ProfilesWindow : CodeDialog
{
    private readonly WrapPanel _grid = new() { HorizontalAlignment = HorizontalAlignment.Center };

    public ProfilesWindow() : base("Profils", 820, 640)
    {
        var root = new DockPanel { Margin = new Thickness(30, 26, 30, 22) };
        var header = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        DockPanel.SetDock(header, Dock.Top);
        var title = Text("Qui regarde ?", 30, FontWeights.Black);
        title.HorizontalAlignment = HorizontalAlignment.Center;
        header.Children.Add(title);
        var caption = Secondary("Chaque profil a ses favoris, son historique, ses ligues, ses équipes et ses chaînes épinglées.", 13);
        caption.HorizontalAlignment = HorizontalAlignment.Center;
        caption.Margin = new Thickness(0, 6, 0, 26);
        header.Children.Add(caption);
        root.Children.Add(header);

        var close = new Button { Style = S("AccentButton"), Content = "Terminé", MinWidth = 120, HorizontalAlignment = HorizontalAlignment.Right, IsCancel = true, Margin = new Thickness(0, 14, 0, 0) };
        close.Click += (_, _) => Close();
        DockPanel.SetDock(close, Dock.Bottom);
        root.Children.Add(close);

        root.Children.Add(new ScrollViewer { Content = _grid, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false });
        Content = root;

        Services.Profiles.ProfilesChanged += Render;
        Services.Profiles.Switched += Render;
        Closed += (_, _) =>
        {
            Services.Profiles.ProfilesChanged -= Render;
            Services.Profiles.Switched -= Render;
        };
        Loaded += (_, _) => Render();
    }

    private void Render()
    {
        _grid.Children.Clear();
        foreach (var profile in Services.Profiles.Profiles) _grid.Children.Add(ProfileTile(profile));
        if (Services.Profiles.Profiles.Count < 8)
        {
            var add = Avatar("+", Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF), false);
            var panel = Tile(add, "Ajouter", null);
            var button = new Button { Style = S("TileButton"), Content = panel, Margin = new Thickness(14) };
            button.Click += (_, _) =>
            {
                var profile = Services.Profiles.Add("");
                new ProfileEditWindow(profile).ShowDialog();
            };
            _grid.Children.Add(button);
        }
    }

    private FrameworkElement ProfileTile(Profile profile)
    {
        var active = profile.Id == Services.Profiles.Active.Id;
        var avatar = Avatar(profile.Initial, ThemeManager.ColorOf(profile.Color), active);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        var edit = new Button { Style = S("GhostButton"), Content = "Modifier", Padding = new Thickness(10, 5, 10, 5), FontSize = 12 };
        edit.Click += (_, _) => new ProfileEditWindow(profile).ShowDialog();
        actions.Children.Add(edit);
        var panel = Tile(avatar, profile.Name, active ? "Profil actif" : null);
        panel.Children.Add(actions);

        var choose = new Button { Style = S("TileButton"), Content = panel, Margin = new Thickness(14), ToolTip = active ? "Profil actif" : $"Passer sur « {profile.Name} »" };
        choose.Click += (_, e) =>
        {
            if (e.OriginalSource is DependencyObject source && IsInside(source, edit)) return;
            if (!active) Services.Profiles.Switch(profile.Id);
            Close();
        };
        return choose;
    }

    private static bool IsInside(DependencyObject source, DependencyObject target)
    {
        for (var node = source; node != null; node = VisualTreeHelper.GetParent(node))
            if (node == target) return true;
        return false;
    }

    private static StackPanel Tile(FrameworkElement avatar, string name, string? caption)
    {
        var panel = new StackPanel { Width = 140 };
        panel.Children.Add(avatar);
        var text = Text(name, 15, FontWeights.SemiBold);
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.Margin = new Thickness(0, 10, 0, 0);
        panel.Children.Add(text);
        if (caption != null)
        {
            var c = Secondary(caption, 12);
            c.HorizontalAlignment = HorizontalAlignment.Center;
            panel.Children.Add(c);
        }
        return panel;
    }

    public static Border Avatar(string initial, Color color, bool ring, double size = 110) => new()
    {
        Width = size,
        Height = size,
        CornerRadius = new CornerRadius(size * 0.22),
        Background = new SolidColorBrush(color),
        BorderBrush = ring ? Brushes.White : Brushes.Transparent,
        BorderThickness = new Thickness(3),
        HorizontalAlignment = HorizontalAlignment.Center,
        Child = new TextBlock
        {
            Text = initial,
            FontSize = size * 0.42,
            FontWeight = FontWeights.Black,
            Foreground = (color.R * 0.299 + color.G * 0.587 + color.B * 0.114) > 170 ? Brushes.Black : Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        },
    };
}

/// <summary>Nom et couleur d'un profil.</summary>
public sealed class ProfileEditWindow : CodeDialog
{
    public ProfileEditWindow(Profile profile) : base("Modifier le profil", 560, 470)
    {
        var color = profile.Color;
        var root = new StackPanel { Margin = new Thickness(30, 24, 30, 24) };
        var preview = new ContentControl();
        void UpdatePreview(string name) => preview.Content = ProfilesWindow.Avatar(string.IsNullOrWhiteSpace(name) ? "?" : name.Trim()[..1].ToUpperInvariant(), ThemeManager.ColorOf(color), false, 84);

        root.Children.Add(preview);
        root.Children.Add(new TextBlock { Text = "Nom", Style = (Style)Application.Current.FindResource("FieldLabel") });
        var name = new TextBox { Style = S("Field"), Text = profile.Name, Tag = "Nom du profil" };
        name.TextChanged += (_, _) => UpdatePreview(name.Text);
        root.Children.Add(name);

        root.Children.Add(new TextBlock { Text = "Couleur", Style = (Style)Application.Current.FindResource("FieldLabel") });
        var swatches = new WrapPanel();
        foreach (var hex in ProfileStore.Colors)
        {
            var swatch = new Button
            {
                Style = S("PlainButton"),
                Margin = new Thickness(0, 0, 10, 0),
                Content = new Border { Width = 34, Height = 34, CornerRadius = new CornerRadius(17), Background = new SolidColorBrush(ThemeManager.ColorOf(hex)) },
            };
            swatch.Click += (_, _) =>
            {
                color = hex;
                UpdatePreview(name.Text);
            };
            swatches.Children.Add(swatch);
        }
        root.Children.Add(swatches);

        var buttons = new DockPanel { Margin = new Thickness(0, 28, 0, 0), LastChildFill = false };
        var save = new Button { Style = S("AccentButton"), Content = "Enregistrer", MinWidth = 120, IsDefault = true };
        save.Click += (_, _) =>
        {
            Services.Profiles.Update(profile, name.Text, color);
            Close();
        };
        DockPanel.SetDock(save, Dock.Right);
        buttons.Children.Add(save);
        var cancel = new Button { Style = S("GhostButton"), Content = "Annuler", IsCancel = true, Margin = new Thickness(0, 0, 10, 0) };
        DockPanel.SetDock(cancel, Dock.Right);
        buttons.Children.Add(cancel);
        if (Services.Profiles.Profiles.Count > 1)
        {
            var delete = new Button { Style = S("GhostButton"), Content = "Supprimer le profil", Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x7A, 0x7A)) };
            delete.Click += (_, _) =>
            {
                var answer = MessageBox.Show(this, $"Supprimer le profil « {profile.Name} » ? Ses favoris, son historique et ses équipes seront effacés.", "Supprimer le profil", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                if (answer != MessageBoxResult.Yes) return;
                Services.Profiles.Delete(profile);
                Close();
            };
            DockPanel.SetDock(delete, Dock.Left);
            buttons.Children.Add(delete);
        }
        root.Children.Add(buttons);

        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false };
        UpdatePreview(profile.Name);
        Loaded += (_, _) =>
        {
            name.Focus();
            name.SelectAll();
        };
    }
}
