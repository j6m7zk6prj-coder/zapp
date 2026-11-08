import SwiftUI

struct OnboardingView: View {
    private enum Sheet: String, Identifiable {
        case link, playlist
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                Image(systemName: "play.tv.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 30)

                VStack(spacing: 8) {
                    Text("Zapp TV")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                    Text("Tous tes flux, au même endroit.")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
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
                    .buttonStyle(PrimaryActionStyle())

                    Button {
                        sheet = .playlist
                    } label: {
                        Text("Ajouter une playlist")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(CardButtonStyle())
                }

                Text("Zapp ne fournit aucun contenu. Utilise uniquement des flux auxquels tu as légalement accès.")
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
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }
}
