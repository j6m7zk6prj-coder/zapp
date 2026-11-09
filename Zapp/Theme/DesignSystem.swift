import SwiftUI

// MARK: - Fonds

/// Fond d'écran iTv : noir profond avec des lueurs colorées très douces.
struct AmbientBackground: View {
    var tint: Color = Theme.accent
    var warm: Bool = true

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [tint.opacity(0.32), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
            if warm {
                RadialGradient(colors: [Color(hex: 0xFF8A4C).opacity(0.14), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 560)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cartes en verre

struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    if let tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.28), .clear], startPoint: .bottomLeading, endPoint: .topTrailing))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, tint: Color? = nil) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }
}

// MARK: - Textes

extension Text {
    /// Mot d'accent en italique (style éditorial).
    func accentSerif(size: CGFloat) -> Text {
        font(.system(size: size, weight: .regular, design: .serif)).italic()
    }
}

/// Titre de section façon Apple TV, avec action « Tout voir ».
struct SectionTitle<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Boutons

/// Bouton principal : capsule blanche, texte noir (comme l'app TV d'Apple).
struct WhiteCapsuleStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Bouton secondaire en verre.
struct GlassCapsuleStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Bouton rond en verre (favori, infos…).
struct GlassCircleStyle: ButtonStyle {
    var size: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Effet « pression » sur les cartes.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Pastilles

struct Pill: View {
    let title: String
    var icon: String?
    var image: URL?
    var count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let image {
                    RemoteImage(url: image, contentMode: .fit) { Color.clear }
                        .frame(width: 18, height: 18)
                }
                if let icon {
                    Image(systemName: icon).font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selected ? Color.black.opacity(0.12) : Color.white.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background {
                if selected {
                    Capsule().fill(.white)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: selected)
    }
}

/// Petite étiquette arrondie (« Nouveau », « Tendance »…).
struct InfoTag: View {
    let text: String
    var icon: String?
    var color: Color = .white

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
    }
}

struct LivePill: View {
    var text = "DIRECT"
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6).opacity(pulse ? 0.35 : 1)
            Text(text).font(.caption2.weight(.heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: 0xFF3B30), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Images

/// Image distante avec repli, mise en cache par URLCache.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    let placeholder: Placeholder

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
    }
}

/// Écusson d'équipe ou logo de compétition (initiales si l'image manque).
struct Crest: View {
    let url: URL?
    let name: String
    var size: CGFloat = 28

    var body: some View {
        RemoteImage(url: url, contentMode: .fit) {
            Circle()
                .fill(Theme.gradient(for: name))
                .overlay(Text(name.initials).font(.system(size: size * 0.34, weight: .heavy)).foregroundStyle(.white))
        }
        .frame(width: size, height: size)
    }
}

/// Avatar de profil (cercle coloré, symbole ou initiale).
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 34
    var ring = false

    var body: some View {
        let color = Color(hex: profile.colorHex)
        Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let symbol = profile.symbol {
                    Image(systemName: symbol).font(.system(size: size * 0.42, weight: .bold))
                } else {
                    Text(profile.initial).font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white, lineWidth: ring ? 3 : 0))
            .shadow(color: color.opacity(0.4), radius: ring ? 14 : 0)
    }
}

/// Barre de progression fine (reprise de lecture).
struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xFFC58A)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * value))
            }
        }
        .frame(height: height)
    }
}

/// Espace sous le contenu pour la barre d'onglets flottante.
extension View {
    func tabBarSpacing() -> some View {
        safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
    }
}
