import SwiftUI

enum AppTab: Hashable {
    case home, live, movies, series, search
}

struct RootView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(Library.self) private var library
    @Environment(CustomizationStore.self) private var customization
    @Environment(Router.self) private var router
    @State private var selection: AppTab = .home

    var body: some View {
        @Bindable var router = router

        Group {
            if playlists.playlists.isEmpty && customization.links.isEmpty {
                OnboardingView()
            } else {
                TabView(selection: $selection) {
                    HomeView(selection: $selection)
                        .tabItem { Label("Accueil", systemImage: "play.house.fill") }
                        .tag(AppTab.home)
                    LiveTVView()
                        .tabItem { Label("En direct", systemImage: "dot.radiowaves.left.and.right") }
                        .tag(AppTab.live)
                    CatalogView(kind: .movie)
                        .tabItem { Label("Films", systemImage: "film") }
                        .tag(AppTab.movies)
                    CatalogView(kind: .series)
                        .tabItem { Label("Séries", systemImage: "tv") }
                        .tag(AppTab.series)
                    SearchView()
                        .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                        .tag(AppTab.search)
                }
            }
        }
        .onChange(of: customization.revision, initial: true) {
            library.setCustomization(links: customization.linkItems, overrides: customization.overrides)
        }
        .task(id: playlists.active?.id) {
            if let active = playlists.active {
                await library.load(active)
            } else {
                library.resetPlaylist()
            }
        }
        .fullScreenCover(item: $router.playback) { request in
            PlayerView(request: request)
        }
        .sheet(item: $router.editing) { item in
            ItemEditorView(item: item)
        }
    }
}

extension View {
    /// Destinations de navigation communes à tous les onglets.
    func mediaDestinations() -> some View {
        navigationDestination(for: MediaItem.self) { item in
            if item.opensDetail {
                SeriesDetailView(series: item)
            } else {
                ItemDetailView(item: item)
            }
        }
        .navigationDestination(for: BrowseRoute.self) { route in
            BrowseGridView(route: route)
        }
    }
}
