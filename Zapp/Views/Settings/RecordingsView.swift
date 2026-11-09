import SwiftUI

/// Enregistrements de flux : lire, renommer, partager, supprimer.
struct RecordingsView: View {
    @State private var playing: PlaybackRequest?
    @State private var files: [Recordings.File] = []
    @State private var renaming: Recordings.File?
    @State private var newName = ""

    var body: some View {
        List {
            if files.isEmpty {
                ContentUnavailableView(
                    "Aucun enregistrement",
                    systemImage: "record.circle",
                    description: Text("Pendant la lecture, touche le bouton ⏺ en haut du lecteur pour enregistrer le flux en pleine qualité.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(files) { file in
                        Button {
                            playing = PlaybackRequest(queue: [file.playable], index: 0)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 40)
                                    .background(Theme.gradient(for: file.name), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text("\(file.date.formatted(date: .abbreviated, time: .shortened)) · \(file.sizeText)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ShareLink(item: file.url) { Label("Partager / enregistrer", systemImage: "square.and.arrow.up") }
                            Button {
                                newName = file.name
                                renaming = file
                            } label: { Label("Renommer", systemImage: "pencil") }
                            Button(role: .destructive) {
                                delete(file)
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(file) } label: { Label("Supprimer", systemImage: "trash") }
                            ShareLink(item: file.url) { Label("Partager", systemImage: "square.and.arrow.up") }
                                .tint(.blue)
                        }
                    }
                } footer: {
                    Text("Aussi dans l'app Fichiers › Sur mon iPhone › iTv › Enregistrements. Usage privé uniquement.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle("Enregistrements")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { reload() }
        .fullScreenCover(item: $playing) { request in PlayerView(request: request) }
        .onAppear { reload() }
        .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nom", text: $newName)
            Button("Renommer") {
                if let file = renaming { _ = Recordings.rename(file, to: newName) }
                renaming = nil
                reload()
            }
            Button("Annuler", role: .cancel) { renaming = nil }
        }
    }

    private func reload() {
        files = Recordings.list()
    }

    private func delete(_ file: Recordings.File) {
        Recordings.delete(file)
        withAnimation { reload() }
    }
}
