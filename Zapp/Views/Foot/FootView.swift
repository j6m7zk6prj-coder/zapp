import SwiftUI

/// Onglet Foot : matchs par jour, classements, équipes suivies.
struct FootView: View {
    enum FootSection: String, CaseIterable {
        case matches = "Matchs"
        case standings = "Classements"
        case teams = "Mes équipes"
    }

    enum Filter: Hashable {
        case all, myTeams, live
        case league(String)
    }

    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @State private var section: FootSection = .matches
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var filter: Filter = .all
    @State private var matches: [Match]?
    @State private var loadError: String?
    @State private var standingsSlug: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    switch section {
                    case .matches: matchesContent
                    case .standings: standingsContent
                    case .teams: FollowedTeamsGrid()
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AmbientBackground(tint: Color(hex: 0x30D158)))
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await EspnClient.shared.invalidate()
                await loadMatches()
            }
            .tabBarSpacing()
            .mediaDestinations()
            .task(id: "\(day.timeIntervalSince1970)|\(profiles.footSlugs.joined(separator: ","))|\(profiles.activeID)") {
                matches = nil
                await loadMatches()
                while !Task.isCancelled && Calendar.current.isDateInToday(day) {
                    try? await Task.sleep(for: .seconds(max(30, settings.footRefreshSeconds)))
                    guard !Task.isCancelled else { return }
                    await EspnClient.shared.invalidate()
                    await loadMatches()
                }
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Le foot, ") + Text("en direct.").accentSerif(size: 34))
                    .font(.system(size: 34, weight: .bold))
                Spacer()
                Button { router.sheet = .follow } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(GlassCircleStyle(size: 40))
                    .accessibilityLabel("Ligues et équipes suivies")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FootSection.allCases, id: \.self) { item in
                        Pill(title: item.rawValue, selected: section == item) {
                            withAnimation(.snappy) { section = item }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: Matchs

    @ViewBuilder
    private var matchesContent: some View {
        dayStrip
        filterStrip

        if profiles.footSlugs.isEmpty {
            emptyState(title: "Tu ne suis aucune compétition", detail: "Choisis tes ligues et tes équipes pour voir leurs matchs ici.", action: "Choisir mes ligues") {
                router.sheet = .follow
            }
        } else if let loadError, matches == nil {
            emptyState(title: "Matchs indisponibles", detail: loadError, action: "Réessayer") {
                Task { await loadMatches() }
            }
        } else if let matches {
            let shown = filtered(matches)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text("\(shown.count) match\(shown.count > 1 ? "s" : "")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)

            if shown.isEmpty {
                emptyState(title: filter == .live ? "Aucun match en direct" : "Aucun match ce jour-là",
                           detail: "Essaie un autre jour ou ajoute des compétitions.", action: nil, perform: nil)
            } else {
                let teamIDs = Set(profiles.current.teams.map(\.id))
                let mine = shown.filter { teamIDs.contains($0.home.id) || teamIDs.contains($0.away.id) }
                if !mine.isEmpty && filter != .myTeams {
                    group(title: "Mes équipes", logo: nil, slug: nil, matches: mine)
                }
                ForEach(groupedByLeague(shown)) { entry in
                    group(title: entry.name, logo: LeagueCatalog.logo(for: entry.slug), slug: entry.slug, matches: entry.matches)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        }
    }

    private var title: String {
        switch filter {
        case .all: return "Tous les matchs"
        case .myTeams: return "Mes équipes"
        case .live: return "En direct"
        case .league(let slug): return LeagueCatalog.name(of: slug)
        }
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(-3...7, id: \.self) { offset in
                        let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                        let selected = Calendar.current.isDate(date, inSameDayAs: day)
                        Button {
                            withAnimation(.snappy) { day = date }
                        } label: {
                            VStack(spacing: 3) {
                                Text(offset == 0 ? "Auj." : date.formatted(.dateTime.weekday(.abbreviated).locale(FootFormat.french)).capitalized)
                                    .font(.caption2.weight(.semibold))
                                Text(date.formatted(.dateTime.day().locale(FootFormat.french)))
                                    .font(.headline.monospacedDigit())
                            }
                            .frame(width: 50, height: 58)
                            .foregroundStyle(selected ? .black : .white)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white)
                                } else {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear { proxy.scrollTo(0, anchor: .center) }
        }
    }

    private var filterStrip: some View {
        let counts = matches ?? []
        let teamIDs = Set(profiles.current.teams.map(\.id))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Pill(title: "Tout", icon: "calendar", count: counts.count, selected: filter == .all) { filter = .all }
                if !profiles.current.teams.isEmpty {
                    Pill(title: "Mes équipes", icon: "star.fill",
                         count: counts.filter { teamIDs.contains($0.home.id) || teamIDs.contains($0.away.id) }.count,
                         selected: filter == .myTeams) { filter = .myTeams }
                }
                let live = counts.filter { $0.state == .live }.count
                Pill(title: "Direct", icon: "dot.radiowaves.left.and.right", count: live, selected: filter == .live) { filter = .live }
                ForEach(profiles.current.leagues, id: \.self) { slug in
                    Pill(title: LeagueCatalog.name(of: slug), image: LeagueCatalog.logo(for: slug),
                         count: counts.filter { $0.leagueSlug == slug }.count,
                         selected: filter == .league(slug)) { filter = .league(slug) }
                }
            }
            .padding(.horizontal, 20)
            .animation(.snappy, value: filter)
        }
    }

    private func filtered(_ list: [Match]) -> [Match] {
        let teamIDs = Set(profiles.current.teams.map(\.id))
        switch filter {
        case .all: return list
        case .myTeams: return list.filter { teamIDs.contains($0.home.id) || teamIDs.contains($0.away.id) }
        case .live: return list.filter { $0.state == .live }
        case .league(let slug): return list.filter { $0.leagueSlug == slug }
        }
    }

    private struct LeagueGroup: Identifiable {
        let slug: String
        let name: String
        let matches: [Match]
        var id: String { slug }
    }

    private func groupedByLeague(_ list: [Match]) -> [LeagueGroup] {
        let order = profiles.current.leagues
        let groups = Dictionary(grouping: list, by: \.leagueSlug)
        return groups
            .map { LeagueGroup(slug: $0.key, name: $0.value.first?.leagueName ?? LeagueCatalog.name(of: $0.key), matches: $0.value.sorted { $0.date < $1.date }) }
            .sorted { (order.firstIndex(of: $0.slug) ?? 99, $0.name) < (order.firstIndex(of: $1.slug) ?? 99, $1.name) }
    }

    private func group(title: String, logo: URL?, slug: String?, matches: [Match]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let logo {
                    Crest(url: logo, name: title, size: 22)
                } else {
                    Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xFFD60A))
                }
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let slug {
                    NavigationLink(value: StandingsRoute(slug: slug)) {
                        Text("Classement")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, 22)

            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    MatchRow(match: match)
                    if index < matches.count - 1 {
                        Divider().overlay(.white.opacity(0.06)).padding(.leading, 90)
                    }
                }
            }
            .glassCard(radius: 22)
            .padding(.horizontal, 16)
        }
    }

    private func loadMatches() async {
        let slugs = profiles.footSlugs
        guard !slugs.isEmpty else {
            matches = []
            return
        }
        let result = await EspnClient.shared.day(slugs, day)
        if result.isEmpty, matches == nil {
            // Peut être une vraie journée sans match : on n'affiche pas d'erreur.
            loadError = nil
        }
        matches = result
    }

    // MARK: Classements

    @ViewBuilder
    private var standingsContent: some View {
        let leagues = profiles.current.leagues.isEmpty ? ["fra.1"] : profiles.current.leagues
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(leagues, id: \.self) { slug in
                    Pill(title: LeagueCatalog.name(of: slug), image: LeagueCatalog.logo(for: slug),
                         selected: (standingsSlug ?? leagues[0]) == slug) {
                        standingsSlug = slug
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        StandingsContent(slug: standingsSlug ?? leagues[0])
            .id(standingsSlug ?? leagues[0])
    }

    private func emptyState(title: String, detail: String, action: String?, perform: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "soccerball")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let action, let perform {
                Button(action, action: perform)
                    .buttonStyle(WhiteCapsuleStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 40)
    }
}

/// Classement d'une compétition (chargé à la demande).
struct StandingsContent: View {
    let slug: String
    @Environment(ProfileStore.self) private var profiles
    @State private var table: LeagueTable?
    @State private var error: String?

    var body: some View {
        Group {
            if let table {
                if table.groups.isEmpty {
                    Text("Pas de classement pour cette compétition (élimination directe).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 20)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(table.groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                if table.groups.count > 1 {
                                    Text(group.name).font(.headline).padding(.horizontal, 22)
                                }
                                StandingsTable(rows: group.rows, highlight: Set(profiles.current.teams.map(\.id)), leagueSlug: slug)
                                    .padding(.horizontal, 16)
                            }
                        }
                        let notes = Array(Set(table.groups.flatMap(\.rows).compactMap(\.noteText))).sorted()
                        if !notes.isEmpty {
                            Text(notes.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 22)
                        }
                    }
                }
            } else if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 20)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .task {
            do {
                table = try await EspnClient.shared.standings(slug)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct StandingsView: View {
    let slug: String

    var body: some View {
        ScrollView {
            StandingsContent(slug: slug)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(AmbientBackground(tint: Color(hex: 0x30D158)))
        .navigationTitle(LeagueCatalog.name(of: slug))
        .navigationBarTitleDisplayMode(.large)
        .tabBarSpacing()
    }
}

/// Grille des équipes suivies avec leur prochain match.
struct FollowedTeamsGrid: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(Router.self) private var router
    @State private var next: [String: Match] = [:]
    @State private var loaded = false

    var body: some View {
        let teams = profiles.current.teams
        if teams.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "star").font(.system(size: 40)).foregroundStyle(Theme.textSecondary)
                Text("Tu ne suis aucune équipe").font(.headline)
                Text("Tes équipes passent en premier partout dans l'app.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Choisir mes équipes") { router.sheet = .follow }
                    .buttonStyle(WhiteCapsuleStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(teams) { team in
                    NavigationLink(value: TeamRoute(team: team.team, league: team.league)) {
                        VStack(alignment: .leading, spacing: 12) {
                            Crest(url: team.logo, name: team.name, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.name).font(.headline).lineLimit(1)
                                Text(LeagueCatalog.name(of: team.league)).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Text(nextText(team))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(next[team.id]?.state == .live ? Color(hex: 0xFF453A) : Theme.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(radius: 20)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
            .task(id: teams.map(\.id)) {
                for team in teams where next[team.id] == nil {
                    if let schedule = try? await EspnClient.shared.teamSchedule(team.id, upcoming: true),
                       let match = schedule.filter({ $0.state != .finished }).min(by: { $0.date < $1.date }) {
                        next[team.id] = match
                    }
                }
                loaded = true
            }
        }
    }

    private func nextText(_ team: FollowedTeam) -> String {
        guard let match = next[team.id] else { return loaded ? "Pas de match programmé" : "Chargement…" }
        let home = match.home.id == team.id
        let opponent = home ? match.away.name : match.home.name
        if match.state == .live, let score = displayedScore(match) {
            return "● En direct \(home ? "vs" : "à") \(opponent) \(score.0)-\(score.1)"
        }
        return "\(FootFormat.kickoff(match.date)) · \(home ? "vs" : "à") \(opponent)"
    }
}
