import AVKit
import SwiftUI

/// Lecteur plein écran. HLS/MP4 via le lecteur iOS, tout le reste via VLC,
/// avec zapping (précédente / suivante / liste) pour le direct.
struct PlayerView: View {
    let request: PlaybackRequest
    @Environment(\.dismiss) private var dismiss
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
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { start() }
        .onChange(of: index) { start() }
        .onChange(of: native.error) { fallBackToVLCIfPossible() }
        .onDisappear {
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
        if PlaybackSupport.usesVLC(url, preference: AppSettings.shared.engine) {
            native.stop()
            usingVLC = true
            vlc.play(url)
        } else {
            vlc.stop()
            usingVLC = false
            native.play(url)
        }
    }

    /// Le lecteur iOS n'a pas pu lire le flux : VLC prend le relais.
    private func fallBackToVLCIfPossible() {
        guard native.error != nil, !usingVLC,
              AppSettings.shared.engine == .auto,
              PlaybackSupport.vlcAvailable else { return }
        native.stop()
        usingVLC = true
        vlc.play(current.url)
    }

    private func zap(_ delta: Int) {
        let count = request.queue.count
        index = (index + delta % count + count) % count
    }

    // MARK: Interface

    private var topBar: some View {
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if current.isLive { LiveBadge() }
                    Text(current.title)
                        .font(.headline)
                        .lineLimit(1)
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
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            if canZap {
                zapButton("chevron.up", label: "Chaîne précédente") { zap(-1) }
                zapButton("list.bullet", label: "Liste des chaînes") { showChannelList = true }
                zapButton("chevron.down", label: "Chaîne suivante") { zap(1) }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
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
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    func play(_ url: URL) {
        error = nil
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Format non pris en charge."
            Task { @MainActor in self?.error = message }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        statusObservation = nil
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
