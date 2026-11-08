import SwiftUI

/// Affiche verticale 2:3 (films, séries) avec repli sur un dégradé + titre.
struct PosterArt: View {
    let item: MediaItem

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                AsyncImage(url: item.logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack(alignment: .bottomLeading) {
                            Theme.gradient(for: item.name)
                            Text(item.displayName)
                                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(4)
                                .padding(10)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.07))
            }
    }
}

/// Vignette 16:9 façon Apple TV : logo de chaîne centré sur un fond sombre.
struct LandscapeArt: View {
    let item: MediaItem

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                LogoArtwork(url: item.logoURL, name: item.name, logoPadding: 16, initialsSize: 26)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.07))
            }
    }
}

/// Logo sur fond sombre, ou initiales sur dégradé si pas d'image.
struct LogoArtwork: View {
    let url: URL?
    let name: String
    var logoPadding: CGFloat = 6
    var initialsSize: CGFloat = 15

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                ZStack {
                    LinearGradient(colors: [Theme.surfaceHigh, Theme.surface], startPoint: .top, endPoint: .bottom)
                    image.resizable().scaledToFit().padding(logoPadding)
                }
            } else {
                ZStack {
                    Theme.gradient(for: name.isEmpty ? "?" : name)
                    Text(name.initials)
                        .font(.system(size: initialsSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

struct LogoBadge: View {
    let item: MediaItem
    var cornerRadius: CGFloat = 8

    var body: some View {
        LogoArtwork(url: item.logoURL, name: item.name)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

enum TileStyle {
    case poster, landscape, auto
}

/// Carte d'une étagère ou d'une grille : image + titre, menu contextuel.
struct MediaTile: View {
    let item: MediaItem
    var style: TileStyle = .auto
    /// nil = s'adapte à la cellule de grille.
    var width: CGFloat?
    @Environment(FavoritesStore.self) private var favorites

    private var isLandscape: Bool {
        switch style {
        case .landscape: return true
        case .poster: return false
        case .auto: return item.kind == .live
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if isLandscape {
                    LandscapeArt(item: item)
                } else {
                    PosterArt(item: item)
                }
            }
            .overlay(alignment: .topTrailing) {
                if favorites.contains(item) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .padding(6)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.pink)
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 5)

            Text(item.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            if isLandscape {
                Text(item.group)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .contextMenu { ItemMenu(item: item) }
    }
}

struct ChannelRow: View {
    let item: MediaItem
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        HStack(spacing: 14) {
            LogoBadge(item: item, cornerRadius: 10)
                .frame(width: 72, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(item.group)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if favorites.contains(item) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
            Image(systemName: item.kind == .live ? "play.fill" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { ItemMenu(item: item) }
    }
}

/// Actions de l'appui long : lire, favori, modifier, masquer.
struct ItemMenu: View {
    let item: MediaItem
    @Environment(FavoritesStore.self) private var favorites
    @Environment(Router.self) private var router
    @Environment(CustomizationStore.self) private var customization

    var body: some View {
        let isFavorite = favorites.contains(item)
        if item.streamURL != nil {
            Button {
                router.play(item, context: [item])
            } label: {
                Label("Lire", systemImage: "play.fill")
            }
        }
        Button {
            favorites.toggle(item)
        } label: {
            Label(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                  systemImage: isFavorite ? "heart.slash" : "heart")
        }
        Button {
            router.edit(item)
        } label: {
            Label("Modifier nom, logo, catégorie…", systemImage: "pencil")
        }
        Button(role: .destructive) {
            customization.setHidden(true, id: item.id)
        } label: {
            Label("Masquer", systemImage: "eye.slash")
        }
    }
}

/// Légère réduction à l'appui, comme les cartes de l'app TV.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Gros bouton blanc « Lire ».
struct PrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Bouton rond translucide (favori, modifier…).
struct CircleActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(.ultraThinMaterial, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct LiveBadge: View {
    var body: some View {
        Text("DIRECT")
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.subheadline)
                Button("Réessayer", action: retry)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
