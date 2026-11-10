using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace ZappTV;

/// <summary>
/// Défilement fluide et précis, comme sur Mac : le pavé tactile déplace la page au pixel près,
/// la molette avance par petits pas animés, et le glissement horizontal fait défiler les rangées.
/// </summary>
public static class SmoothScroll
{
    private sealed class State
    {
        public double TargetY;
        public double TargetX;
        public bool AnimatingY;
        public bool AnimatingX;
    }

    private static readonly ConditionalWeakTable<ScrollViewer, State> States = new();
    private static readonly List<WeakReference<ScrollViewer>> Active = [];
    private static bool _rendering;

    /// <summary>Px par unité de molette (une encoche = 120 → ~84 px ; pavé tactile ≈ 1:1 avec le doigt).</summary>
    private const double Factor = 0.7;

    public static void Install()
    {
        EventManager.RegisterClassHandler(typeof(ScrollViewer), UIElement.PreviewMouseWheelEvent,
            new MouseWheelEventHandler(OnPreviewMouseWheel));
    }

    /// <summary>Glissement horizontal du pavé tactile (WM_MOUSEHWHEEL), que WPF ignore.</summary>
    public static void AttachHorizontal(Window window)
    {
        window.SourceInitialized += (_, _) =>
        {
            if (PresentationSource.FromVisual(window) is HwndSource source)
                source.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
                {
                    const int WM_MOUSEHWHEEL = 0x020E;
                    if (msg != WM_MOUSEHWHEEL) return IntPtr.Zero;
                    var delta = (short)((wParam.ToInt64() >> 16) & 0xFFFF);
                    if (Mouse.DirectlyOver is DependencyObject over && FindScrollable(over, horizontal: true) is { } viewer)
                    {
                        ScrollBy(viewer, delta * Factor, horizontal: true, precise: delta % 120 != 0);
                        handled = true;
                    }
                    return IntPtr.Zero;
                });
        };
    }

    private static void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Handled || sender is not ScrollViewer viewer) return;
        var horizontal = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        if (e.OriginalSource is not DependencyObject origin) return;
        // Seul le défileur le plus proche du pointeur qui peut bouger dans ce sens réagit.
        var target = FindScrollable(origin, horizontal);
        if (target != viewer) return;
        e.Handled = true;
        ScrollBy(viewer, -e.Delta * Factor, horizontal, precise: e.Delta % 120 != 0);
    }

    private static ScrollViewer? FindScrollable(DependencyObject start, bool horizontal)
    {
        for (DependencyObject? node = start; node != null; node = Parent(node))
        {
            if (node is not ScrollViewer viewer) continue;
            if (horizontal ? viewer.ScrollableWidth > 0 && viewer.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled
                           : viewer.ScrollableHeight > 0 && viewer.VerticalScrollBarVisibility != ScrollBarVisibility.Disabled)
                return viewer;
        }
        return null;
    }

    private static DependencyObject? Parent(DependencyObject node) =>
        node is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(node) ?? LogicalTreeHelper.GetParent(node) : LogicalTreeHelper.GetParent(node);

    /// <summary>
    /// Pavé tactile (petits deltas, <paramref name="precise"/>) : la page suit le doigt immédiatement, sans animation
    /// qui ajouterait du retard. Molette (crans de 120) : petit pas animé.
    /// </summary>
    private static void ScrollBy(ScrollViewer viewer, double pixels, bool horizontal, bool precise)
    {
        var state = States.GetValue(viewer, _ => new State());
        if (precise)
        {
            if (horizontal)
            {
                var start = state.AnimatingX ? state.TargetX : viewer.HorizontalOffset;
                state.AnimatingX = false;
                state.TargetX = Math.Clamp(start + pixels, 0, viewer.ScrollableWidth);
                viewer.ScrollToHorizontalOffset(state.TargetX);
            }
            else
            {
                var start = state.AnimatingY ? state.TargetY : viewer.VerticalOffset;
                state.AnimatingY = false;
                state.TargetY = Math.Clamp(start + pixels, 0, viewer.ScrollableHeight);
                viewer.ScrollToVerticalOffset(state.TargetY);
            }
            return;
        }
        if (horizontal)
        {
            if (!state.AnimatingX) state.TargetX = viewer.HorizontalOffset;
            state.TargetX = Math.Clamp(state.TargetX + pixels, 0, viewer.ScrollableWidth);
            state.AnimatingX = true;
        }
        else
        {
            if (!state.AnimatingY) state.TargetY = viewer.VerticalOffset;
            state.TargetY = Math.Clamp(state.TargetY + pixels, 0, viewer.ScrollableHeight);
            state.AnimatingY = true;
        }
        if (!Active.Any(r => r.TryGetTarget(out var v) && v == viewer)) Active.Add(new WeakReference<ScrollViewer>(viewer));
        if (!_rendering)
        {
            _rendering = true;
            CompositionTarget.Rendering += OnRendering;
        }
    }

    /// <summary>Chaque image rapproche la position de la cible (amorti doux).</summary>
    private static void OnRendering(object? sender, EventArgs e)
    {
        for (var i = Active.Count - 1; i >= 0; i--)
        {
            if (!Active[i].TryGetTarget(out var viewer) || !States.TryGetValue(viewer, out var state))
            {
                Active.RemoveAt(i);
                continue;
            }
            if (state.AnimatingY)
            {
                var current = viewer.VerticalOffset;
                var diff = state.TargetY - current;
                if (Math.Abs(diff) < 0.5) { viewer.ScrollToVerticalOffset(state.TargetY); state.AnimatingY = false; }
                else viewer.ScrollToVerticalOffset(current + diff * 0.35);
            }
            if (state.AnimatingX)
            {
                var current = viewer.HorizontalOffset;
                var diff = state.TargetX - current;
                if (Math.Abs(diff) < 0.5) { viewer.ScrollToHorizontalOffset(state.TargetX); state.AnimatingX = false; }
                else viewer.ScrollToHorizontalOffset(current + diff * 0.35);
            }
            if (!state.AnimatingX && !state.AnimatingY) Active.RemoveAt(i);
        }
        if (Active.Count == 0)
        {
            CompositionTarget.Rendering -= OnRendering;
            _rendering = false;
        }
    }
}
