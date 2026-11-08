import AVKit
import SwiftUI

/// Lecteur plein écran, avec zapping (chaîne précédente / suivante / liste) pour le direct.
struct PlayerView: View {
    let request: PlaybackRequest
    @Environment(\.dismiss) private var dismiss
    @State private var model = PlayerModel()
    @State private var index: Int
    @State private var showChannelList = false

    init(request: PlaybackRequest) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    private var current: Playable { request.queue[index] }
    private var canZap: Bool { current.isLive && request.queue.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                SystemPlayer(player: model.player)
                if let error = model.error {
                    errorOverlay(error)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { model.play(current.url) }
        .onChange(of: index) { model.play(current.url) }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showChannelList) {
            ZapList(queue: request.queue, current: $index)
                .presentationDetents([.medium, .large])
        }
        .persistentSystemOverlays(.hidden)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Fermer")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if current.isLive { LiveBadge() }
                    Text(current.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let subtitle = current.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
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
                .background(.white.opacity(0.12), in: Circle())
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
                Button("Réessayer") { model.play(current.url) }
                    .buttonStyle(.borderedProminent)
                if canZap {
                    Button("Chaîne suivante") { zap(1) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(.white)
    }

    private func zap(_ delta: Int) {
        let count = request.queue.count
        index = (index + delta % count + count) % count
    }
}

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
final class PlayerModel {
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
                            HStack {
                                Text("\(position + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 40, alignment: .leading)
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
