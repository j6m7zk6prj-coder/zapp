import SwiftUI

/// Personnalisation du thème : couleur, fond, taille des affiches, affichage du direct.
struct AppearanceView: View {
    @Environment(AppSettings.self) private var settings

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        Form {
            Section {
                ThemePreview()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Couleur d'accent") {
                LazyVGrid(columns: swatchColumns, spacing: 14) {
                    ForEach(AppSettings.accentPresets) { preset in
                        let selected = settings.accentHex == preset.hex
                        Button {
                            withAnimation(.snappy) { settings.setAccent(preset.hex) }
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(Theme.isLight(preset.hex) ? Color.black : Color.white)
                                    }
                                }
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 3 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker(
                    "Couleur personnalisée",
                    selection: Binding(
                        get: { Color(hex: settings.accentHex) },
                        set: { settings.setAccent($0.hexValue) }
                    ),
                    supportsOpacity: false
                )
            }

            Section("Fond") {
                ForEach(BackgroundStyle.allCases) { style in
                    Button {
                        withAnimation(.easeInOut) { settings.setBackground(style) }
                    } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: style.glow), Color(hex: style.base)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 46, height: 30)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.white.opacity(0.2))
                                }
                            Text(style.title)
                            Spacer()
                            if settings.background == style {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Affiches") {
                Picker("Taille", selection: Binding(get: { settings.posterSize }, set: { settings.setPosterSize($0) })) {
                    ForEach(PosterSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("En direct") {
                Picker("Affichage", selection: Binding(get: { settings.liveLayout }, set: { settings.setLiveLayout($0) })) {
                    ForEach(LiveLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Réinitialiser l'apparence", role: .destructive) {
                    withAnimation { settings.resetAppearance() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle("Apparence")
    }
}

/// Aperçu en direct du thème choisi.
private struct ThemePreview: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Tout")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(Theme.onAccent)
                Text("Sport")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
                Text("Infos")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .font(.footnote.weight(.semibold))

            HStack(spacing: 12) {
                ForEach(["Aurore", "Horizon", "Comète"], id: \.self) { title in
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.gradient(for: title))
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay {
                                Text(title.initials)
                                    .font(.system(.headline, design: .rounded).weight(.heavy))
                            }
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            HStack {
                Label("Lire", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .background(Theme.backdrop, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        }
        .foregroundStyle(.white)
    }
}
