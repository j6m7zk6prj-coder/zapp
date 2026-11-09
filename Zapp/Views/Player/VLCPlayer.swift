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
    private(set) var ended = false
    private(set) var currentMs: Int32 = 0
    /// Enregistrement en cours (copie du flux, sans réencodage).
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var recordingFolder: URL?
    @ObservationIgnored private var recordingTitle = ""
    @ObservationIgnored private var recordingPending = false

    func attach(_ view: UIView) {
        player.drawable = view
    }

    func play(_ url: URL, startMs: Int = 0) {
        if isRecording { stopRecording() }
        error = nil
        ended = false
        isBuffering = true
        position = 0
        durationMs = 0
        currentMs = 0
        startedAt = Date()
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
        if startMs > 0 { media.addOption(":start-time=\(startMs / 1000)") }
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

    /// Remplir l'écran (recadrage au format de l'écran) ou afficher toute l'image.
    func setFill(_ fill: Bool, screen: CGSize) {
        if fill, screen.width > 0, screen.height > 0 {
            player.videoCropGeometry = strdup("\(Int(screen.width)):\(Int(screen.height))")
        } else {
            player.videoCropGeometry = nil
        }
    }

    // MARK: Enregistrement

    /// Démarre l'enregistrement du flux en cours (ou dès que la lecture commence).
    func startRecording(title: String) {
        guard !isRecording else { return }
        let folder = Recordings.temporaryFolder()
        recordingFolder = folder
        recordingTitle = title
        isRecording = true
        recordingStartedAt = Date()
        if player.isPlaying {
            recordingPending = !player.startRecording(atPath: folder.path)
        } else {
            recordingPending = true
        }
    }

    /// Arrête l'enregistrement tout de suite, puis range le fichier dans « Enregistrements ».
    func stopRecording(completion: ((URL?) -> Void)? = nil) {
        guard isRecording, let folder = recordingFolder else { return }
        if !recordingPending { _ = player.stopRecording() }
        let title = recordingTitle
        isRecording = false
        recordingStartedAt = nil
        recordingPending = false
        recordingFolder = nil
        Task { @MainActor in
            // VLC finalise le fichier juste après l'arrêt.
            try? await Task.sleep(for: .milliseconds(900))
            let url = await Task.detached { Recordings.finalize(folder: folder, title: title) }.value
            completion?(url)
        }
    }

    func stop() {
        stopRecording()
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
        case .ended:
            ended = true
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
        if isRecording, recordingPending, player.isPlaying, let folder = recordingFolder {
            recordingPending = !player.startRecording(atPath: folder.path)
        }

        durationMs = Self.milliseconds(player.media?.length)
        position = Double(player.position)
        let now = Self.milliseconds(player.time)
        currentMs = now
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
    private(set) var ended = false
    private(set) var currentMs: Int32 = 0
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?

    func setFill(_ fill: Bool, screen: CGSize) {}
    func startRecording(title: String) {}
    func stopRecording(completion: ((URL?) -> Void)? = nil) { completion?(nil) }

    func play(_ url: URL, startMs: Int = 0) {
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
