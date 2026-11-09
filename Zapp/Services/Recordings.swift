import Foundation

/// Enregistrements de flux : fichiers .ts rangés dans Documents/Enregistrements
/// (visibles dans l'app Fichiers, dossier « iTv »).
enum Recordings {
    struct File: Identifiable, Hashable {
        let url: URL
        let name: String
        let date: Date
        let size: Int64
        var id: URL { url }

        var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

        var playable: Playable {
            Playable(id: "recording-\(name)", title: name, subtitle: "Enregistrement", url: url, artworkURL: nil, isLive: false)
        }
    }

    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Enregistrements", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Dossier de travail d'un enregistrement en cours (VLC y écrit le fichier).
    static func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Nom de fichier lisible : « Titre 2026-11-09 21h14 ».
    static func fileName(title: String, date: Date = Date()) -> String {
        let invalid = CharacterSet(charactersIn: "/\\\\?%*|\"<>:")
        var clean = title.components(separatedBy: invalid).joined(separator: " ").trimmed
        if clean.isEmpty { clean = "Enregistrement" }
        if clean.count > 60 { clean = String(clean.prefix(60)).trimmed }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH'h'mm"
        return "\(clean) \(formatter.string(from: date))"
    }

    /// Déplace le fichier produit par VLC vers « Enregistrements » sous un nom lisible.
    static func finalize(folder: URL, title: String) -> URL? {
        let manager = FileManager.default
        defer { try? manager.removeItem(at: folder) }
        guard let produced = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]))?
            .max(by: { size(of: $0) < size(of: $1) }),
              size(of: produced) > 0 else { return nil }
        let ext = produced.pathExtension.isEmpty ? "ts" : produced.pathExtension
        var target = self.folder.appendingPathComponent(fileName(title: title)).appendingPathExtension(ext)
        var counter = 2
        while manager.fileExists(atPath: target.path) {
            target = self.folder.appendingPathComponent("\(fileName(title: title)) (\(counter))").appendingPathExtension(ext)
            counter += 1
        }
        do {
            try manager.moveItem(at: produced, to: target)
            return target
        } catch {
            return nil
        }
    }

    static func list() -> [File] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return File(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                date: values?.creationDate ?? values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0)
            )
        }
        .sorted { $0.date > $1.date }
    }

    static func delete(_ file: File) {
        try? FileManager.default.removeItem(at: file.url)
    }

    static func rename(_ file: File, to name: String) -> URL? {
        let clean = name.trimmed
        guard !clean.isEmpty else { return nil }
        let target = folder.appendingPathComponent(clean).appendingPathExtension(file.url.pathExtension)
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        return (try? FileManager.default.moveItem(at: file.url, to: target)).map { target }
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
