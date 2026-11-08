using System.Text.RegularExpressions;

namespace ZappTV.Core;

public enum StreamFormat { Hls, Dash, Mp4, Mov, MpegTs, Mkv, Avi, Flv, WebM, Audio, Rtmp, Rtsp, Udp, Mms, Unknown }

public static partial class LinkInspector
{
    public static readonly HashSet<string> SupportedSchemes =
    [
        "http", "https", "rtmp", "rtmps", "rtmpt", "rtmpe", "rtsp", "rtsps",
        "rtp", "udp", "srt", "mms", "mmsh", "mmst", "ftp", "smb", "file",
    ];

    [GeneratedRegex("^([a-zA-Z][a-zA-Z0-9+.-]*)://(.+)$")]
    private static partial Regex SchemeRegex();

    public static string Label(this StreamFormat format) => format switch
    {
        StreamFormat.Hls => "HLS",
        StreamFormat.Dash => "DASH",
        StreamFormat.Mp4 => "MP4",
        StreamFormat.Mov => "MOV",
        StreamFormat.MpegTs => "MPEG-TS",
        StreamFormat.Mkv => "MKV",
        StreamFormat.Avi => "AVI",
        StreamFormat.Flv => "FLV",
        StreamFormat.WebM => "WebM",
        StreamFormat.Audio => "Audio",
        StreamFormat.Rtmp => "RTMP",
        StreamFormat.Rtsp => "RTSP",
        StreamFormat.Udp => "UDP / RTP",
        StreamFormat.Mms => "MMS",
        _ => "Flux",
    };

    /// <summary>Ajoute http:// si besoin et vérifie que le protocole est lisible. Renvoie null sinon.</summary>
    public static string? Normalize(string? raw)
    {
        var value = raw?.Trim() ?? "";
        if (value.Length == 0) return null;
        value = value.Replace(" ", "%20");
        if (!value.Contains("://", StringComparison.Ordinal)) value = "http://" + value;

        var match = SchemeRegex().Match(value);
        if (!match.Success) return null;
        var scheme = match.Groups[1].Value.ToLowerInvariant();
        if (!SupportedSchemes.Contains(scheme)) return null;

        if (scheme.StartsWith("http", StringComparison.Ordinal)
            && (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || string.IsNullOrEmpty(uri.Host)))
        {
            return null;
        }
        return value;
    }

    public static StreamFormat Format(string url)
    {
        var match = SchemeRegex().Match(url);
        var scheme = match.Success ? match.Groups[1].Value.ToLowerInvariant() : "";
        if (scheme.StartsWith("rtmp", StringComparison.Ordinal)) return StreamFormat.Rtmp;
        if (scheme.StartsWith("rtsp", StringComparison.Ordinal)) return StreamFormat.Rtsp;
        if (scheme is "udp" or "rtp" or "srt") return StreamFormat.Udp;
        if (scheme.StartsWith("mms", StringComparison.Ordinal)) return StreamFormat.Mms;

        string path = "", query = "";
        if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            path = uri.AbsolutePath.ToLowerInvariant();
            query = uri.Query.ToLowerInvariant();
        }

        return Path.GetExtension(path).TrimStart('.') switch
        {
            "m3u8" => StreamFormat.Hls,
            "mpd" => StreamFormat.Dash,
            "mp4" or "m4v" => StreamFormat.Mp4,
            "mov" => StreamFormat.Mov,
            "ts" or "m2ts" or "mts" => StreamFormat.MpegTs,
            "mkv" => StreamFormat.Mkv,
            "avi" => StreamFormat.Avi,
            "flv" => StreamFormat.Flv,
            "webm" => StreamFormat.WebM,
            "mp3" or "aac" or "m4a" => StreamFormat.Audio,
            _ => query.Contains("m3u8") || path.Contains("/hls/") ? StreamFormat.Hls : StreamFormat.Unknown,
        };
    }

    /// <summary>Lien vers une playlist complète plutôt que vers un seul flux.</summary>
    public static bool LooksLikePlaylist(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        var path = uri.AbsolutePath.ToLowerInvariant();
        if (path.EndsWith(".m3u", StringComparison.Ordinal)) return true;
        return path.EndsWith("get.php", StringComparison.Ordinal)
            && uri.Query.Contains("type=m3u", StringComparison.OrdinalIgnoreCase);
    }

    public static MediaKind GuessKind(string url)
    {
        var kind = M3UParser.DetectKind(url);
        return kind == MediaKind.Series ? MediaKind.Movie : kind;
    }
}
