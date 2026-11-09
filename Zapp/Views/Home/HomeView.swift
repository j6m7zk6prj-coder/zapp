import SwiftUI
import UIKit

/// Accueil : grande affiche à la une, reprise de lecture, matchs, tendances, chaînes.
struct HomeView: View {
    @Binding var selection: AppTab
    @Environment(Library.self) private var library
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlaylistStore.self) private var playlists
    @Environment(ProfileStore.self) private var profiles
    @Environment(MetadataStore.self) private var metadata
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @State private var upcoming: [Match]?
    @State private var results: [Match] = []
    @State private var scrolled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    let hero = heroEntries
                    if hero.isEmpty {
                        Color.clear.frame(height: 110)
                    } else {
                        HeroCarousel(entries: hero)
                    }

                    status

                    let resume = profiles.continueWatching
                    if !resume.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Reprendre la lecture")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(resume) { entry in
                                        ContinueCard(entry: entry)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                        }
                    }

                    footSection

                    if !metadata.trending.isEmpty {
                        Shelf(title: "Tendances dans ta playlist", items: metadata.trending.prefix(20).map { $0.item }, style: .poster)
                    }

                    let recent = profiles.recentChannelIDs.compactMap { library.item($0) }
                    if !recent.isEmpty {
                        Shelf(title: "Regardées récemment", items: recent, style: .landscape)
                    }

                    let favoriteItems = library.lookup(favorites.ids)
                    if !favoriteItems.isEmpty {
                        Shelf(title: "Ma liste", items: Array(favoriteItems.prefix(30)), route: .favorites)
                    }

                    if !results.isEmpty && !settings.hideScores {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Derniers résultats") {
                                Button("Tout le foot") { selection = .foot }
                                    .font(.subheadline.weight(.semibold))
                            }
                            MatchShelf(matches: results)
                        }
                    }

                    if !library.customLinkItems.isEmpty {
                        Shelf(title: "Mes liens", items: Array(library.customLinkItems.prefix(30)), route: .customLinks)
                    }

                    let movies = library.recentlyAdded(.movie)
                    if !movies.isEmpty {
                        Shelf(title: "Films récemment ajoutés", items: movies, style: .poster, route: .kind(.movie))
                    }

                    let series = library.recentlyAdded(.series)
                    if !series.isEmpty {
                        Shelf(title: "Séries récemment ajoutées", items: series, style: .poster, route: .kind(.series))
                    }

                    let channels = Array(library.all(.live).prefix(24))
                    if !channels.isEmpty {
                        Shelf(title: "En direct", items: channels, style: .landscape, route: .kind(.live))
                    }

                    if library.items.isEmpty && !library.isLoading {
                        emptyState
                    }
                }
                .padding(.bottom, 20)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("home")).minY)
                })
            }
            .coordinateSpace(name: "home")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                let value = offset < -260
                if value != scrolled { withAnimation(.easeInOut(duration: 0.2)) { scrolled = value } }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(AmbientBackground())
            .overlay(alignment: .top) { topBar }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await reload() }
            .tabBarSpacing()
            .mediaDestinations()
            .task(id: library.items.count) {
                await metadata.loadTrending(library: library)
            }
            .task(id: footKey) {
                await loadFoot()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(max(30, settings.footRefreshSeconds)))
                    guard upcoming?.contains(where: { $0.state == .live || ($0.state == .scheduled && $0.date <= Date()) }) == true else { continue }
                    await EspnClient.shared.invalidate()
                    await loadFoot()
                }
            }
        }
    }

    // MARK: En-tête

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("iTv")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Menu {
                Button { router.sheet = .addLink } label: { Label("Ajouter un lien", systemImage: "link.badge.plus") }
                Button { router.sheet = .addPlaylist } label: { Label("Ajouter une playlist", systemImage: "list.bullet.rectangle") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            }
            .accessibilityLabel("Ajouter")

            Button { router.sheet = .settings } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(GlassCircleStyle(size: 38))
                .accessibilityLabel("Réglages")

            Button { router.sheet = .profiles } label: {
                ProfileAvatar(profile: profiles.active, size: 38)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Profil : \(profiles.active.name)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background {
            if scrolled {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    // MARK: À la une

    private var heroEntries: [HeroEntry] {
        let trends = metadata.trending.filter { $0.trend.poster != nil || $0.trend.backdrop != nil }.prefix(6)
        if !trends.isEmpty {
            return trends.map { HeroEntry(item: $0.item, trend: $0.trend) }
        }
        let movies = library.recentlyAdded(.movie, limit: 30).filter { $0.logoURL != nil }
        let series = library.recentlyAdded(.series, limit: 30).filter { $0.logoURL != nil }
        let artwork = Array(movies.prefix(3)) + Array(series.prefix(3))
        if !artwork.isEmpty { return artwork.map { HeroEntry(item: $0, trend: nil) } }
        let favoriteItems = library.lookup(favorites.ids).filter { $0.kind != .live }
        return favoriteItems.prefix(5).map { HeroEntry(item: $0, trend: nil) }
    }

    // MARK: Foot

    private var footKey: String {
        profiles.footSlugs.joined(separator: ",") + "|" + profiles.current.teams.map(\.id).joined(separator: ",") + "|\(profiles.activeID)"
    }

    @ViewBuilder
    private var footSection: some View {
        if let upcoming, !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Pour toi ce soir", subtitle: "Matchs de tes compétitions et où les regarder") {
                    Button("Tout le foot") { selection = .foot }
                        .font(.subheadline.weight(.semibold))
                }
                MatchShelf(matches: upcoming)
            }
        }
    }

    private func loadFoot() async {
        let slugs = profiles.footSlugs
        let teams = Set(profiles.current.teams.map(\.id))
        let leagues = profiles.current.leagues
        guard !slugs.isEmpty else {
            upcoming = []
            results = []
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var all: [Match] = []
        for offset in [-1, 0, 1] {
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            all += await EspnClient.shared.day(slugs, day)
        }
        var seen = Set<String>()
        all = all.filter { seen.insert($0.id).inserted }
        func priority(_ match: Match) -> Int { teams.contains(match.home.id) || teams.contains(match.away.id) ? 0 : 1 }
        func leagueRank(_ match: Match) -> Int { leagues.firstIndex(of: match.leagueSlug) ?? 99 }
        upcoming = Array(all
            .filter { ($0.state == .live || $0.state == .scheduled) && $0.date >= today }
            .sorted {
                let a = ($0.state == .live ? 0 : 1, priority($0), $0.date, leagueRank($0))
                let b = ($1.state == .live ? 0 : 1, priority($1), $1.date, leagueRank($1))
                return a < b
            }
            .prefix(20))
        results = Array(all
            .filter { $0.state == .finished }
            .sorted { priority($0) != priority($1) ? priority($0) < priority($1) : $0.date > $1.date }
            .prefix(16))
    }

    // MARK: États

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
                Button("Ajouter un lien") { router.sheet = .addLink }
                    .buttonStyle(WhiteCapsuleStyle())
                Button("Une playlist") { router.sheet = .addPlaylist }
                    .buttonStyle(GlassCapsuleStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal)
    }

    private func reload() async {
        await EspnClient.shared.invalidate()
        await loadFoot()
        guard let active = playlists.active else { return }
        await library.load(active, force: true)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - À la une

struct HeroEntry: Identifiable, Hashable {
    let item: MediaItem
    let trend: TmdbTrend?
    var id: String { item.id }
}

/// Grande affiche plein écran qui défile toute seule, avec points de pagination.
struct HeroCarousel: View {
    let entries: [HeroEntry]
    @State private var index = 0
    @State private var interacting = false

    var body: some View {
        let height = min(UIScreen.main.bounds.height * 0.68, 620)
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { position, entry in
                    HeroCard(entry: entry)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)

            HStack(spacing: 6) {
                ForEach(entries.indices, id: \.self) { position in
                    Capsule()
                        .fill(.white.opacity(position == index ? 1 : 0.35))
                        .frame(width: position == index ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.35), value: index)
            .padding(.bottom, 4)
            .opacity(entries.count > 1 ? 1 : 0)
        }
        .frame(height: height + 10)
        .task(id: entries.map(\.id)) {
            index = min(index, max(0, entries.count - 1))
            while !Task.isCancelled && entries.count > 1 {
                try? await Task.sleep(for: .seconds(7))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) { index = (index + 1) % entries.count }
            }
        }
    }
}

struct HeroCard: View {
    let entry: HeroEntry
    @Environment(FavoritesStore.self) private var favorites
    @Environment(MetadataStore.self) private var metadata
    @Environment(Router.self) private var router

    private var item: MediaItem { entry.item }
    private var info: TmdbInfo? { metadata.info(for: item) }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                RemoteImage(url: entry.trend?.poster ?? info?.poster ?? item.logoURL ?? entry.trend?.backdrop) {
                    Theme.gradient(for: item.name)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: Theme.background.opacity(0.75), location: 0.72),
                    .init(color: Theme.background, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 12) {
                if let logo = info?.logo {
                    RemoteImage(url: logo, contentMode: .fit) {
                        title
                    }
                    .frame(maxWidth: 260, maxHeight: 96)
                } else {
                    title
                }

                Text(meta)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    if item.opensDetail {
                        NavigationLink(value: item) {
                            Label("Épisodes", systemImage: "play.fill")
                        }
                        .buttonStyle(WhiteCapsuleStyle())
                    } else {
                        Button {
                            router.play(item, context: [item])
                        } label: {
                            Label("Regarder", systemImage: "play.fill")
                        }
                        .buttonStyle(WhiteCapsuleStyle())
                    }

                    Button {
                        favorites.toggle(item)
                    } label: {
                        Image(systemName: favorites.contains(item) ? "checkmark" : "plus")
                    }
                    .buttonStyle(GlassCircleStyle())
                    .accessibilityLabel("Ma liste")

                    NavigationLink(value: item) {
                        Image(systemName: "info")
                    }
                    .buttonStyle(GlassCircleStyle())
                    .accessibilityLabel("Fiche")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .contentShape(Rectangle())
        .task { await metadata.load(item) }
    }

    private var title: some View {
        Text(entry.trend?.title ?? info?.title ?? item.displayName)
            .font(.system(size: 34, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.4), radius: 10)
    }

    private var meta: String {
        var parts: [String] = []
        if entry.trend != nil { parts.append("Tendance") } else { parts.append(item.kind == .series ? "Série" : "Film") }
        if let year = entry.trend?.year ?? info?.year { parts.append(String(year)) }
        if let genre = info?.genres.first { parts.append(genre) }
        if let rating = entry.trend?.rating ?? info?.rating ?? item.rating, rating > 0 {
            parts.append("★ " + String(format: "%.1f", rating))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Reprendre la lecture

struct ContinueCard: View {
    let entry: HistoryEntry
    @Environment(Router.self) private var router
    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        Button {
            router.play(queue: [entry.playable], index: 0)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: entry.artwork) { Theme.gradient(for: entry.title) }
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "play.fill").font(.caption)
                                Spacer()
                                Text("Encore \(entry.remainingText)")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                            }
                            ProgressLine(value: entry.progress)
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 250)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(role: .destructive) {
                withAnimation { profiles.removeHistory(entry.id) }
            } label: {
                Label("Retirer de « Reprendre »", systemImage: "xmark.circle")
            }
        }
    }
}
