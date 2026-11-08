import SwiftUI

enum AppTab: Hashable {
    case home, live, movies, series, search
}

struct RootView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(Library.self) private var library
    @Environment(PlayerPresenter.self) private var presenter
    @State private var selection: AppTab = .home

    var body: some View {
        @Bindable var presenter = presenter

        Group {
            if playlists.playlists.isEmpty {
                OnboardingView()
            } else {
                TabView(selection: $selection) {
                    HomeView(selection: $selection)
                        .tabItem { Label("Accueil", systemImage: "house.fill") }
                        .tag(AppTab.home)
                    LiveTVView()
                        .tabItem { Label("Live TV", systemImage: "tv") }
                        .tag(AppTab.live)
                    CatalogView(kind: .movie)
                        .tabItem { Label("Films", systemImage: "film") }
                        .tag(AppTab.movies)
                    CatalogView(kind: .series)
                        .tabItem { Label("Séries", systemImage: "rectangle.stack") }
                        .tag(AppTab.series)
                    SearchView()
                        .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                        .tag(AppTab.search)
                }
            }
        }
        .task(id: playlists.active?.id) {
            if let active = playlists.active {
                await library.load(active)
            } else {
                library.reset()
            }
        }
        .fullScreenCover(item: $presenter.request) { request in
            PlayerView(request: request)
        }
    }
}
