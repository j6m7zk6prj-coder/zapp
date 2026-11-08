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
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(3)
                                .padding(8)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Logo de chaîne : logo sur fond sombre, ou initiales sur dégradé.
struct LogoBadge: View {
    let item: MediaItem
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: item.logoURL) { phase in
            if let image = phase.image {
                ZStack {
                    Theme.surfaceHigh
                    image.resizable().scaledToFit().padding(6)
                }
            } else {
                ZStack {
                    Theme.gradient(for: item.name)
                    Text(item.initials)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat?
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterArt(item: item)
                .overlay(alignment: .topTrailing) {
                    if favorites.contains(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .foregroundStyle(.pink)
                            .padding(6)
                    }
                }
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .contextMenu { FavoriteButton(item: item) }
    }
}

struct ChannelTile: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LogoBadge(item: item, cornerRadius: 12)
                .frame(width: 150, height: 84)
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu { FavoriteButton(item: item) }
    }
}

struct ChannelRow: View {
    let item: MediaItem
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        HStack(spacing: 14) {
            LogoBadge(item: item)
                .frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
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
            Image(systemName: item.opensDetail ? "chevron.right" : "play.fill")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { FavoriteButton(item: item) }
    }
}

struct FavoriteButton: View {
    let item: MediaItem
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        let isFavorite = favorites.contains(item)
        Button {
            favorites.toggle(item)
        } label: {
            Label(
                isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                systemImage: isFavorite ? "heart.slash" : "heart"
            )
        }
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
