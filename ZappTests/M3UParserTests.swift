import XCTest
@testable import Zapp

final class M3UParserTests: XCTestCase {
    func testParsesAttributesAndTitle() {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="demo.one" tvg-name="Demo One" tvg-logo="https://example.com/one.png" group-title="Généralistes",Demo One, HD
        http://example.com/live/1.m3u8
        """
        let items = M3UParser.parse(playlist)

        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.name, "Demo One, HD")
        XCTAssertEqual(item.group, "Généralistes")
        XCTAssertEqual(item.epgID, "demo.one")
        XCTAssertEqual(item.logoURL?.absoluteString, "https://example.com/one.png")
        XCTAssertEqual(item.kind, .live)
    }

    func testCommaInsideQuotedAttribute() {
        let line = #"#EXTINF:-1 group-title="Films, Action" tvg-logo="",Mon Titre"#
        let parsed = M3UParser.parseExtinf(line)
        XCTAssertEqual(parsed.title, "Mon Titre")
        XCTAssertEqual(parsed.attributes["group-title"], "Films, Action")
    }

    func testDetectsMoviesAndSeries() {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 group-title="VOD",Film
        http://example.com/movie/user/pass/10.mp4
        #EXTINF:-1 group-title="Séries",Episode 1
        http://example.com/series/user/pass/20.mkv
        #EXTINF:-1,Chaîne
        http://example.com/user/pass/30.ts
        """
        let kinds = M3UParser.parse(playlist).map(\.kind)
        XCTAssertEqual(kinds, [.movie, .series, .live])
    }

    func testExtGrpAndEntryWithoutURL() {
        let playlist = """
        #EXTM3U
        #EXTINF:-1,Orpheline
        #EXTINF:-1,Sport 1
        #EXTGRP:Sport
        http://example.com/live/2.m3u8
        """
        let items = M3UParser.parse(playlist)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Sport 1")
        XCTAssertEqual(items.first?.group, "Sport")
    }

    func testWindowsLineEndingsAndMissingGroup() {
        let playlist = "#EXTM3U\r\n#EXTINF:-1,Une chaîne\r\nhttp://example.com/a.m3u8\r\n"
        let items = M3UParser.parse(playlist)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.group, "Sans catégorie")
    }

    func testStableIDs() {
        let playlist = "#EXTINF:-1,A\nhttp://example.com/a.m3u8"
        XCTAssertEqual(M3UParser.parse(playlist).first?.id, M3UParser.parse(playlist).first?.id)
    }
}

final class XtreamTests: XCTestCase {
    func testServerNormalization() {
        XCTAssertEqual(XtreamCredentials.normalizedServer("host.example:8080/")?.absoluteString,
                       "http://host.example:8080")
        XCTAssertEqual(XtreamCredentials.normalizedServer("https://host.example/player_api.php?username=a")?.absoluteString,
                       "https://host.example")
        XCTAssertNil(XtreamCredentials.normalizedServer("   "))
    }

    func testLenientJSONValues() {
        XCTAssertEqual(JSONValue.int("12"), 12)
        XCTAssertEqual(JSONValue.int(NSNumber(value: 1)), 1)
        XCTAssertEqual(JSONValue.string(NSNumber(value: 42)), "42")
        XCTAssertEqual(JSONValue.double("7,5"), 7.5)
        XCTAssertNil(JSONValue.string(""))
    }
}

final class MediaItemTests: XCTestCase {
    func testDisplayNameAndInitials() {
        let item = MediaItem(id: "1", name: "FR | Canal Démo", group: "FR", kind: .live)
        XCTAssertEqual(item.displayName, "Canal Démo")
        XCTAssertEqual(item.initials, "CD")
    }
}

final class LinkInspectorTests: XCTestCase {
    func testNormalizeAddsSchemeAndRejectsGarbage() {
        XCTAssertEqual(LinkInspector.normalize("example.com/live/a.m3u8")?.absoluteString,
                       "http://example.com/live/a.m3u8")
        XCTAssertEqual(LinkInspector.normalize("  rtmp://example.com/app/stream ")?.scheme, "rtmp")
        XCTAssertNotNil(LinkInspector.normalize("udp://@239.0.0.1:1234"))
        XCTAssertNil(LinkInspector.normalize(""))
        XCTAssertNil(LinkInspector.normalize("javascript://alert(1)"))
    }

    func testFormatDetection() {
        func format(_ string: String) -> StreamFormat {
            LinkInspector.format(of: URL(string: string)!)
        }
        XCTAssertEqual(format("http://example.com/a.m3u8"), .hls)
        XCTAssertEqual(format("http://example.com/a.ts"), .mpegTS)
        XCTAssertEqual(format("http://example.com/film.mkv"), .mkv)
        XCTAssertEqual(format("rtsp://example.com/cam"), .rtsp)
        XCTAssertEqual(format("rtmp://example.com/app/key"), .rtmp)
        XCTAssertEqual(format("udp://@239.0.0.1:1234"), .udp)
        XCTAssertEqual(format("http://example.com/play?type=m3u8"), .hls)
        XCTAssertEqual(format("http://example.com/stream"), .unknown)
    }

    func testPlaylistDetection() {
        XCTAssertTrue(LinkInspector.looksLikePlaylist(URL(string: "http://example.com/list.m3u")!))
        XCTAssertTrue(LinkInspector.looksLikePlaylist(URL(string: "http://example.com/get.php?username=a&password=b&type=m3u_plus")!))
        XCTAssertFalse(LinkInspector.looksLikePlaylist(URL(string: "http://example.com/live/a.m3u8")!))
    }

    func testNativeFormats() {
        XCTAssertTrue(StreamFormat.hls.isNativeOnIOS)
        XCTAssertTrue(StreamFormat.mp4.isNativeOnIOS)
        XCTAssertFalse(StreamFormat.mkv.isNativeOnIOS)
        XCTAssertFalse(StreamFormat.rtmp.isNativeOnIOS)
    }
}

final class CustomizationTests: XCTestCase {
    private let base = MediaItem(id: "a", name: "Original", group: "Groupe", kind: .live,
                                 streamURL: URL(string: "http://example.com/a.m3u8"),
                                 logoURL: URL(string: "https://example.com/a.png"))

    func testOverrideAppliesNameGroupAndLogo() {
        var change = ItemOverride()
        change.name = "Renommée"
        change.group = "Sport"
        change.logoURL = URL(string: "https://example.com/b.png")
        let result = change.applied(to: base)
        XCTAssertEqual(result.name, "Renommée")
        XCTAssertEqual(result.group, "Sport")
        XCTAssertEqual(result.logoURL?.absoluteString, "https://example.com/b.png")
        XCTAssertEqual(result.id, base.id)
    }

    func testBlankOverrideKeepsOriginal() {
        var change = ItemOverride()
        change.name = "   "
        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(change.applied(to: base), base)
    }

    func testRemoveLogo() {
        var change = ItemOverride()
        change.removeLogo = true
        XCTAssertNil(change.applied(to: base).logoURL)
        XCTAssertFalse(change.isEmpty)
    }

    func testCustomLinkBecomesMediaItem() {
        let link = CustomLink(name: "Ma chaîne", url: URL(string: "rtmp://example.com/app/key")!, group: "  ")
        let item = link.mediaItem
        XCTAssertTrue(item.isCustomLink)
        XCTAssertEqual(item.group, CustomLink.defaultGroup)
        XCTAssertEqual(item.kind, .live)
        XCTAssertEqual(item.streamURL?.scheme, "rtmp")
    }
}
