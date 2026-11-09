import CommonCrypto
import Foundation
import Observation

enum RecordingError: LocalizedError {
    case nothingSaved
    case refused(Int)
    case network(String)
    case disk

    var errorDescription: String? {
        switch self {
        case .nothingSaved:
            return "L'enregistrement n'a rien reçu : réessaie quelques secondes après le début de la lecture."
        case .refused(let code):
            return code == 403 || code == 429 || code == 509 || code == 456
                ? "Le fournisseur a refusé l'enregistrement (\(code)) : ton abonnement n'autorise peut-être qu'une connexion à la fois."
                : "Le serveur a refusé l'enregistrement (\(code))."
        case .network(let message):
            return "Enregistrement interrompu : \(message)"
        case .disk:
            return "Impossible d'écrire le fichier (plus assez d'espace ?)."
        }
    }
}

/// Enregistre un flux en pleine qualité, sans réencodage :
/// - HLS (.m3u8) : téléchargement des segments de la meilleure qualité, mis bout à bout (déchiffrés si AES-128) ;
/// - TS, MP4 et autres flux http(s) : copie directe des octets ;
/// - RTMP, RTSP, UDP… : enregistreur intégré de VLC.
@MainActor
@Observable
final class StreamRecorder {
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    /// Message quand l'enregistrement s'arrête tout seul.
    private(set) var failure: String?

    @ObservationIgnored private var task: Task<RecordingOutcome, Never>?
    @ObservationIgnored private var usesVLC = false
    @ObservationIgnored private var title = ""

    nonisolated static func supports(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    func start(url: URL, title: String) {
        guard !isRecording else { return }
        self.title = title
        usesVLC = false
        failure = nil
        isRecording = true
        startedAt = Date()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).part")
        task = Task.detached(priority: .utility) {
            await RecordingEngine.run(url: url, output: output)
        }
        // Si la copie s'arrête d'elle-même (flux coupé, refus du serveur), on prévient.
        let current = task
        Task { [weak self] in
            guard let outcome = await current?.value else { return }
            guard let self, self.isRecording, self.task == current else { return }
            self.isRecording = false
            self.startedAt = nil
            self.task = nil
            switch self.store(outcome) {
            case .success(let file):
                self.failure = "Enregistrement terminé (\(file.sizeText)) : le flux s'est arrêté."
                Task { _ = await Remuxer.convertToMP4(file.url) }
            case .failure(let error): self.failure = error.localizedDescription
            }
        }
    }

    func startWithVLC(_ vlc: VLCPlayerModel, title: String) {
        guard !isRecording else { return }
        self.title = title
        usesVLC = true
        failure = nil
        isRecording = true
        startedAt = Date()
        vlc.startRecording(title: title)
    }

    func stop(vlc: VLCPlayerModel, completion: @escaping (Result<Recordings.File, Error>) -> Void) {
        guard isRecording else { return }
        isRecording = false
        startedAt = nil
        if usesVLC {
            vlc.stopRecording { url in
                if let url, let file = Recordings.list().first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                    completion(.success(file))
                } else {
                    completion(.failure(RecordingError.nothingSaved))
                }
            }
            return
        }
        guard let task else { return }
        self.task = nil
        task.cancel()
        Task {
            let outcome = await task.value
            completion(self.store(outcome))
        }
    }

    /// Range le fichier temporaire dans « Enregistrements » sous un nom lisible.
    private func store(_ outcome: RecordingOutcome) -> Result<Recordings.File, Error> {
        let manager = FileManager.default
        let size = (try? outcome.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else {
            try? manager.removeItem(at: outcome.file)
            return .failure(outcome.error ?? RecordingError.nothingSaved)
        }
        let base = Recordings.fileName(title: title)
        var target = Recordings.folder.appendingPathComponent(base).appendingPathExtension(outcome.fileExtension)
        var counter = 2
        while manager.fileExists(atPath: target.path) {
            target = Recordings.folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension(outcome.fileExtension)
            counter += 1
        }
        do {
            try manager.moveItem(at: outcome.file, to: target)
        } catch {
            return .failure(RecordingError.disk)
        }
        let file = Recordings.File(url: target, name: target.deletingPathExtension().lastPathComponent, date: Date(), size: Int64(size))
        return .success(file)
    }
}

struct RecordingOutcome: Sendable {
    let file: URL
    let fileExtension: String
    let error: Error?
}

/// Moteur de copie (hors du thread principal).
enum RecordingEngine {
    static let userAgent = "VLC/3.0.21 LibVLC/3.0.21"

    static func run(url: URL, output: URL) async -> RecordingOutcome {
        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: output) else {
            return RecordingOutcome(file: output, fileExtension: "ts", error: RecordingError.disk)
        }
        defer { try? handle.close() }
        var ext = "ts"
        do {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let http = response as? HTTPURLResponse
            if let code = http?.statusCode, !(200..<300).contains(code) { throw RecordingError.refused(code) }
            let finalURL = response.url ?? url
            let mime = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let path = finalURL.path.lowercased()

            if path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") || mime.contains("mpegurl") {
                var text = ""
                for try await line in bytes.lines { text += line + "\n" }
                ext = try await HLSRecorder(playlistURL: finalURL, firstPlaylist: text, handle: handle).run()
            } else {
                if path.hasSuffix(".mp4") || path.hasSuffix(".m4v") || mime.contains("mp4") { ext = "mp4" }
                else if path.hasSuffix(".mkv") || mime.contains("matroska") { ext = "mkv" }
                try await copy(bytes: bytes, to: handle)
            }
            return RecordingOutcome(file: output, fileExtension: ext, error: nil)
        } catch is CancellationError {
            return RecordingOutcome(file: output, fileExtension: ext, error: nil)
        } catch let error as URLError where error.code == .cancelled {
            return RecordingOutcome(file: output, fileExtension: ext, error: nil)
        } catch {
            let wrapped: Error = error is RecordingError ? error : RecordingError.network(error.localizedDescription)
            return RecordingOutcome(file: output, fileExtension: ext, error: wrapped)
        }
    }

    /// Copie directe d'un flux continu (TS…) par paquets de 512 Ko.
    private static func copy(bytes: URLSession.AsyncBytes, to handle: FileHandle) async throws {
        var buffer = Data()
        buffer.reserveCapacity(600_000)
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 512_000 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    try Task.checkCancellation()
                }
            }
        } catch {
            if !buffer.isEmpty { try? handle.write(contentsOf: buffer) }
            throw error
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
    }

    static func fetch(_ url: URL) async throws -> (Data, URL) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw RecordingError.refused(code)
        }
        return (data, response.url ?? url)
    }
}

/// Playlist HLS analysée (publique pour les tests).
struct HLSPlaylist {
    struct Segment {
        let url: URL
        let sequence: Int
        let keyURL: URL?
        let keyMethod: String
        let iv: Data?
        let mapURL: URL?
    }

    struct Variant {
        let url: URL
        let bandwidth: Int
    }

    var isMaster = false
    var variants: [Variant] = []
    var segments: [Segment] = []
    var targetDuration: Double = 6
    var endList = false

    init(text: String, base: URL) {
        var sequence = 0
        var keyURL: URL?
        var keyMethod = "NONE"
        var iv: Data?
        var mapURL: URL?
        var pendingBandwidth: Int?
        var expectSegment = false

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                isMaster = true
                pendingBandwidth = Int(Self.attribute("BANDWIDTH", in: line) ?? "") ?? 0
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 6
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                sequence = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
            } else if line.hasPrefix("#EXT-X-KEY:") {
                keyMethod = Self.attribute("METHOD", in: line) ?? "NONE"
                keyURL = Self.attribute("URI", in: line).flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
                iv = Self.attribute("IV", in: line).flatMap(Self.hexData)
            } else if line.hasPrefix("#EXT-X-MAP:") {
                mapURL = Self.attribute("URI", in: line).flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                endList = true
            } else if line.hasPrefix("#EXTINF") {
                expectSegment = true
            } else if !line.hasPrefix("#") {
                guard let url = URL(string: line, relativeTo: base)?.absoluteURL else { continue }
                if let bandwidth = pendingBandwidth {
                    variants.append(Variant(url: url, bandwidth: bandwidth))
                    pendingBandwidth = nil
                } else if expectSegment || !isMaster {
                    segments.append(Segment(url: url, sequence: sequence, keyURL: keyURL, keyMethod: keyMethod, iv: iv, mapURL: mapURL))
                    sequence += 1
                    expectSegment = false
                }
            }
        }
    }

    /// Valeur d'un attribut (« BANDWIDTH=… », « URI="…" »).
    static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: name + "=") else { return nil }
        var rest = line[range.upperBound...]
        if rest.hasPrefix("\"") {
            rest = rest.dropFirst()
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
        return String(rest.prefix { $0 != "," })
    }

    static func hexData(_ text: String) -> Data? {
        var hex = text.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count % 2 == 0 else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

/// Copie un flux HLS segment par segment, en suivant la playlist du direct.
struct HLSRecorder {
    let playlistURL: URL
    let firstPlaylist: String
    let handle: FileHandle

    func run() async throws -> String {
        var mediaURL = playlistURL
        var playlist = HLSPlaylist(text: firstPlaylist, base: playlistURL)
        if playlist.isMaster {
            // Meilleure qualité disponible.
            guard let best = playlist.variants.max(by: { $0.bandwidth < $1.bandwidth }) else { throw RecordingError.nothingSaved }
            let (data, url) = try await RecordingEngine.fetch(best.url)
            mediaURL = url
            playlist = HLSPlaylist(text: String(decoding: data, as: UTF8.self), base: url)
        }

        var lastSequence: Int?
        var writtenMap: URL?
        var keys: [URL: Data] = [:]
        var ext = "ts"
        var failures = 0
        var first = true

        while !Task.isCancelled {
            var segments = playlist.segments
            // En direct, on démarre au bord du direct (les derniers segments), comme le lecteur.
            if first && !playlist.endList && segments.count > 3 { segments = Array(segments.suffix(3)) }
            first = false
            for segment in segments where lastSequence.map({ segment.sequence > $0 }) ?? true {
                try Task.checkCancellation()
                if let map = segment.mapURL, map != writtenMap {
                    let (data, _) = try await RecordingEngine.fetch(map)
                    try handle.write(contentsOf: data)
                    writtenMap = map
                    ext = "mp4"
                }
                var (data, _) = try await RecordingEngine.fetch(segment.url)
                if segment.keyMethod == "AES-128", let keyURL = segment.keyURL {
                    if keys[keyURL] == nil { keys[keyURL] = try await RecordingEngine.fetch(keyURL).0 }
                    if let key = keys[keyURL] {
                        let iv = segment.iv ?? Self.sequenceIV(segment.sequence)
                        data = Self.decrypt(data, key: key, iv: iv) ?? data
                    }
                }
                try handle.write(contentsOf: data)
                lastSequence = segment.sequence
            }
            if playlist.endList { break }
            try await Task.sleep(for: .seconds(max(1, playlist.targetDuration / 2)))
            do {
                let (data, url) = try await RecordingEngine.fetch(mediaURL)
                playlist = HLSPlaylist(text: String(decoding: data, as: UTF8.self), base: url)
                failures = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
                if failures >= 8 { throw error }
            }
        }
        return ext
    }

    static func sequenceIV(_ sequence: Int) -> Data {
        var iv = Data(repeating: 0, count: 16)
        var value = UInt64(sequence).bigEndian
        withUnsafeBytes(of: &value) { iv.replaceSubrange(8..<16, with: $0) }
        return iv
    }

    static func decrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else { return nil }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let outputCount = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                input.baseAddress, data.count, out.baseAddress, outputCount, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(written...)
        return output
    }
}
