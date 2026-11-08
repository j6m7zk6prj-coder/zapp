import AVFoundation
import SwiftUI

@main
struct ZappApp: App {
    @State private var playlists = PlaylistStore()
    @State private var library = Library()
    @State private var favorites = FavoritesStore()
    @State private var presenter = PlayerPresenter()

    init() {
        // Cache plus large pour les logos et affiches.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
        // Son même en mode silencieux + lecture en arrière-plan / Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(playlists)
                .environment(library)
                .environment(favorites)
                .environment(presenter)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
