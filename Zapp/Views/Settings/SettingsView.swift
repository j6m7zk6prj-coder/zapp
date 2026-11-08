import SwiftUI

struct SettingsView: View {
    @Environment(PlaylistStore.self) private var playlists
    @Environment(CustomizationStore.self) private var customization
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                        HiddenItemsView()
                    } label: {
                        SettingsRow(icon: "eye.slash.fill", color: .gray, title: "Éléments masqués",
                                    value: "\(library.hiddenItems.count)")
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
                    Text("Zapp est uniquement un lecteur : il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des liens et playlists auxquels tu as légalement accès.")
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
