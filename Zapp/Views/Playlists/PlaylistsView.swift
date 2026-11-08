import SwiftUI

/// Gestion des playlists (ouverte depuis les Réglages).
struct PlaylistsView: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(Library.self) private var library
    @State private var showAdd = false

    var body: some View {
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
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .overlay {
            if store.playlists.isEmpty {
                ContentUnavailableView {
                    Label("Aucune playlist", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("URL M3U, fichier M3U ou compte Xtream Codes.")
                } actions: {
                    Button("Ajouter une playlist") { showAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
