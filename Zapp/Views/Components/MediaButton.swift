import SwiftUI

/// Ouvre une série dans sa fiche, ou lance directement la lecture.
struct MediaButton<Content: View>: View {
    let item: MediaItem
    let context: [MediaItem]
    let content: Content
    @Environment(PlayerPresenter.self) private var presenter

    init(item: MediaItem, context: [MediaItem], @ViewBuilder content: () -> Content) {
        self.item = item
        self.context = context
        self.content = content()
    }

    var body: some View {
        if item.opensDetail {
            NavigationLink(value: item) { content }
                .buttonStyle(.plain)
        } else {
            Button {
                presenter.play(item, context: context)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }
}

/// Filtre des catégories (puces horizontales).
enum CategoryFilter: Hashable {
    case all
    case favorites
    case group(String)

    func apply(to items: [MediaItem], favoriteIDs: Set<String>) -> [MediaItem] {
        switch self {
        case .all: return items
        case .favorites: return items.filter { favoriteIDs.contains($0.id) }
        case .group(let name): return items.filter { $0.group == name }
        }
    }
}

struct CategoryChips: View {
    let groups: [String]
    @Binding var selection: CategoryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                chip("Tout", value: .all)
                chip("Favoris", value: .favorites, icon: "heart.fill")
                ForEach(groups, id: \.self) { group in
                    chip(group, value: .group(group))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(height: 56)
    }

    private func chip(_ title: String, value: CategoryFilter, icon: String? = nil) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.caption2)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.accent : Theme.surfaceHigh, in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct ShelfRow: View {
    let title: String
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        MediaButton(item: item, context: items) {
                            if item.kind == .live {
                                ChannelTile(item: item)
                            } else {
                                PosterCard(item: item, width: 112)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct CategoryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Spacer(minLength: 12)
                Text(title)
                    .font(.headline.weight(.heavy))
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.85)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
