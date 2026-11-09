import SwiftUI

/// Fiche d'une équipe : suivre, prochains matchs, résultats, forme, classement.
struct TeamView: View {
    let team: TeamRef
    let leagueSlug: String
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings
    @State private var upcoming: [Match]?
    @State private var results: [Match] = []
    @State private var table: LeagueTable?
    @State private var league = ""

    var body: some View {
        let follows = profiles.follows(team: team.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [(Color(hexString: team.color) ?? Theme.accent).opacity(0.8), Theme.background],
                                   startPoint: .topLeading, endPoint: .bottom)
                        .frame(height: 300)
                    HStack(spacing: 18) {
                        Crest(url: team.logo ?? TeamRef.logo(for: team.id), name: team.name, size: 92)
                            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(team.name)
                                .font(.system(size: 28, weight: .bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            if !league.isEmpty {
                                Text(LeagueCatalog.name(of: league))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Button {
                                withAnimation(.snappy) {
                                    profiles.setTeam(FollowedTeam(id: team.id, name: team.name, logo: team.logo ?? TeamRef.logo(for: team.id), league: league), followed: !follows)
                                }
                            } label: {
                                Label(follows ? "Suivie" : "Suivre", systemImage: follows ? "star.fill" : "star")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(follows ? AnyButtonStyle(GlassCapsuleStyle()) : AnyButtonStyle(WhiteCapsuleStyle()))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                if let upcoming {
                    if let live = upcoming.first(where: { $0.state == .live }) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("En ce moment")
                            MatchShelf(matches: [live])
                        }
                    }
                    section("Prochains matchs", matches: upcoming.filter { $0.state != .live }, empty: "Aucun match programmé.")
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if !settings.hideScores { form.padding(.horizontal, 20) }
                            section("Derniers résultats", matches: results, empty: "")
                        }
                    }
                    if let table, let group = table.groups.first(where: { $0.rows.contains { $0.teamID == team.id || $0.teamName == team.name } }) ?? table.groups.first {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Classement · \(group.name.isEmpty ? LeagueCatalog.name(of: league) : group.name)")
                            StandingsTable(rows: group.rows, highlight: [team.id, team.name], compact: true, leagueSlug: league)
                                .padding(.horizontal, 16)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
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
        .task { await load() }
    }

    private func section(_ title: String, matches: [Match], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            if matches.isEmpty {
                if !empty.isEmpty {
                    Text(empty).font(.subheadline).foregroundStyle(Theme.textSecondary).padding(.horizontal, 20)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(matches) { match in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(FootFormat.dayTitle(match.date)) · \(match.leagueName)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                            MatchRow(match: match)
                        }
                    }
                }
                .glassCard(radius: 22)
                .padding(.horizontal, 16)
            }
        }
    }

    /// Forme récente : V / N / D.
    private var form: some View {
        HStack(spacing: 6) {
            Text("Forme").font(.subheadline.weight(.semibold)).padding(.trailing, 4)
            ForEach(results.prefix(5).reversed()) { match in
                let home = match.home.id == team.id
                let won = home ? match.homeWinner : match.awayWinner
                let lost = home ? match.awayWinner : match.homeWinner
                Text(won ? "V" : lost ? "D" : "N")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(won ? .black : .white)
                    .frame(width: 26, height: 26)
                    .background(won ? Color(hex: 0x30D158) : lost ? Color(hex: 0xFF453A) : Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    private func load() async {
        league = leagueSlug
        let next = (try? await EspnClient.shared.teamSchedule(team.id, upcoming: true)) ?? []
        let past = (try? await EspnClient.shared.teamSchedule(team.id, upcoming: false)) ?? []
        upcoming = Array(next.filter { $0.state != .finished }.sorted { $0.date < $1.date }.prefix(10))
        results = Array(past.filter { $0.state == .finished }.sorted { $0.date > $1.date }.prefix(10))
        if league.isEmpty {
            // Championnat national : la compétition « xxx.1 » la plus fréquente du calendrier.
            let counts = Dictionary(grouping: past + next, by: \.leagueSlug)
                .filter { $0.key.range(of: #"^[a-z]+\.\d$"#, options: .regularExpression) != nil }
            league = counts.max { $0.value.count < $1.value.count }?.key ?? ""
        }
        if !league.isEmpty { table = try? await EspnClient.shared.standings(league) }
    }
}

/// Style de bouton choisi à l'exécution.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
