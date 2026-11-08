using System.Windows;
using System.Windows.Controls;
using ZappTV.Dialogs;

namespace ZappTV.Pages;

public partial class OnboardingPage : UserControl
{
    public OnboardingPage() => InitializeComponent();

    private void AddLink_Click(object sender, RoutedEventArgs e) => new LinkEditorWindow(null).ShowDialog();
    private void AddPlaylist_Click(object sender, RoutedEventArgs e) => new AddPlaylistWindow().ShowDialog();
}
