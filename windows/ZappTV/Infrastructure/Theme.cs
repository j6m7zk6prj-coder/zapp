using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Data;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ZappTV.Core;

namespace ZappTV;

/// <summary>Pose les couleurs du thème dans les ressources de l'app (mises à jour en direct).</summary>
public static class ThemeManager
{
    public static Color Background { get; private set; }

    public static void Apply(AppSettingsData settings)
    {
        var resources = Application.Current.Resources;
        var palette = settings.Background.Palette();
        var bg = ColorOf(palette.Base);
        var glow = ColorOf(palette.Glow);
        var accent = ColorOf(settings.Accent);
        Background = bg;

        resources["BgColor"] = bg;
        resources["BgBrush"] = Frozen(new SolidColorBrush(bg));
        resources["SurfaceBrush"] = Frozen(new SolidColorBrush(ColorOf(palette.Surface)));
        resources["SurfaceHighBrush"] = Frozen(new SolidColorBrush(ColorOf(palette.SurfaceHigh)));
        resources["AccentColor"] = accent;
        resources["AccentBrush"] = Frozen(new SolidColorBrush(accent));
        resources["OnAccentBrush"] = Frozen(new SolidColorBrush(IsLight(settings.Accent) ? Colors.Black : Colors.White));
        // Accent adouci (mélangé au blanc) pour les mots en italique.
        resources["AccentSoftBrush"] = Frozen(new SolidColorBrush(Color.FromRgb(
            (byte)((accent.R + 255 * 2) / 3), (byte)((accent.G + 255 * 2) / 3), (byte)((accent.B + 255 * 2) / 3))));
        resources["TopBarBrush"] = Frozen(new SolidColorBrush(Color.FromArgb(0xF2, bg.R, bg.G, bg.B)));

        // Fond iTv : noir profond, lueur colorée en haut à gauche et lueur chaude en bas à droite.
        var glowLayer = new RadialGradientBrush(
            [new GradientStop(Color.FromArgb(0x70, glow.R, glow.G, glow.B), 0), new GradientStop(Color.FromArgb(0, glow.R, glow.G, glow.B), 1)])
        { Center = new Point(0.12, 0), GradientOrigin = new Point(0.12, 0), RadiusX = 0.75, RadiusY = 0.85 };
        var warmLayer = new RadialGradientBrush(
            [new GradientStop(Color.FromArgb(0x26, 0xFF, 0x8A, 0x4C), 0), new GradientStop(Color.FromArgb(0, 0xFF, 0x8A, 0x4C), 1)])
        { Center = new Point(0.95, 1), GradientOrigin = new Point(0.95, 1), RadiusX = 0.7, RadiusY = 0.8 };
        var drawing = new DrawingGroup();
        var rect = new RectangleGeometry(new Rect(0, 0, 1, 1));
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(bg), null, rect));
        drawing.Children.Add(new GeometryDrawing(glowLayer, null, rect));
        drawing.Children.Add(new GeometryDrawing(warmLayer, null, rect));
        resources["BackdropBrush"] = Frozen(new DrawingBrush(drawing) { Stretch = Stretch.Fill });
        resources["FadeBottomBrush"] = Frozen(new LinearGradientBrush(
            [new GradientStop(Color.FromArgb(0, bg.R, bg.G, bg.B), 0), new GradientStop(Color.FromArgb(200, bg.R, bg.G, bg.B), 0.6), new GradientStop(bg, 1)],
            new Point(0, 0), new Point(0, 1)));
        resources["FadeLeftBrush"] = Frozen(new LinearGradientBrush(
            [new GradientStop(Color.FromArgb(235, bg.R, bg.G, bg.B), 0), new GradientStop(Color.FromArgb(140, bg.R, bg.G, bg.B), 0.45), new GradientStop(Color.FromArgb(0, bg.R, bg.G, bg.B), 1)],
            new Point(0, 0), new Point(1, 0)));

        foreach (Window window in Application.Current.Windows) DarkTitleBar.Apply(window);
    }

    public static Color ColorOf(uint hex) =>
        Color.FromRgb((byte)((hex >> 16) & 0xFF), (byte)((hex >> 8) & 0xFF), (byte)(hex & 0xFF));

    public static bool IsLight(uint hex)
    {
        double r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF;
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.68;
    }

    public static uint? ParseHex(string text)
    {
        var value = text.Trim().TrimStart('#');
        return value.Length == 6 && uint.TryParse(value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var hex)
            ? hex
            : null;
    }

    private static readonly (uint, uint)[] Palettes =
    [
        (0x2A9DB5, 0x1E3A8A), (0xC0344F, 0x7A1F3D), (0xB8333A, 0x7C2D12), (0x9333EA, 0x581C87),
        (0x2563EB, 0x1E3A8A), (0xC026D3, 0x831843), (0x22A447, 0x166534), (0x4338CA, 0x312E81),
        (0x84CC16, 0x3F6212), (0xD97706, 0x78350F), (0x14B8A6, 0x115E59),
    ];

    private static readonly Brush?[] GradientCache = new Brush?[Palettes.Length];

    /// <summary>Dégradé stable dérivé d'un nom, utilisé quand il n'y a pas d'image.</summary>
    public static Brush GradientFor(string? seed)
    {
        var index = (int)(TextUtil.StableHash(string.IsNullOrEmpty(seed) ? "?" : seed) % (ulong)Palettes.Length);
        return GradientCache[index] ??= Frozen(new LinearGradientBrush(ColorOf(Palettes[index].Item1), ColorOf(Palettes[index].Item2), 45));
    }

    private static T Frozen<T>(T freezable) where T : Freezable
    {
        freezable.Freeze();
        return freezable;
    }
}

/// <summary>Barre de titre sombre (couleur du fond) sous Windows 10/11.</summary>
public static class DarkTitleBar
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void Attach(Window window)
    {
        window.SourceInitialized += (_, _) => Apply(window);
    }

    public static void Apply(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        try
        {
            var on = 1;
            DwmSetWindowAttribute(handle, 20, ref on, sizeof(int)); // Mode sombre
            var bg = ThemeManager.Background;
            var colorRef = bg.R | (bg.G << 8) | (bg.B << 16);
            DwmSetWindowAttribute(handle, 35, ref colorRef, sizeof(int)); // Couleur de la barre (Windows 11)
        }
        catch
        {
            // Versions de Windows sans ces attributs : sans gravité.
        }
    }
}

/// <summary>URL ou chemin d'image → image (téléchargée en arrière-plan, mise en cache).</summary>
public sealed class ImageUrlConverter : IValueConverter
{
    private static readonly Dictionary<string, WeakReference<BitmapImage>> Cache = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        Load(value as string, parameter is string p && int.TryParse(p, out var w) ? w : 0);

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        Binding.DoNothing;

    public static BitmapImage? Load(string? url, int decodeWidth = 0)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        var key = $"{url}|{decodeWidth}";
        if (Cache.TryGetValue(key, out var weak) && weak.TryGetTarget(out var cached)) return cached;
        try
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return null;
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = uri;
            image.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            if (decodeWidth > 0) image.DecodePixelWidth = decodeWidth;
            if (uri.IsFile)
            {
                if (!System.IO.File.Exists(uri.LocalPath)) return null;
                // Charge tout de suite pour ne pas verrouiller le fichier.
                image.CacheOption = BitmapCacheOption.OnLoad;
            }
            image.EndInit();
            Cache[key] = new WeakReference<BitmapImage>(image);
            return image;
        }
        catch
        {
            return null;
        }
    }
}

public sealed class GradientConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        ThemeManager.GradientFor(value as string);

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        Binding.DoNothing;
}
