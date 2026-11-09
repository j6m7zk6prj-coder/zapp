import AVFoundation
import Foundation

#if canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// Convertit un enregistrement .ts en .mp4 sans réencodage (même qualité),
/// pour qu'il s'ouvre dans Fichiers, Photos et partout ailleurs.
@MainActor
enum Remuxer {
    /// Renvoie le fichier .mp4 (le .ts est supprimé) ou nil si la conversion échoue (le .ts est gardé).
    static func convertToMP4(_ input: URL) async -> URL? {
        let output = input.deletingPathExtension().appendingPathExtension("mp4")
        guard input.pathExtension.lowercased() != "mp4" else { return input }
        try? FileManager.default.removeItem(at: output)

        #if canImport(MobileVLCKit)
        let player = VLCMediaPlayer()
        let media = VLCMedia(url: input)
        let destination = output.path.replacingOccurrences(of: "'", with: "\\\\'")
        media.addOption(":sout=#std{access=file,mux=mp4,dst='\(destination)'}")
        media.addOption(":sout-keep")
        media.addOption(":no-sout-all")
        player.media = media
        player.play()

        // Conversion plus rapide que le temps réel ; on attend la fin (au plus 30 min).
        let deadline = Date().addingTimeInterval(1800)
        var started = false
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(400))
            let state = player.state
            if state == .playing || state == .buffering || state == .opening { started = true }
            if state == .ended || state == .error { break }
            if started && state == .stopped { break }
        }
        player.stop()
        try? await Task.sleep(for: .milliseconds(500))
        #endif

        let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, (try? await AVURLAsset(url: output).load(.isPlayable)) == true else {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        try? FileManager.default.removeItem(at: input)
        return output
    }
}
