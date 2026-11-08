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
