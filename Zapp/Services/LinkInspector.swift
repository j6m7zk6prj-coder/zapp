import Foundation

enum StreamFormat: String, Sendable {
    case hls = "HLS"
    case dash = "DASH"
    case mp4 = "MP4"
    case mov = "MOV"
    case mpegTS = "MPEG-TS"
    case mkv = "MKV"
    case avi = "AVI"
    case flv = "FLV"
    case webm = "WebM"
    case audio = "Audio"
    case rtmp = "RTMP"
    case rtsp = "RTSP"
    case udp = "UDP / RTP"
    case mms = "MMS"
    case unknown = "Flux"

    /// Formats que le lecteur intégré d'iOS sait lire.
    var isNativeOnIOS: Bool {
        switch self {
        case .hls, .mp4, .mov, .audio: return true
        default: return false
        }
    }
}

/// Analyse un lien collé par l'utilisateur.
enum LinkInspector {
    static let supportedSchemes: Set<String> = [
        "http", "https", "rtmp", "rtmps", "rtmpt", "rtmpe", "rtsp", "rtsps",
        "rtp", "udp", "srt", "mms", "mmsh", "mmst", "ftp", "smb", "file",
    ]

    /// Ajoute http:// si besoin et vérifie que le protocole est lisible.
    static func normalize(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: " ", with: "%20")
        if !value.contains("://") { value = "http://" + value }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              supportedSchemes.contains(scheme) else { return nil }
        if scheme.hasPrefix("http"), url.host == nil { return nil }
        return url
    }

    static func format(of url: URL) -> StreamFormat {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme.hasPrefix("rtmp") { return .rtmp }
        if scheme.hasPrefix("rtsp") { return .rtsp }
        if scheme == "udp" || scheme == "rtp" || scheme == "srt" { return .udp }
        if scheme.hasPrefix("mms") { return .mms }

        switch url.pathExtension.lowercased() {
        case "m3u8": return .hls
        case "mpd": return .dash
        case "mp4", "m4v": return .mp4
        case "mov": return .mov
        case "ts", "m2ts", "mts": return .mpegTS
        case "mkv": return .mkv
        case "avi": return .avi
        case "flv": return .flv
        case "webm": return .webm
        case "mp3", "aac", "m4a": return .audio
        default:
            let query = url.query?.lowercased() ?? ""
            if query.contains("m3u8") || url.path.lowercased().contains("/hls/") { return .hls }
            return .unknown
        }
    }

    /// Lien vers une playlist complète plutôt que vers un seul flux.
    static func looksLikePlaylist(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "m3u" { return true }
        let query = url.query?.lowercased() ?? ""
        return url.path.lowercased().hasSuffix("get.php") && query.contains("type=m3u")
    }

    static func guessKind(_ url: URL) -> MediaKind {
        let kind = M3UParser.detectKind(url: url)
        return kind == .series ? .movie : kind
    }
}

enum PlaybackEngine: String, CaseIterable, Identifiable, Sendable {
    case auto, native, vlc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatique"
        case .native: return "Lecteur iOS"
        case .vlc: return "VLC"
        }
    }

    var explanation: String {
        switch self {
        case .auto:
            return "HLS et MP4 avec le lecteur iOS (AirPlay, Picture in Picture), tout le reste avec VLC. Si le lecteur iOS échoue, VLC prend le relais."
        case .native:
            return "Toujours le lecteur iOS : AirPlay et Picture in Picture, mais seulement HLS et MP4."
        case .vlc:
            return "Toujours VLC : lit tous les formats (TS, MKV, RTMP, RTSP, UDP…)."
        }
    }
}

enum PlaybackSupport {
    static let vlcAvailable: Bool = {
        #if canImport(MobileVLCKit)
        return true
        #else
        return false
        #endif
    }()

    static func usesVLC(_ url: URL, preference: PlaybackEngine) -> Bool {
        guard vlcAvailable else { return false }
        switch preference {
        case .native:
            return false
        case .vlc:
            return true
        case .auto:
            let scheme = url.scheme?.lowercased() ?? ""
            guard scheme == "http" || scheme == "https" || scheme == "file" else { return true }
            let format = LinkInspector.format(of: url)
            // Format inconnu en http : on tente iOS d'abord, VLC prend le relais en cas d'échec.
            return !(format.isNativeOnIOS || format == .unknown)
        }
    }

    static func engineLabel(for url: URL, preference: PlaybackEngine) -> String {
        usesVLC(url, preference: preference) ? "VLC" : "Lecteur iOS"
    }
}
