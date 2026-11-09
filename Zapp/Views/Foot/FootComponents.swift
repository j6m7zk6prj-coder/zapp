import SwiftUI

/// Score à afficher (masqué en mode anti-spoiler pour les matchs terminés).
@MainActor
func displayedScore(_ match: Match, reveal: Bool = false) -> (String, String)? {
    guard match.state != .scheduled, let home = match.homeScore, let away = match.awayScore else { return nil }
    if match.state == .finished && AppSettings.shared.hideScores && !reveal { return ("•", "•") }
    return (home, away)
}

struct MatchStatusBadge: View {
    let match: Match

    var body: some View {
        switch match.state {
        case .live:
            LivePill(text: match.statusText == "Mi-temps" ? "MI-TEMPS" : match.statusText)
        case .postponed:
            Text(match.statusText.uppercased())
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.15), in: Capsule())
        case .finished:
            Text(match.statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        case .scheduled:
            Text(FootFormat.time(match.date))
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
    }
}

/// Carte de match « Pour toi » : compétition, équipes, score ou heure, chaîne.
struct MatchCard: View {
    let match: Match
    var width: CGFloat = 290
    @Environment(Library.self) private var library
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let score = displayedScore(match)
        NavigationLink(value: match) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Crest(url: LeagueCatalog.logo(for: match.leagueSlug), name: match.leagueName, size: 18)
                    Text(match.leagueName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if match.state != .scheduled {
                        MatchStatusBadge(match: match)
                    } else {
                        Text(FootFormat.dayTitle(match.date, short: true))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 9) {
                        teamLine(match.home, winner: match.homeWinner)
                        teamLine(match.away, winner: match.awayWinner)
                    }
                    Spacer(minLength: 4)
                    if let score {
                        VStack(alignment: .trailing, spacing: 9) {
                            Text(score.0)
                            Text(score.1)
                        }
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(match.state == .live ? Color(hex: 0xFF453A) : .white)
                    } else {
                        Text(FootFormat.time(match.date))
                            .font(.title3.weight(.bold).monospacedDigit())
                    }
                }

                if match.state != .finished {
                    channelLine
                }
            }
            .padding(16)
            .frame(width: width, alignment: .leading)
            .glassCard(radius: 22, tint: match.state == .live ? Color(hex: 0xFF453A) : Color(hex: 0x30D158))
        }
        .buttonStyle(PressableStyle())
    }

    private func teamLine(_ team: TeamRef, winner: Bool) -> some View {
        HStack(spacing: 10) {
            Crest(url: team.logo, name: team.name, size: 24)
            Text(team.shortName)
                .font(.subheadline.weight(winner && !settings.hideScores ? .bold : .medium))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var channelLine: some View {
        let channel = Broadcast.channels(for: match.leagueSlug, library: library, profiles: profiles, limit: 1).first
        let label = settings.broadcasterLabel(match.leagueSlug)
        if let channel {
            HStack(spacing: 8) {
                LogoArtwork(url: channel.logoURL, name: channel.name, logoPadding: 2, initialsSize: 9)
                    .frame(width: 34, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(channel.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.white.opacity(0.85))
            }
        } else if !label.isEmpty {
            Label(label, systemImage: "tv")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

struct MatchShelf: View {
    let matches: [Match]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(matches) { match in
                    MatchCard(match: match)
                }
            }
            .padding(.horizontal, 20)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Ligne de match du calendrier (heure, équipes empilées, chaîne).
struct MatchRow: View {
    let match: Match
    @Environment(Library.self) private var library
    @Environment(ProfileStore.self) private var profiles
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let score = displayedScore(match)
        NavigationLink(value: match) {
            HStack(spacing: 14) {
                Group {
                    if match.state == .scheduled {
                        Text(FootFormat.time(match.date))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    } else {
                        MatchStatusBadge(match: match)
                    }
                }
                .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    teamLine(match.home, score: score?.0, winner: match.homeWinner)
                    teamLine(match.away, score: score?.1, winner: match.awayWinner)
                }

                if match.state != .finished {
                    let channel = Broadcast.channels(for: match.leagueSlug, library: library, profiles: profiles, limit: 1).first
                    let label = channel?.displayName ?? settings.broadcasterLabel(match.leagueSlug)
                    if !label.isEmpty {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .frame(width: 74, alignment: .trailing)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func teamLine(_ team: TeamRef, score: String?, winner: Bool) -> some View {
        HStack(spacing: 10) {
            Crest(url: team.logo, name: team.name, size: 22)
            Text(team.name)
                .font(.subheadline.weight(winner && !settings.hideScores ? .bold : .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let score {
                Text(score)
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(match.state == .live ? Color(hex: 0xFF453A) : .white)
            }
        }
    }
}

/// Tableau de classement (équipes cliquables, mise en avant de certaines équipes).
struct StandingsTable: View {
    let rows: [StandingRow]
    var highlight: Set<String> = []
    var compact = false
    var leagueSlug = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(rows) { row in
                NavigationLink(value: TeamRoute(team: TeamRef(id: row.teamID, name: row.teamName, shortName: row.teamName, abbreviation: "", logo: row.logo, color: nil), league: leagueSlug)) {
                    line(row)
                }
                .buttonStyle(.plain)
                .disabled(row.teamID.isEmpty)
            }
        }
        .padding(.vertical, 6)
        .glassCard(radius: 20)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 28)
            Text("Équipe").frame(maxWidth: .infinity, alignment: .leading)
            Text("J").frame(width: 28)
            if !compact {
                Text("G").frame(width: 26)
                Text("N").frame(width: 26)
                Text("P").frame(width: 26)
            }
            Text("Diff").frame(width: 38)
            Text("Pts").frame(width: 36)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func line(_ row: StandingRow) -> some View {
        let isHighlighted = highlight.contains(row.teamID) || highlight.contains(row.teamName)
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let color = row.noteColor, let hex = UInt32(color.replacingOccurrences(of: "#", with: ""), radix: 16) {
                    Capsule().fill(Color(hex: hex)).frame(width: 3, height: 18).offset(x: -6)
                }
                Text("\(row.rank)").frame(width: 28)
            }
            .frame(width: 28)
            HStack(spacing: 8) {
                Crest(url: row.logo, name: row.teamName, size: 20)
                Text(row.teamName).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.played)").frame(width: 28)
            if !compact {
                Text("\(row.won)").frame(width: 26)
                Text("\(row.drawn)").frame(width: 26)
                Text("\(row.lost)").frame(width: 26)
            }
            Text(row.goalDiff).frame(width: 38)
            Text("\(row.points)").fontWeight(.bold).frame(width: 36)
        }
        .font(.footnote.weight(isHighlighted ? .bold : .regular).monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isHighlighted ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

/// Bouton « Regarder sur… » pour une chaîne de la playlist.
struct ChannelButton: View {
    let channel: MediaItem
    let context: [MediaItem]
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.play(channel, context: context)
        } label: {
            HStack(spacing: 10) {
                LogoArtwork(url: channel.logoURL, name: channel.name, logoPadding: 3, initialsSize: 10)
                    .frame(width: 48, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(channel.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
            }
            .padding(10)
            .glassCard(radius: 16)
        }
        .buttonStyle(PressableStyle())
    }
}
