import Foundation

/// Lit une playlist M3U / M3U8 « étendue » (#EXTINF avec attributs tvg-*).
enum M3UParser {
    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z0-9_-]+)="([^"]*)""#
    )

    static func parse(_ text: String) -> [MediaItem] {
        var items: [MediaItem] = []
        var pending: (attributes: [String: String], title: String)?
        var groupOverride: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                pending = parseExtinf(line)
                groupOverride = nil
            } else if line.hasPrefix("#EXTGRP:") {
                groupOverride = String(line.dropFirst("#EXTGRP:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                continue
            } else if let entry = pending, let url = URL(string: line), url.scheme != nil {
                let attributes = entry.attributes
                let groupTitle = attributes["group-title"].flatMap { $0.isEmpty ? nil : $0 }
                let group = groupTitle ?? groupOverride ?? "Sans catégorie"
                let logo = attributes["tvg-logo"].flatMap { URL(string: $0) }

                items.append(MediaItem(
                    id: String(url.absoluteString.stableHash, radix: 16),
                    name: entry.title,
                    group: group,
                    kind: detectKind(url: url),
                    streamURL: url,
                    logoURL: logo,
                    epgID: attributes["tvg-id"].flatMap { $0.isEmpty ? nil : $0 }
                ))
                pending = nil
                groupOverride = nil
            }
        }
        return items
    }

    /// Extrait les attributs `cle="valeur"` et le titre (après la première virgule hors guillemets).
    static func parseExtinf(_ line: String) -> (attributes: [String: String], title: String) {
        var attributes: [String: String] = [:]
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        for match in attributeRegex.matches(in: line, range: range) {
            let key = nsLine.substring(with: match.range(at: 1)).lowercased()
            attributes[key] = nsLine.substring(with: match.range(at: 2))
        }

        var inQuotes = false
        var commaIndex: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                commaIndex = index
                break
            }
            index = line.index(after: index)
        }

        var title = ""
        if let commaIndex {
            title = String(line[line.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty { title = attributes["tvg-name"] ?? "" }
        if title.isEmpty { title = "Sans titre" }
        return (attributes, title)
    }

    /// Les serveurs Xtream exposent les films sous /movie/ et les séries sous /series/.
    static func detectKind(url: URL) -> MediaKind {
        let path = url.path.lowercased()
        if path.contains("/series/") { return .series }
        if path.contains("/movie/") || path.contains("/movies/") { return .movie }
        let videoExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v", "webm"]
        if videoExtensions.contains(url.pathExtension.lowercased()) { return .movie }
        return .live
    }
}
