import SwiftUI
import UIKit

enum AppTab: String, Hashable, CaseIterable {
    case home, live, movies, series, foot, search

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .live: return "Direct"
        case .movies: return "Films"
        case .series: return "Séries"
        case .foot: return "Foot"
        case .search: return "Recherche"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .movies: return "film.fill"
        case .series: return "rectangle.stack.fill"
        case .foot: return "soccerball"
        case .search: return "magnifyingglass"
        }
    }
}

/// Feuilles présentées depuis n'importe quel écran.
enum AppSheet: String, Identifiable {
    case settings, addLink, addPlaylist, profiles, follow
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(Library.self) private var library
    @Environment(CustomizationStore.self) private var customization
    @Environment(MetadataStore.self) private var metadata
    @Environment(Router.self) private var router
    @State private var selection: AppTab = .home
    @AppStorage("profiles.askOnLaunch") private var askProfileOnLaunch = false
    @State private var askedProfile = false

    var body: some View {
        @Bindable var router = router

        Group {
            if playlists.playlists.isEmpty && customization.links.isEmpty {
                OnboardingView()
            } else {
                TabView(selection: $selection) {
                    HomeView(selection: $selection).tag(AppTab.home).toolbar(.hidden, for: .tabBar)
                    LiveTVView().tag(AppTab.live).toolbar(.hidden, for: .tabBar)
                    CatalogView(kind: .movie).tag(AppTab.movies).toolbar(.hidden, for: .tabBar)
                    CatalogView(kind: .series).tag(AppTab.series).toolbar(.hidden, for: .tabBar)
                    FootView().tag(AppTab.foot).toolbar(.hidden, for: .tabBar)
                    SearchView().tag(AppTab.search).toolbar(.hidden, for: .tabBar)
                }
                .overlay(alignment: .bottom) {
                    FloatingTabBar(selection: $selection)
                }
                .ignoresSafeArea(.keyboard)
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
        .onAppear {
            if askProfileOnLaunch && !askedProfile {
                askedProfile = true
                router.sheet = .profiles
            }
        }
        .fullScreenCover(item: $router.playback) { request in
            PlayerView(request: request)
        }
        .sheet(item: $router.editing) { item in
            ItemEditorView(item: item)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .settings: SettingsView()
            case .addLink: LinkEditorView(link: nil)
            case .addPlaylist: AddPlaylistView()
            case .profiles: ProfilePickerView()
            case .follow: FootFollowView()
            }
        }
    }
}

/// Barre d'onglets flottante en verre, avec la recherche à part (comme sur iOS récent).
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var namespace

    private let tabs: [AppTab] = [.home, .live, .movies, .series, .foot]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    let selected = selection == tab
                    Button {
                        if selection != tab {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = tab }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(height: 20)
                            Text(tab.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(selected ? Theme.accent : Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = .search }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selection == .search ? Theme.accent : .white)
                    .frame(width: 58, height: 58)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.14)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Recherche")
        }
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
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
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .navigationDestination(for: TeamRoute.self) { route in
            TeamView(team: route.team, leagueSlug: route.league)
        }
        .navigationDestination(for: StandingsRoute.self) { route in
            StandingsView(slug: route.slug)
        }
    }
}
