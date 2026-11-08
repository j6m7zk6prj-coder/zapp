import SwiftUI

struct OnboardingView: View {
    @State private var showAdd = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.background, Color(hex: 0x151B3A)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 8) {
                    Text("Zapp TV")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                    Text("Ton lecteur IPTV, façon streaming.")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("tv", "Chaînes en direct et zapping instantané")
                    feature("film", "Films et séries rangés par catégorie")
                    feature("heart", "Favoris et recherche globale")
                    feature("pip", "AirPlay et Picture in Picture")
                }
                .padding(.horizontal, 8)

                Spacer()

                Button {
                    showAdd = true
                } label: {
                    Text("Ajouter une playlist")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text("Zapp ne fournit aucun contenu. Ajoute une playlist M3U ou Xtream à laquelle tu as légalement accès.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(24)
        }
        .sheet(isPresented: $showAdd) { AddPlaylistView() }
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
