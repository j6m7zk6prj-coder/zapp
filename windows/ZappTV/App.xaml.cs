using System.Windows;
using ZappTV.Core;
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
        if (Services.Settings.Data.ThemeVersion < 3)
        {
            // Passage à iTv : fond noir, violet iTv, accueil réduit à l'essentiel.
            Services.Settings.Update(s =>
            {
                if (s.Accent is 0x4F6BFF or 0x7C5CFF) s.Accent = AppSettingsData.DefaultAccent;
                if (s.Background == BackgroundStyle.Night) s.Background = BackgroundStyle.Oled;
                s.HomeSections = [];
                s.ThemeVersion = 3;
            }, notify: false);
        }
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
            "iTv", MessageBoxButton.OK, MessageBoxImage.Warning);
        e.Handled = true;
    }
}
