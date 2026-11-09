using System.Windows;

namespace ZappTV;

/// <summary>
/// Adapte la taille des fenêtres à l'écran (PC portables, mise à l'échelle 125–150 %) :
/// jamais plus grandes que la zone utile, pour que la barre de titre reste visible.
/// </summary>
public static class WindowSizing
{
    private const double ScreenMargin = 40;

    /// <summary>Fenêtre principale ou lecteur : taille souhaitée, réduite si l'écran est petit (agrandie dans ce cas).</summary>
    public static void Fit(Window window, double width, double height)
    {
        var area = SystemParameters.WorkArea;
        var maxWidth = Math.Max(400, area.Width - ScreenMargin);
        var maxHeight = Math.Max(300, area.Height - ScreenMargin);

        window.MinWidth = Math.Min(window.MinWidth, maxWidth);
        window.MinHeight = Math.Min(window.MinHeight, maxHeight);
        window.Width = Math.Min(width, maxWidth);
        window.Height = Math.Min(height, maxHeight);

        window.WindowStartupLocation = WindowStartupLocation.Manual;
        window.Left = area.Left + (area.Width - window.Width) / 2;
        window.Top = area.Top + (area.Height - window.Height) / 2;

        // Écran plus petit que la taille prévue : on ouvre directement en plein écran (fenêtré).
        if (width > maxWidth || height > maxHeight) window.WindowState = WindowState.Maximized;
    }

    /// <summary>Fenêtres d'ajout / modification : hauteur limitée à l'écran (le contenu défile).</summary>
    public static void FitDialog(Window window)
    {
        var area = SystemParameters.WorkArea;
        window.MaxHeight = Math.Max(300, area.Height - ScreenMargin);
        window.MaxWidth = Math.Max(400, area.Width - ScreenMargin);
        if (window.Width > window.MaxWidth) window.Width = window.MaxWidth;
    }
}
