import SwiftUI

struct PlaylistsView: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.playlists) { playlist in
                        Button {
                            store.setActive(playlist.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.body.weight(.semibold))
                                    Text(playlist.source.label)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if store.active?.id == playlist.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { store.playlists[$0] }
                        for playlist in removed { store.remove(playlist) }
                    }
                } header: {
                    Text("Mes playlists")
                } footer: {
                    Text("Touche une playlist pour l'activer, balaye vers la gauche pour la supprimer.")
                }

                Section {
                    Button {
                        Task {
                            if let active = store.active {
                                await library.load(active, force: true)
                            }
                        }
                    } label: {
                        Label(library.isLoading ? "Actualisation…" : "Actualiser la playlist active",
                              systemImage: "arrow.clockwise")
                    }
                    .disabled(library.isLoading || store.active == nil)
                }

                Section("À propos") {
                    Text("Zapp est uniquement un lecteur : il ne fournit aucune chaîne ni aucun contenu. Utilise seulement des playlists auxquelles tu as légalement accès.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter une playlist")
                }
            }
            .sheet(isPresented: $showAdd) { AddPlaylistView() }
        }
    }
}
