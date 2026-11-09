import SwiftUI
import UIKit

/// « Qui regarde ? » : choisir, créer ou modifier un profil.
struct ProfilePickerView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Profile?
    @State private var isEditing = false
    @AppStorage("profiles.askOnLaunch") private var askOnLaunch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 6) {
                        (Text("Qui ") + Text("regarde").accentSerif(size: 38) + Text(" ?"))
                            .font(.system(size: 38, weight: .bold))
                        Text("Chaque profil a sa liste, son historique, ses ligues et ses équipes.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 30)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 24)], spacing: 28) {
                        ForEach(profiles.profiles) { profile in
                            Button {
                                if isEditing {
                                    editing = profile
                                } else {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    withAnimation(.snappy) { profiles.switchTo(profile.id) }
                                    dismiss()
                                }
                            } label: {
                                VStack(spacing: 12) {
                                    ProfileAvatar(profile: profile, size: 104, ring: profile.id == profiles.activeID)
                                        .overlay(alignment: .topTrailing) {
                                            if isEditing {
                                                Image(systemName: "pencil.circle.fill")
                                                    .font(.title2)
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.black, .white)
                                            }
                                        }
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundStyle(profile.id == profiles.activeID ? .white : .white.opacity(0.75))
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }

                        if profiles.profiles.count < 8 {
                            Button {
                                let profile = profiles.add(name: "")
                                editing = profile
                            } label: {
                                VStack(spacing: 12) {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                        .frame(width: 104, height: 104)
                                        .overlay(Image(systemName: "plus").font(.system(size: 34, weight: .medium)))
                                    Text("Ajouter").font(.headline).foregroundStyle(.white.opacity(0.75))
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 24)

                    Toggle("Demander au lancement", isOn: $askOnLaunch)
                        .tint(Theme.accent)
                        .padding(16)
                        .glassCard(radius: 18)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 30)
            }
            .background(AmbientBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "Terminé" : "Modifier") { withAnimation { isEditing.toggle() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $editing) { profile in
                ProfileEditorView(profile: profile)
            }
        }
    }
}

struct ProfileEditorView: View {
    @State var profile: Profile
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileAvatar(profile: profile, size: 96)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Nom") {
                    TextField("Nom du profil", text: $profile.name)
                }
                Section("Couleur") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Profile.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white, lineWidth: profile.colorHex == hex ? 3 : 0))
                                .onTapGesture { profile.colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Icône") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        Text(profile.initial)
                            .font(.headline)
                            .frame(width: 38, height: 38)
                            .background(profile.symbol == nil ? Color.white.opacity(0.25) : .clear, in: Circle())
                            .onTapGesture { profile.symbol = nil }
                        ForEach(Profile.symbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .frame(width: 38, height: 38)
                                .background(profile.symbol == symbol ? Color.white.opacity(0.25) : .clear, in: Circle())
                                .onTapGesture { profile.symbol = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if profiles.profiles.count > 1 {
                    Section {
                        Button("Supprimer le profil", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground().ignoresSafeArea())
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if profile.name.trimmed.isEmpty { profile.name = "Profil" }
                        profiles.update(profile)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Supprimer « \(profile.name) » ? Sa liste, son historique et ses équipes seront effacés.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    profiles.delete(profile)
                    dismiss()
                }
            }
        }
    }
}
