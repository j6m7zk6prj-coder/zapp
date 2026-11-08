import SwiftUI
import UniformTypeIdentifiers

struct AddPlaylistView: View {
    enum SourceKind: String, CaseIterable, Identifiable {
        case url = "URL M3U"
        case file = "Fichier"
        case xtream = "Xtream"
        var id: String { rawValue }
    }

    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SourceKind = .url
    @State private var name = ""
    @State private var m3uAddress = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var storedFileName: String?
    @State private var importedFileLabel: String?
    @State private var showImporter = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didSave = false

    private static let importTypes: [UTType] = [
        UTType(filenameExtension: "m3u"),
        UTType(filenameExtension: "m3u8"),
        .plainText,
        .data,
    ].compactMap { $0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(SourceKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Nom") {
                    TextField("Ma playlist", text: $name)
                }

                switch kind {
                case .url:
                    Section {
                        TextField("https://exemple.com/playlist.m3u", text: $m3uAddress)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Adresse de la playlist")
                    } footer: {
                        Text("Lien M3U / M3U8 fourni par ton fournisseur.")
                    }

                case .file:
                    Section("Fichier") {
                        Button {
                            showImporter = true
                        } label: {
                            Label(importedFileLabel ?? "Choisir un fichier .m3u", systemImage: "doc.badge.plus")
                        }
                    }

                case .xtream:
                    Section {
                        TextField("Serveur (http://hote:port)", text: $server)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Identifiant", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Mot de passe", text: $password)
                    } header: {
                        Text("Xtream Codes")
                    } footer: {
                        Text("Le mot de passe est stocké dans le trousseau de l'iPhone.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Ajouter une playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Ajouter") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes) { result in
                handleImport(result)
            }
            .onDisappear {
                // Fichier importé mais playlist abandonnée : on fait le ménage.
                if !didSave, let storedFileName {
                    try? FileManager.default.removeItem(at: AppPaths.playlistFile(storedFileName))
                }
            }
        }
    }

    private var canSave: Bool {
        switch kind {
        case .url: return !m3uAddress.trimmingCharacters(in: .whitespaces).isEmpty
        case .file: return storedFileName != nil
        case .xtream: return !server.isEmpty && !username.isEmpty && !password.isEmpty
        }
    }

    private func save() async {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .url:
            guard let url = URL(string: m3uAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                errorMessage = "Adresse invalide. Elle doit commencer par http:// ou https://."
                return
            }
            finish(Playlist(name: trimmedName.isEmpty ? (url.host ?? "Playlist M3U") : trimmedName,
                            source: .m3uURL(url)),
                   password: nil)

        case .file:
            guard let storedFileName else { return }
            finish(Playlist(name: trimmedName.isEmpty ? "Playlist importée" : trimmedName,
                            source: .m3uFile(storedFileName)),
                   password: nil)

        case .xtream:
            guard let serverURL = XtreamCredentials.normalizedServer(server) else {
                errorMessage = "Adresse du serveur invalide."
                return
            }
            let login = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentials = XtreamCredentials(server: serverURL, username: login, password: password)
            isWorking = true
            defer { isWorking = false }
            do {
                try await XtreamClient(credentials: credentials).authenticate()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            finish(Playlist(name: trimmedName.isEmpty ? (serverURL.host ?? "Xtream") : trimmedName,
                            source: .xtream(server: serverURL, username: login)),
                   password: password)
        }
    }

    private func finish(_ playlist: Playlist, password: String?) {
        store.add(playlist, password: password)
        didSave = true
        dismiss()
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                try AppPaths.ensurePlaylistsFolder()
                let fileName = UUID().uuidString + ".m3u"
                try FileManager.default.copyItem(at: url, to: AppPaths.playlistFile(fileName))
                if let previous = storedFileName {
                    try? FileManager.default.removeItem(at: AppPaths.playlistFile(previous))
                }
                storedFileName = fileName
                importedFileLabel = url.lastPathComponent
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                errorMessage = nil
            } catch {
                errorMessage = "Impossible d'importer ce fichier : \(error.localizedDescription)"
            }
        }
    }
}
