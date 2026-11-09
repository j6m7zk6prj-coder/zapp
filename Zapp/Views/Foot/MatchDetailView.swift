import SwiftUI

/// Fiche d'un match : score, où regarder, buts, statistiques, compositions, classement.
struct MatchDetailView: View {
    let match: Match
    @Environment(Library.self) private var library
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings
    @State private var detail: MatchDetail?
    @State private var current: Match?
    @State private var reveal = false
    @State private var picker = false
    @State private var tab = 0

    private var shown: Match { current ?? match }
    private var hideDetails: Bool { settings.hideScores && shown.state == .finished && !reveal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                whereToWatch
                    .padding(.horizontal, 16)

                if let detail {
                    if hideDetails {
                        Text("Score, buts et statistiques masqués (anti-spoiler).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 20)
                    } else {
                        let tabs = availableTabs(detail)
                        if !tabs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tabs) { item in
                                        Pill(title: item.title, selected: (tabs.contains { $0.id == tab } ? tab : tabs[0].id) == item.id) {
                                            withAnimation(.snappy) { tab = item.id }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            let selected = tabs.contains { $0.id == tab } ? tab : tabs[0].id
                            Group {
                                switch selected {
                                case 0: EventsCard(events: detail.events)
                                case 1: StatsCard(stats: detail.stats)
                                case 2: LineupsCard(lineups: detail.lineups)
                                default:
                                    StandingsTable(rows: compactStandings(detail.standings), highlight: [shown.home.id, shown.away.id], compact: true, leagueSlug: shown.leagueSlug)
                                }
                            }
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                    }
                    if let venue = shown.venue {
                        Label(venue + (detail.attendance.map { " · \($0) spectateurs" } ?? ""), systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 20)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tabBarSpacing()
        .sheet(isPresented: $picker) {
            ChannelPickerView(slug: shown.leagueSlug, leagueName: shown.leagueName)
        }
        .task {
            while !Task.isCancelled {
                if let result = try? await EspnClient.shared.summary(match.id, slug: match.leagueSlug, live: shown.state == .live) {
                    detail = result
                    var updated = result.match
                    updated.leagueName = match.leagueName
                    current = updated
                }
                let live = shown.state == .live || (shown.state == .scheduled && shown.date.timeIntervalSinceNow < 900)
                guard live else { return }
                try? await Task.sleep(for: .seconds(max(20, settings.footRefreshSeconds / 2)))
            }
        }
    }

    // MARK: En-tête

    private var hero: some View {
        let home = Color(hexString: shown.home.color) ?? Color(hex: 0x2A44D8)
        let away = Color(hexString: shown.away.color) ?? Color(hex: 0xA3123A)
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: [home.opacity(0.75), Theme.background, away.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Crest(url: LeagueCatalog.logo(for: shown.leagueSlug), name: shown.leagueName, size: 20)
                    Text(shown.leagueName).font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())

                HStack(alignment: .top, spacing: 8) {
                    teamColumn(shown.home)
                    VStack(spacing: 8) {
                        if let score = displayedScore(shown, reveal: reveal) {
                            Text("\(score.0) – \(score.1)")
                                .font(.system(size: 44, weight: .heavy).monospacedDigit())
                                .foregroundStyle(shown.state == .live ? Color(hex: 0xFF453A) : .white)
                                .contentTransition(.numericText())
                            MatchStatusBadge(match: shown)
                            if hideDetails {
                                Button("Afficher le score") { withAnimation { reveal = true } }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(GlassCapsuleStyle())
                            }
                        } else {
                            Text(FootFormat.time(shown.date))
                                .font(.system(size: 40, weight: .heavy).monospacedDigit())
                            Text(FootFormat.dayTitle(shown.date))
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.8))
                            if shown.state == .postponed { MatchStatusBadge(match: shown) }
                        }
                    }
                    .frame(width: 130)
                    .padding(.top, 16)
                    teamColumn(shown.away)
                }

                if !hideDetails {
                    let goals = (detail?.events ?? shown.events).filter(\.isGoal)
                    if !goals.isEmpty {
                        HStack(alignment: .top) {
                            scorers(goals.filter(\.isHome), alignment: .leading)
                            Spacer()
                            scorers(goals.filter { !$0.isHome }, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.top, 100)
            .padding(.bottom, 10)
        }
    }

    private func teamColumn(_ team: TeamRef) -> some View {
        NavigationLink(value: TeamRoute(team: team, league: shown.leagueSlug)) {
            VStack(spacing: 10) {
                Crest(url: team.logo, name: team.name, size: 72)
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                Text(team.name)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if profiles.follows(team: team.id) {
                    Label("Suivie", systemImage: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xFFD60A))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
    }

    private func scorers(_ goals: [MatchEvent], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            ForEach(goals) { goal in
                Text("\(goal.text) \(goal.clock)\(goal.kind == .penalty ? " (pén.)" : goal.kind == .ownGoal ? " (c.s.c.)" : "")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: Où regarder

    private var whereToWatch: some View {
        let channels = Broadcast.channels(for: shown.leagueSlug, library: library, profiles: profiles)
        let label = settings.broadcasterLabel(shown.leagueSlug)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Où regarder").font(.headline)
                    Text(label.isEmpty ? "Diffuseur non renseigné" : "En France : \(label)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Choisir") { picker = true }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(GlassCapsuleStyle())
            }
            if channels.isEmpty {
                Text(library.all(.live).isEmpty
                     ? "Ajoute une playlist pour voir les chaînes correspondantes."
                     : "Aucune chaîne trouvée dans ta playlist. Choisis-la une fois : elle sera retenue pour toute la compétition.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(channels.prefix(4)) { channel in
                    ChannelButton(channel: channel, context: channels)
                }
            }
        }
        .padding(16)
        .glassCard(radius: 22, tint: Theme.accent)
    }

    // MARK: Onglets

    private struct DetailTab: Identifiable {
        let id: Int
        let title: String
    }

    private func availableTabs(_ detail: MatchDetail) -> [DetailTab] {
        var tabs: [DetailTab] = []
        if !detail.events.isEmpty { tabs.append(DetailTab(id: 0, title: "Résumé")) }
        if !detail.stats.isEmpty { tabs.append(DetailTab(id: 1, title: "Statistiques")) }
        if detail.lineups.contains(where: { !$0.players.isEmpty }) { tabs.append(DetailTab(id: 2, title: "Compositions")) }
        if !detail.standings.isEmpty { tabs.append(DetailTab(id: 3, title: "Classement")) }
        return tabs
    }

    private func compactStandings(_ rows: [StandingRow]) -> [StandingRow] {
        guard rows.count > 12 else { return rows }
        let indexes = rows.indices.filter { [shown.home.id, shown.away.id].contains(rows[$0].teamID) || [shown.home.name, shown.away.name].contains(rows[$0].teamName) }
        guard let first = indexes.min(), let last = indexes.max() else { return rows }
        return Array(rows[max(0, first - 2)...min(rows.count - 1, last + 2)])
    }
}

private struct EventsCard: View {
    let events: [MatchEvent]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                HStack(spacing: 10) {
                    if event.isHome {
                        Text(event.text).font(.subheadline.weight(event.isGoal ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .trailing)
                        icon(event)
                    } else {
                        Spacer().frame(maxWidth: .infinity)
                    }
                    Text(event.clock)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 46)
                        .foregroundStyle(Theme.textSecondary)
                    if !event.isHome {
                        icon(event)
                        Text(event.text).font(.subheadline.weight(event.isGoal ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
                .lineLimit(1)
                .padding(.vertical, 9)
            }
        }
        .padding(14)
        .glassCard(radius: 20)
    }

    private func icon(_ event: MatchEvent) -> some View {
        Image(systemName: event.symbol)
            .font(.caption)
            .foregroundStyle(event.kind == .yellow ? Color(hex: 0xFFD60A) : event.kind == .red ? Color(hex: 0xFF453A) : .white)
    }
}

private struct StatsCard: View {
    let stats: [StatLine]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(stats) { stat in
                VStack(spacing: 7) {
                    HStack {
                        Text(stat.home).font(.subheadline.weight(.bold).monospacedDigit())
                        Spacer()
                        Text(stat.label).font(.caption).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(stat.away).font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    GeometryReader { proxy in
                        let total = stat.homeValue + stat.awayValue
                        let share = total > 0 ? stat.homeValue / total : 0.5
                        HStack(spacing: 4) {
                            Capsule()
                                .fill(stat.homeValue >= stat.awayValue ? Theme.accent : Color.white.opacity(0.2))
                                .frame(width: max(4, (proxy.size.width - 4) * share))
                            Capsule()
                                .fill(stat.awayValue > stat.homeValue ? Theme.accent : Color.white.opacity(0.2))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(18)
        .glassCard(radius: 20)
    }
}

private struct LineupsCard: View {
    let lineups: [Lineup]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(lineups) { lineup in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(lineup.teamName).font(.headline)
                        Spacer()
                        if let formation = lineup.formation {
                            Text(formation)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                    ForEach(lineup.players.filter(\.starter)) { player in row(player) }
                    let subs = lineup.players.filter { !$0.starter }
                    if !subs.isEmpty {
                        Text("Remplaçants").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary).padding(.top, 6)
                        ForEach(subs) { player in row(player).opacity(0.8) }
                    }
                }
                .padding(16)
                .glassCard(radius: 20)
            }
        }
    }

    private func row(_ player: LineupPlayer) -> some View {
        HStack(spacing: 10) {
            Text(player.jersey)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, alignment: .leading)
            Text(player.name).font(.subheadline)
            if player.subbedIn { Image(systemName: "arrow.up").font(.caption2).foregroundStyle(Color(hex: 0x30D158)) }
            if player.subbedOut { Image(systemName: "arrow.down").font(.caption2).foregroundStyle(Color(hex: 0xFF453A)) }
            Spacer()
            Text(player.position).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}

extension Color {
    /// « 1A2B3C » ou « #1A2B3C » (couleurs d'équipes ESPN), assombrie si trop claire.
    init?(hexString: String?) {
        guard var text = hexString?.trimmed, !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        let factor = luminance > 0.6 ? 0.45 : 1
        self.init(red: r / 255 * factor, green: g / 255 * factor, blue: b / 255 * factor)
    }
}
