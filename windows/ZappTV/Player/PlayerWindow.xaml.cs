using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using ZappTV.Core;
using Vlc = LibVLCSharp.Shared;

namespace ZappTV.Player;

public sealed class ZapEntry
{
    public required int Index { get; init; }
    public required string Title { get; init; }
    public string? Logo { get; init; }
    public bool IsCurrent { get; init; }
    public string Number => (Index + 1).ToString();
    public string Initials => TextUtil.Initials(Title);
    public bool HasLogo => !string.IsNullOrEmpty(Logo);
}

/// <summary>Lecteur VLC : tous les formats, zapping, plein écran, raccourcis clavier.</summary>
public partial class PlayerWindow : Window
{
    public static PlayerWindow? Current { get; private set; }

    private readonly Vlc.MediaPlayer _player;
    private readonly DispatcherTimer _uiTimer = new() { Interval = TimeSpan.FromMilliseconds(400) };
    private readonly DispatcherTimer _hideTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private IReadOnlyList<Playable> _queue = [];
    private int _index;
    private bool _videoReady;
    private bool _seeking;
    private bool _fullscreen;
    private bool _buffering;
    private DateTime _startedAt;
    private WindowState _restoreState;
    private Point _lastMouse;
    private long _resumeAt;
    private string? _recordPath;
    private DateTime _recordStartedAt;
    private readonly DispatcherTimer _nextTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private int _countdown;
    private DateTime _lastRecord;

    /// <summary>Ouvre le lecteur (ou réutilise celui déjà ouvert) sur une file de lecture.</summary>
    public static void Open(IReadOnlyList<Playable> queue, int index)
    {
        if (queue.Count == 0) return;
        if (Current is null)
        {
            Current = new PlayerWindow();
            Current.Show();
        }
        if (Current.WindowState == WindowState.Minimized) Current.WindowState = WindowState.Normal;
        Current.Load(queue, index);
        Current.Activate();
    }

    /// <summary>Raccourcis clavier, qu'il ait le focus ou que ce soit la couche des commandes.</summary>
    public static void RouteKey(object sender, KeyEventArgs e)
    {
        if (Current is not { } player || e.Handled) return;
        if (sender is not Window window) return;
        if (window == player || window.Owner == player || window.GetType().Name == "ForegroundWindow" && window.IsActive)
        {
            player.HandleKey(e);
        }
    }

    private PlayerWindow()
    {
        InitializeComponent();
        WindowSizing.Fit(this, 1280, 760);
        DarkTitleBar.Attach(this);

        _player = new Vlc.MediaPlayer(Services.LibVLC) { EnableHardwareDecoding = Services.Settings.Data.HardwareDecoding };
        VolumeSlider.Value = Services.Settings.Data.Volume;

        _player.Buffering += (_, e) =>
        {
            var cache = e.Cache;
            Dispatcher.InvokeAsync(() => SetBuffering(cache < 100f));
        };
        _player.Playing += (_, _) => Dispatcher.InvokeAsync(() =>
        {
            SetBuffering(false);
            ApplyResume();
        });
        _player.EncounteredError += (_, _) =>
            Dispatcher.InvokeAsync(() => ShowError("VLC n'a pas pu ouvrir ce flux. Vérifie le lien ou ta connexion."));
        _player.EndReached += (_, _) => Dispatcher.InvokeAsync(OnEnded);

        Video.Loaded += (_, _) =>
        {
            Video.MediaPlayer = _player;
            _videoReady = true;
            PlayCurrent();
            if (Services.Settings.Data.PlayerStartsFullscreen && !_fullscreen) ToggleFullscreen();
        };

        _uiTimer.Tick += (_, _) => RefreshProgress();
        _uiTimer.Start();
        _hideTimer.Tick += (_, _) => HideControls();
        _nextTimer.Tick += (_, _) => CountdownTick();
        Closed += OnClosed;
    }

    private Playable CurrentItem => _queue[_index];
    private bool CanZap => _queue.Count > 1 && CurrentItem.IsLive;
    private bool HasNextEpisode => !CurrentItem.IsLive && _index < _queue.Count - 1;
    private bool HasPreviousEpisode => !CurrentItem.IsLive && _index > 0;

    private void Load(IReadOnlyList<Playable> queue, int index)
    {
        RecordHistory(notify: true);
        _queue = queue;
        _index = Math.Clamp(index, 0, queue.Count - 1);
        PlayCurrent();
    }

    // ── Lecture ───────────────────────────────────────────────────────────

    private void PlayCurrent()
    {
        if (!_videoReady || _queue.Count == 0) return;
        var item = CurrentItem;
        StopRecordingState();
        CancelNextEpisode();
        _resumeAt = 0;
        if (!item.IsLive && Services.Settings.Data.ResumePlayback && Services.Profiles.HistoryFor(item.Id) is { CanResume: true } previous)
            _resumeAt = previous.PositionMs;

        Title = $"{item.Title} — iTv";
        TitleText.Text = item.Title;
        SubtitleText.Text = item.Subtitle ?? "";
        LiveBadge.Visibility = item.IsLive ? Visibility.Visible : Visibility.Collapsed;
        LogoFallback.Background = ThemeManager.GradientFor(item.Title);
        LogoInitials.Text = TextUtil.Initials(item.Title);
        var logo = ImageUrlConverter.Load(item.ArtworkUrl, 160);
        LogoImage.Source = logo;
        LogoImageBox.Visibility = logo != null ? Visibility.Visible : Visibility.Collapsed;

        var zap = CanZap ? Visibility.Visible : Visibility.Collapsed;
        ListButton.Visibility = ErrorNextButton.Visibility = zap;
        PrevButton.Visibility = CanZap || HasPreviousEpisode ? Visibility.Visible : Visibility.Collapsed;
        NextButton.Visibility = CanZap || HasNextEpisode ? Visibility.Visible : Visibility.Collapsed;
        PrevButton.ToolTip = CanZap ? "Chaîne précédente (↑)" : "Épisode précédent";
        NextButton.ToolTip = CanZap ? "Chaîne suivante (↓)" : "Épisode suivant (N)";
        var vod = item.IsLive ? Visibility.Collapsed : Visibility.Visible;
        SeekRow.Visibility = BackTenButton.Visibility = ForwardTenButton.Visibility = vod;
        HintText.Text = LinkInspector.Format(item.Url).Label() + " · VLC";
        if (!CanZap) ChannelPanel.Visibility = Visibility.Collapsed;

        ErrorPanel.Visibility = Visibility.Collapsed;
        SetBuffering(true);
        _startedAt = DateTime.Now;
        Seek.Value = 0;
        TimeText.Text = "0:00";
        RemainingText.Text = "";

        StartMedia(0, null);

        RefreshChannelList();
        ShowControls();
    }

    /// <summary>Lance le flux courant, éventuellement à une position et en l'enregistrant dans un fichier.</summary>
    private void StartMedia(long startMs, string? recordPath)
    {
        using var media = new Vlc.Media(Services.LibVLC, CurrentItem.Url, Vlc.FromType.FromLocation);
        media.AddOption($":network-caching={Math.Clamp(Services.Settings.Data.NetworkCacheMs, 300, 20000)}");
        media.AddOption(":http-reconnect");
        if (startMs > 0) media.AddOption(":start-time=" + (startMs / 1000.0).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture));
        if (recordPath != null)
        {
            // Lecture à l'écran + copie du flux dans un fichier, sans réencodage.
            var dst = recordPath.Replace('\\', '/');
            media.AddOption($":sout=#duplicate{{dst=display,dst=std{{access=file,mux=ts,dst='{dst}'}}}}");
            media.AddOption(":sout-keep");
        }
        _player.Play(media);
        _player.Volume = (int)VolumeSlider.Value;
    }

    // ── Enregistrement ────────────────────────────────────────────────────

    public static string RecordingsFolder =>
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "iTv");

    private void ToggleRecording()
    {
        if (_queue.Count == 0) return;
        var position = CurrentItem.IsLive ? 0 : Math.Max(0, _player.Time);
        if (_recordPath is null)
        {
            try
            {
                System.IO.Directory.CreateDirectory(RecordingsFolder);
            }
            catch (Exception ex)
            {
                ShowHint($"Impossible de créer le dossier d'enregistrement : {ex.Message}");
                return;
            }
            var invalid = System.IO.Path.GetInvalidFileNameChars();
            var name = new string(CurrentItem.Title.Select(c => invalid.Contains(c) ? '_' : c).ToArray()).Trim();
            if (name.Length > 60) name = name[..60];
            var path = System.IO.Path.Combine(RecordingsFolder, $"{name} {DateTime.Now:yyyy-MM-dd HH-mm-ss}.ts");
            _recordPath = path;
            _recordStartedAt = DateTime.Now;
            StartMedia(position, path);
            RecBadge.Visibility = Visibility.Visible;
            RecordDot.Fill = Brushes.White;
            RecordButton.ToolTip = "Arrêter l'enregistrement (R)";
            ShowHint("Enregistrement en cours · usage privé uniquement");
        }
        else
        {
            var saved = _recordPath;
            StopRecordingState();
            StartMedia(position, null);
            ShowHint($"Enregistré dans Vidéos\\iTv : {System.IO.Path.GetFileName(saved)}");
        }
    }

    private void StopRecordingState()
    {
        _recordPath = null;
        RecBadge.Visibility = Visibility.Collapsed;
        RecordDot.Fill = new SolidColorBrush(Color.FromRgb(0xE5, 0x48, 0x4D));
        RecordButton.ToolTip = "Enregistrer le flux (R)";
    }

    private void ShowHint(string message)
    {
        HintText.Text = message;
        ShowControls();
    }

    // ── Épisode suivant ───────────────────────────────────────────────────

    private void StartNextEpisodeCountdown()
    {
        if (!HasNextEpisode || !Services.Settings.Data.AutoPlayNext) return;
        var next = _queue[_index + 1];
        NextEpisodeTitle.Text = next.Title;
        NextEpisodeSubtitle.Text = next.Subtitle ?? "";
        _countdown = 10;
        CountdownText.Text = _countdown.ToString();
        NextEpisodePanel.Visibility = Visibility.Visible;
        _nextTimer.Start();
        ShowControls();
    }

    private void CountdownTick()
    {
        _countdown--;
        CountdownText.Text = Math.Max(0, _countdown).ToString();
        if (_countdown <= 0) PlayNextEpisode();
    }

    private void PlayNextEpisode()
    {
        CancelNextEpisode();
        if (!HasNextEpisode) return;
        RecordHistory(notify: true);
        _index++;
        PlayCurrent();
    }

    private void CancelNextEpisode()
    {
        _nextTimer.Stop();
        NextEpisodePanel.Visibility = Visibility.Collapsed;
    }

    private void NextEpisodeNow_Click(object sender, RoutedEventArgs e) => PlayNextEpisode();
    private void NextEpisodeCancel_Click(object sender, RoutedEventArgs e) => CancelNextEpisode();
    private void Record_Click(object sender, RoutedEventArgs e) => ToggleRecording();

    /// <summary>Reprise d'un film / épisode là où on s'était arrêté.</summary>
    private void ApplyResume()
    {
        if (_resumeAt <= 0 || _player.Length <= 0) return;
        var target = Math.Min(_resumeAt, _player.Length - 5000);
        _resumeAt = 0;
        if (target <= 0) return;
        _player.Time = target;
        HintText.Text = $"Reprise à {Format(target)}";
    }

    /// <summary>Historique du profil : chaînes récentes et « Reprendre la lecture ».</summary>
    private void RecordHistory(bool notify)
    {
        if (_queue.Count == 0 || _index >= _queue.Count) return;
        var item = CurrentItem;
        try
        {
            if (item.IsLive)
            {
                // Chaîne : comptée comme regardée après quelques secondes de lecture.
                if (DateTime.Now - _startedAt < TimeSpan.FromSeconds(5)) return;
                if (_player.Time <= 0 && !_player.IsPlaying) return;
                Services.Profiles.Record(item, -1, 0, notify);
                return;
            }
            var length = _player.Length;
            var time = _player.Time;
            if (length <= 0 || time <= 0) return;
            Services.Profiles.Record(item, time, length, notify);
        }
        catch
        {
            // Lecteur en cours d'arrêt : rien à enregistrer.
        }
    }

    private void Zap(int delta)
    {
        if (!CanZap) return;
        RecordHistory(notify: true);
        _index = (_index + delta + _queue.Count) % _queue.Count;
        PlayCurrent();
    }

    private void TogglePause()
    {
        var state = _player.State;
        if (state is Vlc.VLCState.Ended or Vlc.VLCState.Stopped or Vlc.VLCState.Error) PlayCurrent();
        else _player.SetPause(_player.IsPlaying);
        RefreshProgress();
    }

    private void Jump(int seconds)
    {
        if (CurrentItem.IsLive || _player.Length <= 0) return;
        _player.Time = Math.Clamp(_player.Time + seconds * 1000L, 0, Math.Max(0, _player.Length - 1000));
    }

    private void ChangeVolume(int delta) =>
        VolumeSlider.Value = Math.Clamp(VolumeSlider.Value + delta, 0, 100);

    private void OnEnded()
    {
        PlayPauseGlyph.Text = "";
        if (_recordPath != null)
        {
            var saved = _recordPath;
            StopRecordingState();
            HintText.Text = $"Enregistré : {System.IO.Path.GetFileName(saved)}";
        }
        // Fin d'un film ou d'un épisode : il sort de « Reprendre la lecture ».
        if (!CurrentItem.IsLive) Services.Profiles.RemoveHistory(CurrentItem.Id);
        ShowControls();
        StartNextEpisodeCountdown();
    }

    private void SetBuffering(bool buffering)
    {
        _buffering = buffering;
        BufferingPanel.Visibility = buffering && ErrorPanel.Visibility != Visibility.Visible ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ShowError(string message)
    {
        SetBuffering(false);
        ErrorText.Text = message;
        ErrorPanel.Visibility = Visibility.Visible;
        BufferingPanel.Visibility = Visibility.Collapsed;
        ShowControls();
    }

    private void RefreshProgress()
    {
        if (_queue.Count == 0) return;
        PlayPauseGlyph.Text = _player.IsPlaying ? "" : "";

        if (_buffering && ErrorPanel.Visibility != Visibility.Visible
            && DateTime.Now - _startedAt > TimeSpan.FromSeconds(30) && _player.Time <= 0)
        {
            ShowError("Le flux ne répond pas (délai dépassé).");
        }

        if (_recordPath != null)
        {
            var elapsed = DateTime.Now - _recordStartedAt;
            RecText.Text = $"REC {(int)elapsed.TotalMinutes}:{elapsed.Seconds:00}";
        }

        if (DateTime.Now - _lastRecord > TimeSpan.FromSeconds(5) && _player.IsPlaying)
        {
            _lastRecord = DateTime.Now;
            RecordHistory(notify: false);
        }

        var length = _player.Length;
        if (CurrentItem.IsLive || length <= 0) return;
        var time = Math.Max(0, _player.Time);
        if (!_seeking) Seek.Value = Math.Clamp((double)time / length, 0, 1);
        TimeText.Text = Format(time);
        RemainingText.Text = "-" + Format(Math.Max(0, length - time));
    }

    private static string Format(long milliseconds)
    {
        var t = TimeSpan.FromMilliseconds(milliseconds);
        return t.TotalHours >= 1 ? $"{(int)t.TotalHours}:{t.Minutes:00}:{t.Seconds:00}" : $"{t.Minutes}:{t.Seconds:00}";
    }

    // ── Liste de zapping ──────────────────────────────────────────────────

    private void RefreshChannelList()
    {
        if (!CanZap)
        {
            ChannelList.ItemsSource = null;
            return;
        }
        ChannelList.ItemsSource = _queue.Select((p, i) => new ZapEntry
        {
            Index = i,
            Title = p.Title,
            Logo = p.ArtworkUrl,
            IsCurrent = i == _index,
        }).ToList();
        if (ChannelPanel.Visibility == Visibility.Visible) ScrollToCurrent();
    }

    private void ScrollToCurrent()
    {
        if (ChannelList.Items.Count > _index) ChannelList.ScrollIntoView(ChannelList.Items[_index]);
    }

    private void ToggleList()
    {
        if (!CanZap) return;
        ChannelPanel.Visibility = ChannelPanel.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
        if (ChannelPanel.Visibility == Visibility.Visible) ScrollToCurrent();
        ShowControls();
    }

    // ── Affichage des commandes ───────────────────────────────────────────

    private void ShowControls()
    {
        TopBar.Visibility = BottomBar.Visibility = Visibility.Visible;
        Overlay.Cursor = null;
        _hideTimer.Stop();
        _hideTimer.Start();
    }

    private void HideControls()
    {
        _hideTimer.Stop();
        if (!_player.IsPlaying || ChannelPanel.Visibility == Visibility.Visible || ErrorPanel.Visibility == Visibility.Visible
            || TopBar.IsMouseOver || BottomBar.IsMouseOver || _seeking)
        {
            return;
        }
        TopBar.Visibility = BottomBar.Visibility = Visibility.Hidden;
        Overlay.Cursor = Cursors.None;
    }

    private void ToggleFullscreen()
    {
        if (!_fullscreen)
        {
            _restoreState = WindowState;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            if (WindowState == WindowState.Maximized) WindowState = WindowState.Normal;
            WindowState = WindowState.Maximized;
        }
        else
        {
            WindowStyle = WindowStyle.SingleBorderWindow;
            ResizeMode = ResizeMode.CanResize;
            WindowState = _restoreState;
        }
        _fullscreen = !_fullscreen;
        FullscreenGlyph.Text = _fullscreen ? "" : "";
        ShowControls();
    }

    // ── Clavier ───────────────────────────────────────────────────────────

    public void HandleKey(KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Space:
                TogglePause();
                break;
            case Key.Escape:
                if (ChannelPanel.Visibility == Visibility.Visible) ToggleList();
                else if (_fullscreen) ToggleFullscreen();
                else Close();
                break;
            case Key.F:
            case Key.F11:
            case Key.Enter:
                ToggleFullscreen();
                break;
            case Key.M:
                Mute_Click(this, new RoutedEventArgs());
                break;
            case Key.L:
                ToggleList();
                break;
            case Key.R:
                ToggleRecording();
                break;
            case Key.N:
                if (HasNextEpisode) PlayNextEpisode();
                break;
            case Key.Up:
                if (CanZap) Zap(-1); else ChangeVolume(5);
                break;
            case Key.Down:
                if (CanZap) Zap(1); else ChangeVolume(-5);
                break;
            case Key.PageUp:
                Zap(-1);
                break;
            case Key.PageDown:
                Zap(1);
                break;
            case Key.Left:
                Jump(-10);
                break;
            case Key.Right:
                Jump(10);
                break;
            default:
                return;
        }
        e.Handled = true;
        if (Current != null) ShowControls();
    }

    // ── Souris ────────────────────────────────────────────────────────────

    private void Overlay_MouseMove(object sender, MouseEventArgs e)
    {
        var position = e.GetPosition(Overlay);
        if ((position - _lastMouse).Length < 2) return;
        _lastMouse = position;
        ShowControls();
    }

    private void Overlay_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2) ToggleFullscreen();
        Overlay.Focus();
    }

    private void Overlay_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (ChannelPanel.IsMouseOver) return;
        ChangeVolume(e.Delta > 0 ? 5 : -5);
        ShowControls();
    }

    // ── Boutons ───────────────────────────────────────────────────────────

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
    private void List_Click(object sender, RoutedEventArgs e) => ToggleList();
    private void Prev_Click(object sender, RoutedEventArgs e)
    {
        if (CanZap) Zap(-1);
        else if (HasPreviousEpisode)
        {
            RecordHistory(notify: true);
            _index--;
            PlayCurrent();
        }
    }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (CanZap) Zap(1);
        else PlayNextEpisode();
    }
    private void PlayPause_Click(object sender, RoutedEventArgs e) => TogglePause();
    private void BackTen_Click(object sender, RoutedEventArgs e) => Jump(-10);
    private void ForwardTen_Click(object sender, RoutedEventArgs e) => Jump(10);
    private void Fullscreen_Click(object sender, RoutedEventArgs e) => ToggleFullscreen();
    private void Retry_Click(object sender, RoutedEventArgs e) => PlayCurrent();

    private void Channel_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: int index } && index != _index)
        {
            _index = index;
            PlayCurrent();
        }
    }

    private void Mute_Click(object sender, RoutedEventArgs e)
    {
        _player.Mute = !_player.Mute;
        VolumeGlyph.Text = _player.Mute ? "" : "";
    }

    private void Volume_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_player is null) return;
        _player.Volume = (int)e.NewValue;
        if (_player.Mute && e.NewValue > 0) _player.Mute = false;
        VolumeGlyph.Text = _player.Mute || e.NewValue == 0 ? "" : "";
    }

    private void Seek_MouseDown(object sender, MouseButtonEventArgs e) => _seeking = true;

    private void Seek_MouseUp(object sender, MouseButtonEventArgs e)
    {
        // Laisse le curseur se placer sous la souris avant de lire sa valeur.
        Dispatcher.InvokeAsync(() =>
        {
            if (_player.Length > 0) _player.Position = (float)Seek.Value;
            _seeking = false;
        }, DispatcherPriority.Input);
    }

    // ── Fermeture ─────────────────────────────────────────────────────────

    private void OnClosed(object? sender, EventArgs e)
    {
        RecordHistory(notify: true);
        _nextTimer.Stop();
        Current = null;
        _uiTimer.Stop();
        _hideTimer.Stop();
        var volume = VolumeSlider.Value;
        Services.Settings.Update(s => s.Volume = volume, notify: false);

        Video.MediaPlayer = null;
        var player = _player;
        // Arrêt hors du thread de l'interface : VLC peut prendre un instant pour couper le réseau.
        Task.Run(() =>
        {
            player.Stop();
            player.Dispose();
        });
    }
}
