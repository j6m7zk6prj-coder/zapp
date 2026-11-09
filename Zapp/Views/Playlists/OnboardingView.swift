import SwiftUI

struct OnboardingView: View {
    private enum Sheet: String, Identifiable {
        case link, playlist
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 26) {
                Spacer()

                InfoTag(text: "Bienvenue sur iTv", icon: "sparkles")

                VStack(spacing: 10) {
                    (Text("Toute ta télé,\n") + Text("sublimée.").accentSerif(size: 46))
                        .font(.system(size: 42, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Direct, films, séries et foot réunis dans une app pensée pour l'iPhone.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("link", "Ajoute tes liens un par un : HLS, TS, MKV, RTMP, UDP…")
                    feature("list.bullet.rectangle", "Ou une playlist M3U / Xtream complète")
                    feature("pencil", "Renomme, change les logos et les catégories")
                    feature("paintbrush", "Personnalise les couleurs de l'app")
                }
                .padding(.horizontal, 4)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        sheet = .link
                    } label: {
                        Label("Ajouter un lien", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(WhiteCapsuleStyle(fullWidth: true))

                    Button {
                        sheet = .playlist
                    } label: {
                        Text("Ajouter une playlist")
                    }
                    .buttonStyle(GlassCapsuleStyle(fullWidth: true))
                }

                Text("iTv ne fournit aucun contenu. Utilise uniquement des flux auxquels tu as légalement accès.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(24)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .link: LinkEditorView(link: nil)
            case .playlist: AddPlaylistView()
            }
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(.subheadline)
        }
    }
}
