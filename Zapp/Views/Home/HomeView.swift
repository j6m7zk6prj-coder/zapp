import SwiftUI

struct HomeView: View {
    @Binding var selection: AppTab
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlaylistStore.self) private var playlists
    @State private var sheet: HomeSheet?

    enum HomeSheet: String, Identifiable {
        case settings, addLink, addPlaylist
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    let featured = featuredItems
                    if !featured.isEmpty {
                        HeroCarousel(items: featured)
                    }

                    status
                    quickAccess

                    let favoriteItems = library.lookup(favorites.ids)
                    if !favoriteItems.isEmpty {
                        Shelf(title: "Mes favoris", items: Array(favoriteItems.prefix(30)), route: .favorites)
                    }

                    if !library.customLinkItems.isEmpty {
                        Shelf(title: "Mes liens", items: Array(library.customLinkItems.prefix(30)), route: .customLinks)
                    }

                    let channels = Array(library.all(.live).prefix(24))
                    if !channels.isEmpty {
                        Shelf(title: "En direct", items: channels, style: .landscape, route: .kind(.live))
                    }

                    let liveGroups = library.groups(of: .live)
                    if liveGroups.count > 1 {
                        CategoryLinks(title: "Catégories", kind: .live, groups: Array(liveGroups.prefix(24)))
                    }

                    let movies = library.recentlyAdded(.movie)
                    if !movies.isEmpty {
                        Shelf(title: "Films récemment ajoutés", items: movies, style: .poster, route: .kind(.movie))
                    }

                    let series = library.recentlyAdded(.series)
                    if !series.isEmpty {
                        Shelf(title: "Séries récemment ajoutées", items: series, style: .poster, route: .kind(.series))
                    }

                    if library.items.isEmpty && !library.isLoading {
                        emptyState
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Accueil")
            .refreshable { await reload() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sheet = .addLink
                        } label: {
                            Label("Ajouter un lien", systemImage: "link.badge.plus")
                        }
                        Button {
                            sheet = .addPlaylist
                        } label: {
                            Label("Ajouter une playlist", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Ajouter")

                    Button {
                        sheet = .settings
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .mediaDestinations()
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .settings: SettingsView()
                case .addLink: LinkEditorView(link: nil)
                case .addPlaylist: AddPlaylistView()
                }
            }
        }
    }

    /// Mise en avant : films/séries récents avec image, sinon favoris, sinon chaînes.
    private var featuredItems: [MediaItem] {
        let movies = library.recentlyAdded(.movie, limit: 30).filter { $0.logoURL != nil }
        let series = library.recentlyAdded(.series, limit: 30).filter { $0.logoURL != nil }
        let artwork = Array(movies.prefix(3)) + Array(series.prefix(3))
        if !artwork.isEmpty { return artwork }
        let favoriteItems = library.lookup(favorites.ids)
        if !favoriteItems.isEmpty { return Array(favoriteItems.prefix(6)) }
        return Array(library.all(.live).prefix(6))
    }

    private var quickAccess: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                QuickCard(title: "En direct", subtitle: "\(library.count(.live).formatted()) chaînes",
                          icon: "dot.radiowaves.left.and.right", gradient: Theme.liveGradient) { selection = .live }
                QuickCard(title: "Films", subtitle: "\(library.count(.movie).formatted()) films",
                          icon: "film", gradient: Theme.moviesGradient) { selection = .movies }
                QuickCard(title: "Séries", subtitle: "\(library.count(.series).formatted()) séries",
                          icon: "tv", gradient: Theme.seriesGradient) { selection = .series }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var status: some View {
        if library.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text(library.items.isEmpty ? "Chargement de la playlist…" : "Mise à jour de la playlist…")
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Rien à regarder pour l'instant")
                .font(.headline)
            Text("Ajoute un lien de flux ou une playlist pour commencer.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Ajouter un lien") { sheet = .addLink }
                    .buttonStyle(.borderedProminent)
                Button("Ajouter une playlist") { sheet = .addPlaylist }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal)
    }

    private func reload() async {
        guard let active = playlists.active else { return }
        await library.load(active, force: true)
    }
}

/// Grand carrousel en haut de l'accueil, qui défile tout seul.
struct HeroCarousel: View {
    let items: [MediaItem]
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                HeroCard(item: item)
                    .padding(.horizontal)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 270)
        .task(id: items.count) {
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.6)) {
                    page = (page + 1) % items.count
                }
            }
        }
    }
}

struct HeroCard: View {
    let item: MediaItem
    @Environment(FavoritesStore.self) private var favorites
    @Environment(Router.self) private var router

    private var kindLabel: String {
        switch item.kind {
        case .live: return "EN DIRECT"
        case .movie: return "FILM"
        case .series: return "SÉRIE"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay { backdrop }
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(kindLabel)
                        .font(.caption2.weight(.heavy))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text(item.displayName)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .lineLimit(2)
                    Text(item.group)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        mainAction
                        Button {
                            favorites.toggle(item)
                        } label: {
                            Image(systemName: favorites.contains(item) ? "checkmark" : "plus")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                if item.kind != .live {
                    PosterArt(item: item)
                        .frame(width: 86)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                }
            }
            .padding(16)
            .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu { ItemMenu(item: item) }
    }

    @ViewBuilder
    private var mainAction: some View {
        let label = HStack(spacing: 6) {
            Image(systemName: item.opensDetail ? "info.circle.fill" : "play.fill")
            Text(item.kind == .live ? "Regarder" : (item.opensDetail ? "Épisodes" : "Lire"))
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.white, in: Capsule())

        if item.opensDetail {
            NavigationLink(value: item) { label }
                .buttonStyle(CardButtonStyle())
        } else {
            Button {
                router.play(item, context: [item])
            } label: {
                label
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    private var backdrop: some View {
        AsyncImage(url: item.logoURL) { phase in
            if let image = phase.image {
                if item.kind == .live {
                    ZStack {
                        Theme.gradient(for: item.name)
                        image.resizable().scaledToFit().padding(50).opacity(0.9)
                    }
                } else {
                    image.resizable().scaledToFill()
                        .blur(radius: 18)
                        .overlay(Color.black.opacity(0.2))
                }
            } else {
                Theme.gradient(for: item.name)
            }
        }
    }
}

private struct QuickCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.heavy))
                    Text(subtitle).font(.caption2).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// Raccourcis vers les catégories (puces).
private struct CategoryLinks: View {
    let title: String
    let kind: MediaKind
    let groups: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(groups, id: \.self) { group in
                        NavigationLink(value: BrowseRoute.group(kind, group)) {
                            Text(group)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 46)
        }
    }
}
