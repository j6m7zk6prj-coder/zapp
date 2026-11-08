import SwiftUI
import UIKit

#if canImport(MobileVLCKit)
import MobileVLCKit

/// Moteur VLC : lit TS, MKV, AVI, FLV, RTMP, RTSP, UDP, MMS…
@MainActor
@Observable
final class VLCPlayerModel {
    @ObservationIgnored let player = VLCMediaPlayer()
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var error: String?
    private(set) var position: Double = 0
    private(set) var durationMs: Int32 = 0
    private(set) var timeText = "0:00"
    private(set) var remainingText = ""
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt = Date()

    func attach(_ view: UIView) {
        player.drawable = view
    }

    func play(_ url: URL) {
        error = nil
        isBuffering = true
        position = 0
        durationMs = 0
        startedAt = Date()
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
        player.media = media
        player.play()
        startPolling()
    }

    func togglePause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        refresh()
    }

    func seek(to value: Double) {
        player.position = Float(min(max(value, 0), 1))
    }

    func jump(_ seconds: Int32) {
        if seconds >= 0 {
            player.jumpForward(seconds)
        } else {
            player.jumpBackward(-seconds)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if player.media != nil { player.stop() }
        isPlaying = false
        isBuffering = false
    }

    private func startPolling() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func refresh() {
        let state = player.state
        isPlaying = player.isPlaying
        switch state {
        case .error:
            error = "VLC n'a pas pu ouvrir ce flux. Vérifie le lien ou ta connexion."
            isBuffering = false
        case .opening, .buffering:
            isBuffering = !player.isPlaying
            if isBuffering, Date().timeIntervalSince(startedAt) > 30, Self.milliseconds(player.time) == 0 {
                error = "Le flux ne répond pas (délai dépassé)."
                isBuffering = false
            }
        default:
            isBuffering = false
        }

        durationMs = Self.milliseconds(player.media?.length)
        position = Double(player.position)
        let now = Self.milliseconds(player.time)
        timeText = Self.format(now)
        remainingText = durationMs > 0 ? "-" + Self.format(max(0, durationMs - now)) : ""
    }

    private static func milliseconds(_ time: VLCTime?) -> Int32 {
        time?.intValue ?? 0
    }

    private static func format(_ milliseconds: Int32) -> String {
        let total = Int(milliseconds) / 1000
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Surface vidéo sur laquelle VLC dessine.
struct VLCSurface: UIViewRepresentable {
    let model: VLCPlayerModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        model.attach(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#else

/// Version de repli quand MobileVLCKit n'est pas installé (pod install pas lancé).
@MainActor
@Observable
final class VLCPlayerModel {
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var error: String?
    private(set) var position: Double = 0
    private(set) var durationMs: Int32 = 0
    private(set) var timeText = ""
    private(set) var remainingText = ""

    func play(_ url: URL) {
        error = "Le moteur VLC n'est pas intégré à cette version de l'app (lance « pod install »)."
    }

    func togglePause() {}
    func seek(to value: Double) {}
    func jump(_ seconds: Int32) {}
    func stop() {}
}

struct VLCSurface: View {
    let model: VLCPlayerModel
    var body: some View { Color.black }
}

#endif
