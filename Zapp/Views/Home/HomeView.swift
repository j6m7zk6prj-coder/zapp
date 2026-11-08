import SwiftUI

struct HomeView: View {
    @Binding var selection: AppTab
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlaylistStore.self) private var playlists
    @State private var showPlaylists = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    shortcuts
                    status

                    let favoriteItems = library.lookup(favorites.ids)
                    if !favoriteItems.isEmpty {
                        ShelfRow(title: "Mes favoris", items: favoriteItems)
                    }

                    let channels = Array(library.all(.live).prefix(24))
                    if !channels.isEmpty {
                        ShelfRow(title: "Chaînes", items: channels)
                    }

                    let movies = library.recentlyAdded(.movie)
                    if !movies.isEmpty {
                        ShelfRow(title: "Films récemment ajoutés", items: movies)
                    }

                    let series = library.recentlyAdded(.series)
                    if !series.isEmpty {
                        ShelfRow(title: "Séries récemment ajoutées", items: series)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { brand }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPlaylists = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Playlists")
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: MediaItem.self) { SeriesDetailView(series: $0) }
            .sheet(isPresented: $showPlaylists) { PlaylistsView() }
        }
    }

    private var brand: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("ZAPP")
                .font(.headline.weight(.heavy))
                .tracking(2)
            Text("TV")
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EN DIRECT")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
            Text("Live TV")
                .font(.largeTitle.weight(.heavy))
            HStack(spacing: 14) {
                Text("\(library.count(.live).formatted()) chaînes")
                Text("\(library.groups(of: .live).count.formatted()) catégories")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
            Text("Toutes tes chaînes en direct, avec un zapping instantané.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            if let active = playlists.active {
                Label(active.name, systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            CategoryCard(
                title: "Live TV",
                subtitle: "\(library.count(.live).formatted()) chaînes",
                systemImage: "tv",
                gradient: Theme.liveGradient
            ) { selection = .live }
            CategoryCard(
                title: "Films",
                subtitle: "\(library.count(.movie).formatted()) films",
                systemImage: "film",
                gradient: Theme.moviesGradient
            ) { selection = .movies }
            CategoryCard(
                title: "Séries",
                subtitle: "\(library.count(.series).formatted()) séries",
                systemImage: "rectangle.stack",
                gradient: Theme.seriesGradient
            ) { selection = .series }
            CategoryCard(
                title: "Recherche",
                subtitle: "Chaînes, films, séries",
                systemImage: "magnifyingglass",
                gradient: Theme.searchGradient
            ) { selection = .search }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var status: some View {
        if library.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text(library.items.isEmpty ? "Chargement de la playlist…" : "Mise à jour…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        if let message = library.errorMessage {
            ErrorBanner(message: message) {
                Task { await reload() }
            }
            .padding(.horizontal)
        }
    }

    private func reload() async {
        guard let active = playlists.active else { return }
        await library.load(active, force: true)
    }
}
