import SwiftUI

/// Ouvre le bon éditeur : lien perso, ou modification d'un élément de playlist.
struct ItemEditorView: View {
    let item: MediaItem
    @Environment(CustomizationStore.self) private var customization
    @Environment(Library.self) private var library

    var body: some View {
        if item.isCustomLink, let link = customization.link(forItemID: item.id) {
            LinkEditorView(link: link)
        } else {
            OverrideEditorView(
                original: library.baseItem(item.id) ?? item,
                current: customization.itemOverride(for: item.id)
            )
        }
    }
}

/// Renommer, changer le logo ou la catégorie, masquer une chaîne / un film de la playlist.
struct OverrideEditorView: View {
    let original: MediaItem
    @Environment(CustomizationStore.self) private var customization
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var group: String
    @State private var logo: LogoDraft
    @State private var hidden: Bool
    @State private var didSave = false

    init(original: MediaItem, current: ItemOverride) {
        self.original = original
        _name = State(initialValue: current.name ?? "")
        _group = State(initialValue: current.group ?? "")
        _logo = State(initialValue: LogoDraft(
            urlText: current.logoURL?.absoluteString ?? "",
            file: current.logoFile,
            removed: current.removeLogo == true,
            original: original.logoURL
        ))
        _hidden = State(initialValue: current.hidden == true)
    }

    private var previewName: String { name.trimmed.isEmpty ? original.name : name }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        LogoArtwork(url: logo.previewURL, name: previewName, logoPadding: 8, initialsSize: 18)
                            .frame(width: 96, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(previewName)
                                .font(.headline)
                                .lineLimit(2)
                            Text(group.trimmed.isEmpty ? original.group : group)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField(original.name, text: $name)
                } header: {
                    Text("Nom")
                } footer: {
                    Text("Laisse vide pour garder « \(original.name) ».")
                }

                Section {
                    GroupField(group: $group, placeholder: original.group, suggestions: Array(library.groups(of: original.kind).prefix(80)))
                } header: {
                    Text("Catégorie")
                } footer: {
                    Text("Tu peux taper un nom de catégorie nouveau : elle sera créée.")
                }

                LogoSection(draft: $logo, name: previewName)

                Section {
                    Toggle("Masquer cet élément", isOn: $hidden)
                } footer: {
                    Text("Un élément masqué n'apparaît plus nulle part. Tu peux le réafficher dans Réglages → Éléments masqués.")
                }

                Section {
                    Button("Rétablir l'original", role: .destructive) {
                        customization.resetOverride(for: original.id)
                        logo.discardUnused(keeping: nil)
                        didSave = true
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
            .onDisappear {
                if !didSave { logo.discardUnused(keeping: nil) }
            }
        }
    }

    private func save() {
        var value = ItemOverride()
        value.name = name.trimmed.isEmpty ? nil : name.trimmed
        value.group = group.trimmed.isEmpty ? nil : group.trimmed
        value.removeLogo = logo.removed ? true : nil
        value.logoFile = logo.removed ? nil : logo.file
        value.logoURL = logo.removed ? nil : logo.customURL
        value.hidden = hidden ? true : nil
        customization.setOverride(value, for: original.id)
        logo.discardUnused(keeping: value.logoFile)
        didSave = true
        dismiss()
    }
}
