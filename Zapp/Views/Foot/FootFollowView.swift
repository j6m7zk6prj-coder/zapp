import SwiftUI

/// Choisir les compétitions et les équipes suivies par le profil actif.
struct FootFollowView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var query = ""
    @State private var teamsLeague = "fra.1"
    @State private var teams: [TeamRef]?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $tab) {
                        Text("Compétitions").tag(0)
                        Text("Équipes").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if tab == 0 {
                    leagues
                } else {
                    teamsContent
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tint: Color(hex: 0x30D158)).ignoresSafeArea())
            .searchable(text: $query, prompt: tab == 0 ? "Rechercher une compétition" : "Rechercher une équipe")
            .navigationTitle("Ligues et équipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .task(id: teamsLeague) {
                guard tab == 1 || teams == nil else { return }
                await loadTeams()
            }
            .onChange(of: tab) {
                if tab == 1 && teams == nil { Task { await loadTeams() } }
            }
            .onAppear {
                teamsLeague = profiles.current.leagues.first(where: { $0.hasSuffix(".1") }) ?? "fra.1"
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        query.trimmed.isEmpty || text.range(of: query.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    @ViewBuilder
    private var leagues: some View {
        let areas = Dictionary(grouping: LeagueCatalog.all.filter { matches($0.name + " " + $0.area) }, by: \.area)
        let order = ["France", "Europe", "Angleterre", "Espagne", "Italie", "Allemagne"]
        ForEach(areas.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }, id: \.self) { area in
            Section(area) {
                ForEach(areas[area] ?? []) { league in
                    Toggle(isOn: Binding(
                        get: { profiles.follows(league: league.slug) },
                        set: { profiles.setLeague(league.slug, followed: $0) }
                    )) {
                        HStack(spacing: 12) {
                            Crest(url: LeagueCatalog.logo(for: league.slug), name: league.name, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(league.name)
                                if !league.broadcaster.isEmpty {
                                    Text(league.broadcaster).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .tint(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var teamsContent: some View {
        let followed = profiles.current.teams
        if !followed.isEmpty {
            Section("Tes équipes") {
                ForEach(followed) { team in
                    HStack(spacing: 12) {
                        Crest(url: team.logo, name: team.name, size: 28)
                        VStack(alignment: .leading) {
                            Text(team.name)
                            Text(LeagueCatalog.name(of: team.league)).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button {
                            withAnimation { profiles.setTeam(team, followed: false) }
                        } label: {
                            Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xFFD60A))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let leagues = LeagueCatalog.all.filter { profiles.follows(league: $0.slug) || $0.slug.hasSuffix(".1") }
                    ForEach(leagues) { league in
                        Pill(title: league.name, image: LeagueCatalog.logo(for: league.slug), selected: teamsLeague == league.slug) {
                            teamsLeague = league.slug
                            teams = nil
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }

        Section(LeagueCatalog.name(of: teamsLeague)) {
            if let error {
                Text(error).foregroundStyle(Theme.textSecondary)
            } else if let teams {
                ForEach(teams.filter { matches($0.name) }) { team in
                    let model = FollowedTeam(id: team.id, name: team.name, logo: team.logo ?? TeamRef.logo(for: team.id), league: teamsLeague)
                    Toggle(isOn: Binding(
                        get: { profiles.follows(team: team.id) },
                        set: { profiles.setTeam(model, followed: $0) }
                    )) {
                        HStack(spacing: 12) {
                            Crest(url: model.logo, name: team.name, size: 28)
                            Text(team.name)
                        }
                    }
                    .tint(Theme.accent)
                }
            } else {
                ProgressView()
            }
        }
    }

    private func loadTeams() async {
        error = nil
        do {
            teams = try await EspnClient.shared.teams(teamsLeague)
        } catch {
            self.error = "Impossible de charger les équipes : \(error.localizedDescription)"
        }
    }
}

/// Épingler les chaînes de la playlist qui diffusent une compétition, et modifier les mots-clés.
struct ChannelPickerView: View {
    let slug: String
    let leagueName: String
    @Environment(Library.self) private var library
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var keywords = ""
    @State private var playing: PlaybackRequest?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Ex. : Canal+ Foot, beIN Sports 1", text: $keywords, axis: .vertical)
                        .onSubmit(save)
                    Button("Rétablir les diffuseurs par défaut") {
                        settings.broadcasters[slug] = nil
                        keywords = settings.broadcasterKeywords(slug)
                    }
                } header: {
                    Text("Diffuseurs / mots-clés")
                } footer: {
                    Text("Sert à retrouver les bonnes chaînes dans ta playlist. Sépare-les par des virgules.")
                }

                Section(query.isEmpty ? "Suggestions" : "Résultats") {
                    let rows = channels
                    if library.all(.live).isEmpty {
                        Text("Aucune chaîne : ajoute d'abord une playlist ou des liens.").foregroundStyle(Theme.textSecondary)
                    } else if rows.isEmpty {
                        Text(query.isEmpty ? "Aucune chaîne ne correspond aux diffuseurs. Cherche-la par son nom." : "Aucune chaîne ne correspond.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(rows) { channel in
                        let pinned = profiles.pinnedChannels(slug).contains(channel.id)
                        HStack(spacing: 12) {
                            LogoArtwork(url: channel.logoURL, name: channel.name, logoPadding: 3, initialsSize: 10)
                                .frame(width: 52, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.displayName).lineLimit(1)
                                Text(channel.group).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            Button {
                                withAnimation { profiles.togglePin(slug, channelID: channel.id) }
                            } label: {
                                Image(systemName: pinned ? "pin.fill" : "pin")
                                    .foregroundStyle(pinned ? Theme.accent : .white)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(pinned ? "Désépingler" : "Épingler")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let playable = channel.playable { playing = PlaybackRequest(queue: [playable], index: 0) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground().ignoresSafeArea())
            .searchable(text: $query, prompt: "Rechercher une chaîne")
            .navigationTitle(leagueName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear { keywords = settings.broadcasterKeywords(slug) }
            .fullScreenCover(item: $playing) { request in PlayerView(request: request) }
        }
    }

    private var channels: [MediaItem] {
        let all = library.all(.live)
        let pinned = Set(profiles.pinnedChannels(slug))
        if !query.trimmed.isEmpty {
            return Array(all.filter {
                $0.name.range(of: query.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }.prefix(150))
        }
        var seen = Set<String>()
        let pinnedItems = all.filter { pinned.contains($0.id) }
        let suggested = ChannelMatcher.find(in: all, keywords: keywords, limit: 30)
        return (pinnedItems + suggested).filter { seen.insert($0.id).inserted }
    }

    private func save() {
        let value = keywords.trimmed
        let defaults = LeagueCatalog.find(slug)?.channelKeywords ?? ""
        settings.broadcasters[slug] = value.isEmpty || value == defaults ? nil : value
    }
}
