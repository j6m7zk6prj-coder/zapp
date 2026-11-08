import PhotosUI
import SwiftUI

/// Logo en cours d'édition : image importée, URL, ou retiré.
struct LogoDraft: Equatable {
    var urlText = ""
    var file: String?
    var removed = false
    /// Logo d'origine (playlist), affiché si rien d'autre n'est choisi.
    var original: URL?
    /// Images importées pendant cette édition (pour faire le ménage).
    var createdFiles: [String] = []

    var customURL: URL? {
        let value = urlText.trimmed
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }

    var previewURL: URL? {
        if removed { return nil }
        if let file { return AppPaths.logoFile(file) }
        if let customURL { return customURL }
        return original
    }

    /// Supprime les images importées qui ne sont pas gardées.
    func discardUnused(keeping kept: String?) {
        for name in createdFiles where name != kept {
            LogoStorage.delete(name)
        }
    }
}

struct LogoSection: View {
    @Binding var draft: LogoDraft
    let name: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false

    var body: some View {
        Section {
            HStack(spacing: 16) {
                LogoArtwork(url: draft.previewURL, name: name, logoPadding: 8, initialsSize: 20)
                    .frame(width: 112, height: 63)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        if isImporting { ProgressView() }
                    }
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choisir une image", systemImage: "photo.on.rectangle")
                    }
                    if draft.previewURL != nil {
                        Button(role: .destructive) {
                            draft.file = nil
                            draft.urlText = ""
                            draft.removed = true
                        } label: {
                            Label("Retirer le logo", systemImage: "trash")
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding(.vertical, 4)

            TextField("…ou adresse d'une image (https://…/logo.png)", text: $draft.urlText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Logo")
        } footer: {
            Text("Image depuis tes photos ou lien vers un logo en ligne.")
        }
        .onChange(of: draft.urlText) {
            if !draft.urlText.trimmed.isEmpty {
                draft.file = nil
                draft.removed = false
            }
        }
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            isImporting = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let saved = LogoStorage.save(data) {
                    draft.file = saved
                    draft.createdFiles.append(saved)
                    draft.urlText = ""
                    draft.removed = false
                }
                isImporting = false
                pickerItem = nil
            }
        }
    }
}

/// Champ catégorie avec suggestions des catégories existantes.
struct GroupField: View {
    @Binding var group: String
    let placeholder: String
    let suggestions: [String]

    var body: some View {
        HStack {
            TextField(placeholder, text: $group)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { group = suggestion }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Choisir une catégorie existante")
            }
        }
    }
}
