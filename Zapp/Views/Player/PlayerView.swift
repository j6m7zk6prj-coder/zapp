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

    init(request: PlaybackRequest) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    private var current: Playable { request.queue[index] }
    private var canZap: Bool { current.isLive && request.queue.count > 1 }
    private var hasNextEpisode: Bool { !current.isLive && index < request.queue.count - 1 }
    private var ended: Bool { usingVLC ? vlc.ended : native.ended }
    private var activeError: String? { usingVLC ? vlc.error : native.error }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if usingVLC {
                    VLCSurface(model: vlc)
                        .overlay { VLCControls(model: vlc, isLive: current.isLive) }
                } else {
                    SystemPlayer(player: native.player)
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
                            .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { self.recordingNotice = nil }
                    }
                }
            }
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
            zapButton("chevron.up", label: "Chaîne précédente") { zap(-1) }
            zapButton("list.bullet", label: "Liste des chaînes") { showChannelList = true }
            zapButton("chevron.down", label: "Chaîne suivante") { zap(1) }
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

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

@MainActor
@Observable
final class NativePlayerModel {
    let player = AVPlayer()
    var error: String?
    var ended = false
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

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
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay, startMs > 0 {
                Task { @MainActor in
                    await self?.player.seek(to: CMTime(value: CMTimeValue(startMs), timescale: 1000))
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
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - Contrôles VLC

/// Contrôles affichés par-dessus VLC (qui n'a pas de contrôles natifs).
private struct VLCControls: View {
    let model: VLCPlayerModel
    let isLive: Bool
    @State private var visible = true
    @State private var scrubbing: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.35 : 0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { visible.toggle() }
                }

            if model.isBuffering && model.error == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if visible {
                HStack(spacing: 46) {
                    if !isLive {
                        Button { model.jump(-10) } label: { Image(systemName: "gobackward.10") }
                    }
                    Button {
                        model.togglePause()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 38))
                    }
                    if !isLive {
                        Button { model.jump(10) } label: { Image(systemName: "goforward.10") }
                    }
                }
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(model.isBuffering ? 0 : 1)

                if !isLive && model.durationMs > 0 {
                    VStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(get: { scrubbing ?? model.position }, set: { scrubbing = $0 }),
                                in: 0...1,
                                onEditingChanged: { editing in
                                    if !editing, let target = scrubbing {
                                        model.seek(to: target)
                                        scrubbing = nil
                                    }
                                }
                            )
                            .tint(.white)
                            HStack {
                                Text(model.timeText)
                                Spacer()
                                Text(model.remainingText)
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding()
                    }
                }
            }
        }
        .task(id: visible) {
            guard visible else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, model.isPlaying, scrubbing == nil else { return }
            withAnimation(.easeInOut(duration: 0.3)) { visible = false }
        }
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
