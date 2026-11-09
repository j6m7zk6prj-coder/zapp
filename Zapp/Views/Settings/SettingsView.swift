import SwiftUI

struct SettingsView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(CustomizationStore.self) private var customization
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(ProfileStore.self) private var profiles
    @Environment(MetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var showProfiles = false
    @State private var showFollow = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showProfiles = true
                    } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(profile: profiles.active, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profiles.active.name).font(.headline)
                                Text("\(profiles.profiles.count) profil\(profiles.profiles.count > 1 ? "s" : "") · changer ou modifier")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Contenu") {
                    NavigationLink {
                        LinksView()
                    } label: {
                        SettingsRow(icon: "link", color: .orange, title: "Mes liens",
                                    value: "\(customization.links.count)")
                    }
                    NavigationLink {
                        PlaylistsView()
                    } label: {
                        SettingsRow(icon: "list.bullet.rectangle.fill", color: .blue, title: "Playlists",
                                    value: "\(playlists.playlists.count)")
                    }
                    NavigationLink {
                        RecordingsView()
                    } label: {
                        SettingsRow(icon: "record.circle", color: .red, title: "Enregistrements", value: nil)
                    }
                    NavigationLink {
                        HiddenItemsView()
                    } label: {
                        SettingsRow(icon: "eye.slash.fill", color: .gray, title: "Éléments masqués",
                                    value: "\(library.hiddenItems.count)")
                    }
                }

                Section {
                    NavigationLink {
                        TmdbSettingsView()
                    } label: {
                        SettingsRow(icon: "film.stack", color: .purple, title: "Fiches films et séries",
                                    value: settings.tmdbKey.trimmed.isEmpty ? "Désactivées" : "Activées")
                    }
                } footer: {
                    Text("Grandes affiches, notes, résumés, acteurs, bandes-annonces et tendances (TMDB).")
                }

                Section("Foot") {
                    Button {
                        showFollow = true
                    } label: {
                        SettingsRow(icon: "soccerball", color: .green, title: "Ligues et équipes suivies",
                                    value: "\(profiles.current.leagues.count + profiles.current.teams.count)")
                    }
                    .buttonStyle(.plain)
                    Toggle(isOn: Binding(get: { settings.hideScores }, set: { settings.hideScores = $0 })) {
                        SettingsRow(icon: "eye.slash", color: .gray, title: "Anti-spoiler (masquer les scores)", value: nil)
                    }
                    .tint(Theme.accent)
                    Picker(selection: Binding(get: { settings.footRefreshSeconds }, set: { settings.footRefreshSeconds = $0 })) {
                        Text("30 s").tag(30)
                        Text("1 min").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                    } label: {
                        SettingsRow(icon: "arrow.clockwise", color: .teal, title: "Actualisation des scores", value: nil)
                    }
                    NavigationLink {
                        BroadcastersView()
                    } label: {
                        SettingsRow(icon: "tv", color: .indigo, title: "Où regarder (chaînes)", value: nil)
                    }
                }

                Section("Personnalisation") {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        SettingsRow(icon: "paintbrush.fill", color: .pink, title: "Apparence", value: nil)
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { settings.autoPlayNext }, set: { settings.autoPlayNext = $0 })) {
                        SettingsRow(icon: "forward.end.fill", color: .orange, title: "Épisode suivant automatique", value: nil)
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: Binding(get: { settings.resumePlayback }, set: { settings.resumePlayback = $0 })) {
                        SettingsRow(icon: "clock.arrow.circlepath", color: .blue, title: "Reprendre là où je me suis arrêté", value: nil)
                    }
                    .tint(Theme.accent)
                    Button(role: .destructive) {
                        profiles.clearHistory()
                    } label: {
                        Text("Effacer l'historique de ce profil")
                    }
                    Picker(selection: Binding(get: { settings.engine }, set: { settings.setEngine($0) })) {
                        ForEach(PlaybackEngine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    } label: {
                        SettingsRow(icon: "play.rectangle.fill", color: .green, title: "Moteur de lecture", value: nil)
                    }
                } header: {
                    Text("Lecture")
                } footer: {
                    if PlaybackSupport.vlcAvailable {
                        Text(settings.engine.explanation)
                    } else {
                        Text("Le moteur VLC n'est pas inclus dans cette version : seuls HLS et MP4 sont lisibles.")
                    }
                }

                Section("À propos") {
                    LabeledContent("Version", value: appVersion)
                    Text("iTv est uniquement un lecteur : il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des liens et playlists auxquels tu as légalement accès.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $showProfiles) { ProfilePickerView() }
            .sheet(isPresented: $showFollow) { FootFollowView() }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
            Spacer()
            if let value {
                Text(value).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Liste des liens ajoutés à la main.
struct LinksView: View {
    @Environment(CustomizationStore.self) private var customization
    @State private var editing: CustomLink?
    @State private var isAdding = false

    var body: some View {
        List {
            ForEach(customization.links) { link in
                Button {
                    editing = link
                } label: {
                    HStack(spacing: 12) {
                        LogoArtwork(url: link.resolvedLogoURL, name: link.name, logoPadding: 4, initialsSize: 13)
                            .frame(width: 64, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.name)
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                            Text("\(LinkInspector.format(of: link.url).rawValue) · \(link.group)")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let removed = offsets.map { customization.links[$0] }
                for link in removed { customization.delete(link) }
            }
            .onMove { source, destination in
                customization.moveLinks(from: source, to: destination)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .overlay {
            if customization.links.isEmpty {
                ContentUnavailableView {
                    Label("Aucun lien", systemImage: "link")
                } description: {
                    Text("Ajoute tes flux un par un : HLS, TS, MKV, RTMP, RTSP, UDP…")
                } actions: {
                    Button("Ajouter un lien") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Mes liens")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter un lien")
            }
            if !customization.links.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .sheet(item: $editing) { link in
            LinkEditorView(link: link)
        }
        .sheet(isPresented: $isAdding) {
            LinkEditorView(link: nil)
        }
    }
}

struct HiddenItemsView: View {
    @Environment(Library.self) private var library
    @Environment(CustomizationStore.self) private var customization

    var body: some View {
        List(library.hiddenItems) { item in
            HStack(spacing: 12) {
                LogoBadge(item: item)
                    .frame(width: 64, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).lineLimit(1)
                    Text(item.group)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Afficher") {
                    customization.setHidden(false, id: item.id)
                }
                .buttonStyle(.bordered)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .overlay {
            if library.hiddenItems.isEmpty {
                ContentUnavailableView("Rien de masqué", systemImage: "eye",
                                       description: Text("Appui long sur une chaîne → Masquer."))
            }
        }
        .navigationTitle("Éléments masqués")
    }
}

/// Clé TMDB : fiches enrichies et tendances.
struct TmdbSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MetadataStore.self) private var metadata
    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        List {
            Section {
                TextField("Clé d'API (v3) ou jeton (v4)", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(key.trimmed.isEmpty ? "Désactiver les fiches" : "Enregistrer et tester")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(checking)
                if let status {
                    Text(status).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Clé TMDB")
            } footer: {
                Text("Gratuit, 2 minutes : crée un compte sur themoviedb.org → Paramètres → API → Créer → « Développeur », usage personnel → copie la « Clé d'API » ici.")
            }

            Section {
                Button("Ouvrir themoviedb.org") {
                    if let url = URL(string: "https://www.themoviedb.org/settings/api") { openURL(url) }
                }
                if !settings.tmdbKey.trimmed.isEmpty {
                    Button("Vider le cache des fiches") {
                        Task {
                            await metadata.clearCache()
                            status = "Cache vidé."
                        }
                    }
                }
            } footer: {
                Text("Ce produit utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle("Fiches films et séries")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { key = settings.tmdbKey }
    }

    private func save() async {
        let value = key.trimmed
        guard !value.isEmpty else {
            settings.tmdbKey = ""
            status = "Fiches désactivées."
            return
        }
        checking = true
        defer { checking = false }
        if await metadata.validate(key: value) {
            settings.tmdbKey = value
            status = "Clé valide : les fiches sont activées."
            await metadata.loadTrending(library: library)
        } else {
            status = "Clé refusée par TMDB (ou pas de connexion). Vérifie-la et réessaie."
        }
    }
}

/// Diffuseur et chaînes associées pour chaque compétition suivie.
struct BroadcastersView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @State private var picking: League?

    var body: some View {
        List {
            Section {
                ForEach(profiles.current.leagues, id: \.self) { slug in
                    let league = LeagueCatalog.find(slug) ?? League(slug: slug, name: LeagueCatalog.name(of: slug), area: "", broadcaster: "", channelKeywords: "")
                    let channels = Broadcast.channels(for: slug, library: library, profiles: profiles, limit: 3)
                    Button {
                        picking = league
                    } label: {
                        HStack(spacing: 12) {
                            Crest(url: LeagueCatalog.logo(for: slug), name: league.name, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(league.name)
                                Text(channels.isEmpty ? (settings.broadcasterLabel(slug).isEmpty ? "Non renseigné" : settings.broadcasterLabel(slug)) : channels.map(\.displayName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Diffuseurs en France pour la saison 2026-2027. Touche une compétition pour épingler la bonne chaîne de ta playlist.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle("Où regarder")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picking) { league in
            ChannelPickerView(slug: league.slug, leagueName: league.name)
        }
    }
}
