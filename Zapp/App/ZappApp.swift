import AVFoundation
import SwiftUI

@main
struct ZappApp: App {
    @State private var playlists = PlaylistStore()
    @State private var library = Library()
    @State private var profiles: ProfileStore
    @State private var favorites: FavoritesStore
    @State private var customization = CustomizationStore()
    @State private var metadata = MetadataStore()
    @State private var router = Router()

    init() {
        let profiles = ProfileStore()
        _profiles = State(initialValue: profiles)
        _favorites = State(initialValue: FavoritesStore(profiles: profiles))
        // Cache plus large pour les logos et affiches.
        URLCache.shared = URLCache(memoryCapacity: 96 * 1024 * 1024, diskCapacity: 768 * 1024 * 1024)
        // Son même en mode silencieux + lecture en arrière-plan / Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(playlists)
                .environment(library)
                .environment(profiles)
                .environment(favorites)
                .environment(customization)
                .environment(metadata)
                .environment(router)
                .environment(AppSettings.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
