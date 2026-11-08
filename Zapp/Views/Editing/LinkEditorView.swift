import SwiftUI

/// Ajout / modification d'un lien de flux, un par un.
struct LinkEditorView: View {
    let existing: CustomLink?
    @Environment(CustomizationStore.self) private var customization
    @Environment(PlaylistStore.self) private var playlists
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var address: String
    @State private var name: String
    @State private var kind: MediaKind
    @State private var group: String
    @State private var logo: LogoDraft
    @State private var testRequest: PlaybackRequest?
    @State private var errorMessage: String?
    @State private var didSave = false
    @State private var kindEdited: Bool

    init(link: CustomLink?) {
        existing = link
        _address = State(initialValue: link?.url.absoluteString ?? "")
        _name = State(initialValue: link?.name ?? "")
        _kind = State(initialValue: link?.kind ?? .live)
        _group = State(initialValue: link?.group ?? "")
        _logo = State(initialValue: LogoDraft(
            urlText: link?.logoURL?.absoluteString ?? "",
            file: link?.logoFile
        ))
        _kindEdited = State(initialValue: link != nil)
    }

    private var parsedURL: URL? { LinkInspector.normalize(address) }

    var body: some View {
        NavigationStack {
            Form {
                linkSection

                if let url = parsedURL, LinkInspector.looksLikePlaylist(url) {
                    Section {
                        Label("Ce lien ressemble à une playlist complète (plusieurs chaînes).",
                              systemImage: "list.bullet.rectangle")
                            .font(.subheadline)
                        Button("L'ajouter comme playlist") { addAsPlaylist(url) }
                    }
                }

                Section("Informations") {
                    TextField("Nom (ex. : Ma chaîne)", text: $name)
                    Picker("Type", selection: kindBinding) {
                        Label("Chaîne en direct", systemImage: "dot.radiowaves.left.and.right").tag(MediaKind.live)
                        Label("Film / vidéo", systemImage: "film").tag(MediaKind.movie)
                    }
                    GroupField(group: $group, placeholder: "Catégorie (\(CustomLink.defaultGroup))", suggestions: groupSuggestions)
                }

                LogoSection(draft: $logo, name: name.isEmpty ? (parsedURL?.host ?? "?") : name)

                Section {
                    Button {
                        test()
                    } label: {
                        Label("Tester le lien", systemImage: "play.circle.fill")
                    }
                    .disabled(parsedURL == nil)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let existing {
                    Section {
                        Button("Supprimer ce lien", role: .destructive) {
                            customization.delete(existing)
                            didSave = true
                            logo.discardUnused(keeping: nil)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Nouveau lien" : "Modifier le lien")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Ajouter" : "Enregistrer") { save() }
                        .disabled(parsedURL == nil)
                }
            }
            .onChange(of: address) {
                // Devine le type tant que l'utilisateur ne l'a pas choisi lui-même.
                if !kindEdited, let url = parsedURL {
                    kind = LinkInspector.guessKind(url)
                }
            }
            .onDisappear {
                if !didSave { logo.discardUnused(keeping: nil) }
            }
            .fullScreenCover(item: $testRequest) { request in
                PlayerView(request: request)
            }
        }
    }

    private var linkSection: some View {
        Section {
            TextField("http://…/flux.m3u8, rtmp://…, udp://@…", text: $address, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
            if let url = parsedURL {
                let format = LinkInspector.format(of: url)
                HStack {
                    Label(format.rawValue, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("Lu par \(PlaybackSupport.engineLabel(for: url, preference: AppSettings.shared.engine))")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
            } else if !address.trimmed.isEmpty {
                Label("Lien non reconnu", systemImage: "xmark.octagon.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Lien du flux")
        } footer: {
            Text("Formats acceptés : HLS (.m3u8), MP4, TS, MKV, AVI, FLV, RTMP, RTSP, UDP, RTP, SRT, MMS…")
        }
    }

    private var kindBinding: Binding<MediaKind> {
        Binding(get: { kind }, set: { kind = $0; kindEdited = true })
    }

    private var groupSuggestions: [String] {
        var seen = Set<String>()
        let all = [CustomLink.defaultGroup] + library.groups(of: kind)
        return Array(all.filter { seen.insert($0).inserted }.prefix(60))
    }

    private func save() {
        guard let url = parsedURL else {
            errorMessage = "Lien invalide."
            return
        }
        let finalName = name.trimmed.isEmpty ? (url.host ?? url.lastPathComponent) : name.trimmed
        var link = existing ?? CustomLink(name: finalName, url: url)
        link.name = finalName
        link.url = url
        link.kind = kind
        link.group = group.trimmed.isEmpty ? CustomLink.defaultGroup : group.trimmed
        link.logoFile = logo.removed ? nil : logo.file
        link.logoURL = logo.removed ? nil : logo.customURL
        customization.save(link)
        logo.discardUnused(keeping: link.logoFile)
        didSave = true
        dismiss()
    }

    private func test() {
        guard let url = parsedURL else { return }
        let playable = Playable(
            id: "test-\(url.absoluteString.stableHash)",
            title: name.trimmed.isEmpty ? "Test du lien" : name.trimmed,
            subtitle: url.host ?? url.absoluteString,
            url: url,
            artworkURL: logo.previewURL,
            isLive: kind == .live
        )
        testRequest = PlaybackRequest(queue: [playable], index: 0)
    }

    private func addAsPlaylist(_ url: URL) {
        let playlistName = name.trimmed.isEmpty ? (url.host ?? "Playlist") : name.trimmed
        playlists.add(Playlist(name: playlistName, source: .m3uURL(url)), password: nil)
        dismiss()
    }
}
