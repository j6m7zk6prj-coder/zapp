import AVKit
import SwiftUI
import UIKit

/// Lecteur plein écran. HLS/MP4 via le lecteur iOS, tout le reste via VLC,
/// avec zapping (précédente / suivante / liste) pour le direct.
struct PlayerView: View {
    let request: PlaybackRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings
    @State private var countdown: Int?
    @State private var startedAt = Date()
    @State private var recordingNotice: String?
    @State private var recorder = StreamRecorder()
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showRecordInfo = false
    @AppStorage("recordings.infoShown") private var recordInfoShown = false
    @State private var native = NativePlayerModel()
    @State private var vlc = VLCPlayerModel()
    @State private var index: Int
    @State private var usingVLC = false
    @State private var showChannelList = false
    @State private var chromeVisible = true
    @State private var scrubbing: Double?
    @State private var fill = false

    init(request: PlaybackRequest) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    private var current: Playable { request.queue[index] }
    private var canZap: Bool { current.isLive && request.queue.count > 1 }
    private var hasNextEpisode: Bool { !current.isLive && index < request.queue.count - 1 }
    private var ended: Bool { usingVLC ? vlc.ended : native.ended }
    private var activeError: String? { usingVLC ? vlc.error : native.error }
    private var isPlaying: Bool { usingVLC ? vlc.isPlaying : native.isPlaying }
    private var isBuffering: Bool { usingVLC ? vlc.isBuffering : native.isBuffering }
    private var position: Double { usingVLC ? vlc.position : native.position }
    private var durationMs: Int { usingVLC ? Int(vlc.durationMs) : native.durationMs }
    private var timeText: String { usingVLC ? vlc.timeText : native.timeText }
    private var remainingText: String { usingVLC ? vlc.remainingText : native.remainingText }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Vidéo en plein écran (bord à bord), sans les commandes d'iOS.
            Group {
                if usingVLC {
                    VLCSurface(model: vlc)
                } else {
                    SystemPlayer(player: native.player, fill: fill)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Zone de toucher : afficher / masquer les commandes, double-tap = remplir l'écran, pincer = zoom.
            Color.black.opacity(chromeVisible ? 0.35 : 0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFill() }
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } }
                .gesture(MagnifyGesture().onEnded { value in
                    let wantFill = value.magnification > 1
                    if wantFill != fill { toggleFill() }
                })

            if isBuffering && activeError == nil {
                ProgressView().controlSize(.large).tint(.white)
            }

            if chromeVisible {
                chrome
                    .transition(.opacity)
            }

            if let error = activeError {
                errorOverlay(error)
            }
            if let countdown, hasNextEpisode {
                nextEpisodeCard(countdown)
            }
            if let recordingNotice {
                VStack {
                    Label(recordingNotice, systemImage: recordingNotice.hasPrefix("Enregistré") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .multilineTextAlignment(.center)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 60)
                        .padding(.horizontal)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { self.recordingNotice = nil }
                }
            }
        }
        .statusBarHidden(!chromeVisible)
        .task(id: chromeVisible) {
            // Les commandes se masquent toutes seules pendant la lecture.
            guard chromeVisible else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, isPlaying, scrubbing == nil, activeError == nil else { return }
            withAnimation(.easeInOut(duration: 0.3)) { chromeVisible = false }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { start() }
        .onChange(of: index) { oldValue, _ in
            recordPosition(of: request.queue[oldValue])
            finishRecording()
            start()
        }
        .alert("Enregistrer le flux", isPresented: $showRecordInfo) {
            Button("Enregistrer") {
                recordInfoShown = true
                beginRecording()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le flux est copié tel quel, en pleine qualité (meilleure qualité disponible), dans l'app Fichiers › iTv › Enregistrements. Compte 2 à 4 Go par heure en Full HD. L'enregistrement continue si tu changes d'appli, tant que la lecture continue. Usage privé uniquement : pas de partage ni de diffusion.")
        }
        .onChange(of: native.error) { fallBackToVLCIfPossible() }
        .onChange(of: recorder.failure) { _, failure in
            // L'enregistrement s'est arrêté tout seul (flux coupé, plus de place…).
            guard let failure else { return }
            withAnimation { recordingNotice = failure }
        }
        .onChange(of: ended) { _, isEnded in
            guard isEnded else { return }
            finishRecording()
            // Fin du film ou de l'épisode : il sort de « Reprendre la lecture ».
            if !current.isLive { profiles.removeHistory(current.id) }
            if hasNextEpisode && settings.autoPlayNext { countdown = 10 }
        }
        .task(id: countdown) {
            guard let value = countdown else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, countdown == value else { return }
            if value <= 1 {
                playNextEpisode()
            } else {
                countdown = value - 1
            }
        }
        .task(id: index) {
            // Position enregistrée régulièrement pour « Reprendre » et « Regardées récemment ».
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                recordPosition(of: current)
            }
        }
        .onDisappear {
            recordPosition(of: current)
            finishRecording()
            native.stop()
            vlc.stop()
        }
        .sheet(isPresented: $showChannelList) {
            ZapList(queue: request.queue, current: $index)
                .presentationDetents([.medium, .large])
        }
        .persistentSystemOverlays(.hidden)
    }

    // MARK: Lecture

    private func start() {
        let url = current.url
        countdown = nil
        startedAt = Date()
        var startMs = 0
        if !current.isLive, settings.resumePlayback, let entry = profiles.history(for: current.id), entry.canResume {
            startMs = entry.positionMs
        }
        if PlaybackSupport.usesVLC(url, preference: AppSettings.shared.engine) {
            native.stop()
            usingVLC = true
            vlc.play(url, startMs: startMs)
        } else {
            vlc.stop()
            usingVLC = false
            native.play(url, startMs: startMs)
        }
    }

    private func recordPosition(of playable: Playable) {
        guard playable.id == current.id else {
            // Changement de chaîne : on garde juste la chaîne dans l'historique.
            if playable.isLive { profiles.record(playable, positionMs: nil, durationMs: nil) }
            return
        }
        if playable.isLive {
            guard Date().timeIntervalSince(startedAt) > 5, activeError == nil else { return }
            profiles.record(playable, positionMs: nil, durationMs: nil)
            return
        }
        let position = usingVLC ? Int(vlc.currentMs) : native.currentMs
        let duration = usingVLC ? Int(vlc.durationMs) : native.durationMs
        guard position > 0, duration > 0, !ended else { return }
        profiles.record(playable, positionMs: position, durationMs: duration)
    }

    // MARK: Enregistrement

    /// Enregistrable : flux http(s) copié directement, ou autre protocole via VLC.
    private var canRecord: Bool {
        guard !current.url.isFileURL else { return false }
        return StreamRecorder.supports(current.url) || PlaybackSupport.vlcAvailable
    }

    private func toggleRecording() {
        if recorder.isRecording {
            finishRecording()
        } else if recordInfoShown {
            beginRecording()
        } else {
            showRecordInfo = true
        }
    }

    /// Les flux http(s) (HLS, TS, MP4…) sont copiés à part, sans toucher à la lecture.
    /// Les autres protocoles (RTMP, RTSP, UDP…) passent par l'enregistreur de VLC.
    private func beginRecording() {
        let url = current.url
        if StreamRecorder.supports(url) {
            recorder.start(url: url, title: current.title)
        } else {
            if !usingVLC {
                native.stop()
                usingVLC = true
                vlc.play(url)
            }
            recorder.startWithVLC(vlc, title: current.title)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func finishRecording() {
        guard recorder.isRecording else { return }
        recorder.stop(vlc: vlc) { result in
            withAnimation(.snappy) {
                switch result {
                case .success(let file):
                    recordingNotice = "Enregistré (\(file.sizeText)) dans Fichiers › iTv › Enregistrements"
                case .failure(let error):
                    recordingNotice = error.localizedDescription
                }
            }
        }
    }

    private func playNextEpisode() {
        countdown = nil
        guard hasNextEpisode else { return }
        index += 1
    }

    private func nextEpisodeCard(_ value: Int) -> some View {
        let next = request.queue[index + 1]
        return VStack {
            Spacer()
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(value) / 10)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: value)
                    Text("\(value)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ÉPISODE SUIVANT")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(next.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let subtitle = next.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(spacing: 8) {
                    Button("Lire") { playNextEpisode() }
                        .buttonStyle(WhiteCapsuleStyle())
                    Button("Annuler") { countdown = nil }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .padding()
            .frame(maxWidth: 520)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Le lecteur iOS n'a pas pu lire le flux : VLC prend le relais.
    private func fallBackToVLCIfPossible() {
        guard native.error != nil, !usingVLC,
              AppSettings.shared.engine == .auto,
              PlaybackSupport.vlcAvailable else { return }
        native.stop()
        usingVLC = true
        vlc.play(current.url, startMs: native.currentMs)
    }

    private func zap(_ delta: Int) {
        let count = request.queue.count
        index = (index + delta % count + count) % count
    }

    // MARK: Commandes

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
                .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            Spacer()
            centerControls
            Spacer()
            bottomBar
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
    }

    private var centerControls: some View {
        HStack(spacing: 50) {
            if !current.isLive {
                Button { jump(-10) } label: { Image(systemName: "gobackward.10") }
                    .accessibilityLabel("Reculer de 10 secondes")
            } else if canZap {
                Button { zap(-1) } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Chaîne précédente")
            }
            Button {
                togglePause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40))
                    .frame(width: 76, height: 76)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
            .opacity(isBuffering ? 0 : 1)
            if !current.isLive {
                Button { jump(10) } label: { Image(systemName: "goforward.10") }
                    .accessibilityLabel("Avancer de 10 secondes")
            } else if canZap {
                Button { zap(1) } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Chaîne suivante")
            }
        }
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if !current.isLive && durationMs > 0 {
                Slider(
                    value: Binding(get: { scrubbing ?? position }, set: { scrubbing = $0 }),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing, let target = scrubbing {
                            seek(to: target)
                            scrubbing = nil
                        }
                    }
                )
                .tint(.white)
            }
            HStack(spacing: 18) {
                if current.isLive {
                    LivePill()
                } else {
                    Text(timeText).monospacedDigit()
                }
                Spacer()
                if !current.isLive {
                    Text(remainingText).monospacedDigit()
                }
                AirPlayButton()
                    .frame(width: 30, height: 30)
                Button { toggleFill() } label: {
                    Image(systemName: fill ? "arrow.down.right.and.arrow.up.left.rectangle" : "arrow.up.left.and.arrow.down.right.rectangle")
                }
                .accessibilityLabel(fill ? "Afficher toute l'image" : "Remplir l'écran")
                Button { rotate() } label: {
                    Image(systemName: isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isLandscape ? "Quitter le plein écran" : "Plein écran")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 30)
    }

    private func togglePause() {
        if usingVLC { vlc.togglePause() } else { native.togglePause() }
    }

    private func jump(_ seconds: Int32) {
        if usingVLC { vlc.jump(seconds) } else { native.jump(Double(seconds)) }
    }

    private func seek(to value: Double) {
        if usingVLC { vlc.seek(to: value) } else { native.seek(to: value) }
    }

    private func toggleFill() {
        withAnimation(.easeInOut(duration: 0.25)) { fill.toggle() }
        let size = UIScreen.main.bounds.size
        vlc.setFill(fill, screen: CGSize(width: max(size.width, size.height), height: min(size.width, size.height)))
    }

    /// Plein écran = paysage (et retour en portrait).
    private func rotate() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        let target: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscapeRight
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // MARK: Interface

    /// Barre du haut : sur une ligne en paysage, sur deux lignes en portrait (titre puis boutons).
    private var topBar: some View {
        let portrait = verticalSizeClass != .compact
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Fermer")

                if let artwork = current.artworkURL {
                    LogoArtwork(url: artwork, name: current.title)
                        .frame(width: 52, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if current.isLive { LiveBadge().fixedSize() }
                        Text(current.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 6) {
                        if let subtitle = current.subtitle {
                            Text(subtitle).lineLimit(1)
                        }
                        Text(usingVLC ? "VLC" : "iOS")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                if portrait {
                    recordButton
                } else {
                    actionButtons
                }
            }

            if portrait && (hasNextEpisode || canZap) {
                HStack(spacing: 12) {
                    Spacer()
                    actionButtons
                    Spacer()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var recordButton: some View {
        if recorder.isRecording, let started = recorder.startedAt {
            Button(action: toggleRecording) {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Text(timerInterval: started...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                }
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color(hex: 0xFF3B30), in: Capsule())
                .fixedSize()
            }
            .accessibilityLabel("Arrêter l'enregistrement")
        } else if canRecord {
            Button(action: toggleRecording) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 20, height: 20)
                    Circle().fill(Color(hex: 0xFF3B30)).frame(width: 10, height: 10)
                }
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.14), in: Circle())
            }
            .accessibilityLabel("Enregistrer le flux")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if verticalSizeClass == .compact { recordButton }
        if hasNextEpisode {
            zapButton("forward.end.fill", label: "Épisode suivant") { playNextEpisode() }
        }
        if canZap {
            zapButton("list.bullet", label: "Liste des chaînes") { showChannelList = true }
        }
    }

    private func zapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.14), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Impossible de lire ce flux")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Réessayer") { start() }
                    .buttonStyle(.borderedProminent)
                if canZap {
                    Button("Chaîne suivante") { zap(1) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.white)
        .padding()
    }
}

// MARK: - Lecteur iOS

/// Lecteur système (contrôles natifs, AirPlay, Picture in Picture).
private struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var fill = false

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        // Commandes d'iOS masquées : iTv affiche les siennes (pas de plein écran système qui bloque).
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

/// Bouton AirPlay du système.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

@MainActor
@Observable
final class NativePlayerModel {
    let player = AVPlayer()
    var error: String?
    var ended = false
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var position: Double = 0
    private(set) var timeText = "0:00"
    private(set) var remainingText = ""
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?

    var currentMs: Int {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? Int(seconds * 1000) : 0
    }

    var durationMs: Int {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite else { return 0 }
        return Int(seconds * 1000)
    }

    func play(_ url: URL, startMs: Int = 0) {
        error = nil
        ended = false
        isBuffering = true
        position = 0
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay, startMs > 0 {
                Task { @MainActor in
                    _ = await self?.player.seek(to: CMTime(value: CMTimeValue(startMs), timescale: 1000))
                }
                return
            }
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Format non pris en charge."
            Task { @MainActor in self?.error = message }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ended = true }
        }
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func togglePause() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        refresh()
    }

    func jump(_ seconds: Double) {
        let target = player.currentTime().seconds + seconds
        guard target.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600))
    }

    func seek(to value: Double) {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else { return }
        player.seek(to: CMTime(seconds: duration * min(max(value, 0), 1), preferredTimescale: 600))
    }

    private func refresh() {
        isPlaying = player.timeControlStatus != .paused
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate && error == nil
        let now = currentMs
        let total = durationMs
        position = total > 0 ? Double(now) / Double(total) : 0
        timeText = Self.format(now)
        remainingText = total > 0 ? "-" + Self.format(max(0, total - now)) : ""
    }

    private static func format(_ milliseconds: Int) -> String {
        let total = milliseconds / 1000
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }

    func stop() {
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
    }
}

// MARK: - Liste de zapping

private struct ZapList: View {
    let queue: [Playable]
    @Binding var current: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(queue.enumerated()), id: \.offset) { position, channel in
                        Button {
                            current = position
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(position + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 36, alignment: .leading)
                                LogoArtwork(url: channel.artworkURL, name: channel.title, logoPadding: 3, initialsSize: 11)
                                    .frame(width: 48, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                Text(channel.title)
                                    .lineLimit(1)
                                Spacer()
                                if position == current {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(position)
                    }
                }
                .listStyle(.plain)
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            .navigationTitle("Chaînes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
