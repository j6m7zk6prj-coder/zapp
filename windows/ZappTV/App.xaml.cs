using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using ZappTV.Player;

namespace ZappTV;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnUnhandledException;

        LibVLCSharp.Shared.Core.Initialize();
        Services.Initialize();
        ThemeManager.Apply(Services.Settings.Data);
        Services.Settings.Changed += () => ThemeManager.Apply(Services.Settings.Data);

        // Raccourcis du lecteur, quelle que soit la fenêtre qui a le focus (vidéo ou commandes).
        EventManager.RegisterClassHandler(typeof(Window), Keyboard.PreviewKeyDownEvent,
            new KeyEventHandler((sender, args) => PlayerWindow.RouteKey(sender, args)));

        var window = new MainWindow();
        MainWindow = window;
        window.Show();

        Services.LoadActivePlaylist();
    }

    private static void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(
            $"Une erreur inattendue s'est produite :\n\n{e.Exception.Message}",
            "Zapp TV", MessageBoxButton.OK, MessageBoxImage.Warning);
        e.Handled = true;
    }
}
