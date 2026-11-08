using ZappTV.Core;

namespace ZappTV.Tests;

public class M3UParserTests
{
    [Fact]
    public void ParsesAttributesAndTitle()
    {
        const string playlist = """
            #EXTM3U
            #EXTINF:-1 tvg-id="demo.one" tvg-name="Demo One" tvg-logo="https://example.com/one.png" group-title="Généralistes",Demo One, HD
            http://example.com/live/1.m3u8
            """;
        var items = M3UParser.Parse(playlist);

        var item = Assert.Single(items);
        Assert.Equal("Demo One, HD", item.Name);
        Assert.Equal("Généralistes", item.Group);
        Assert.Equal("demo.one", item.EpgId);
        Assert.Equal("https://example.com/one.png", item.LogoUrl);
        Assert.Equal(MediaKind.Live, item.Kind);
    }

    [Fact]
    public void CommaInsideQuotedAttribute()
    {
        var (attributes, title) = M3UParser.ParseExtinf("#EXTINF:-1 group-title=\"Films, Action\" tvg-logo=\"\",Mon Titre");
        Assert.Equal("Mon Titre", title);
        Assert.Equal("Films, Action", attributes["group-title"]);
    }

    [Fact]
    public void DetectsMoviesAndSeries()
    {
        const string playlist = """
            #EXTM3U
            #EXTINF:-1 group-title="VOD",Film
            http://example.com/movie/user/pass/10.mp4
            #EXTINF:-1 group-title="Séries",Episode 1
            http://example.com/series/user/pass/20.mkv
            #EXTINF:-1,Chaîne
            http://example.com/user/pass/30.ts
            """;
        var kinds = M3UParser.Parse(playlist).Select(i => i.Kind).ToArray();
        Assert.Equal(new[] { MediaKind.Movie, MediaKind.Series, MediaKind.Live }, kinds);
    }

    [Fact]
    public void ExtGrpAndEntryWithoutUrl()
    {
        const string playlist = """
            #EXTM3U
            #EXTINF:-1,Orpheline
            #EXTINF:-1,Sport 1
            #EXTGRP:Sport
            http://example.com/live/2.m3u8
            """;
        var item = Assert.Single(M3UParser.Parse(playlist));
        Assert.Equal("Sport 1", item.Name);
        Assert.Equal("Sport", item.Group);
    }

    [Fact]
    public void WindowsLineEndingsAndMissingGroup()
    {
        var item = Assert.Single(M3UParser.Parse("#EXTM3U\r\n#EXTINF:-1,Une chaîne\r\nhttp://example.com/a.m3u8\r\n"));
        Assert.Equal("Sans catégorie", item.Group);
    }

    [Fact]
    public void StableIds()
    {
        const string playlist = "#EXTINF:-1,A\nhttp://example.com/a.m3u8";
        Assert.Equal(M3UParser.Parse(playlist)[0].Id, M3UParser.Parse(playlist)[0].Id);
    }
}

public class XtreamTests
{
    [Theory]
    [InlineData("host.example:8080/", "http://host.example:8080")]
    [InlineData("https://host.example/player_api.php?username=a", "https://host.example")]
    public void ServerNormalization(string raw, string expected) =>
        Assert.Equal(expected, XtreamCredentials.NormalizeServer(raw));

    [Fact]
    public void EmptyServerIsRejected() => Assert.Null(XtreamCredentials.NormalizeServer("   "));

    [Fact]
    public void LenientJsonValues()
    {
        using var document = System.Text.Json.JsonDocument.Parse("""{"a":"12","b":1,"c":42,"d":"7,5","e":"","f":true}""");
        var root = document.RootElement;
        Assert.Equal(12, XJson.Int(root, "a"));
        Assert.Equal(1, XJson.Int(root, "b"));
        Assert.Equal("42", XJson.Str(root, "c"));
        Assert.Equal(7.5, XJson.Double(root, "d"));
        Assert.Null(XJson.Str(root, "e"));
        Assert.Equal(1, XJson.Int(root, "f"));
    }
}

public class LinkInspectorTests
{
    [Fact]
    public void NormalizeAddsSchemeAndRejectsGarbage()
    {
        Assert.Equal("http://example.com/live/a.m3u8", LinkInspector.Normalize("example.com/live/a.m3u8"));
        Assert.Equal("rtmp://example.com/app/stream", LinkInspector.Normalize("  rtmp://example.com/app/stream "));
        Assert.NotNull(LinkInspector.Normalize("udp://@239.0.0.1:1234"));
        Assert.Null(LinkInspector.Normalize(""));
        Assert.Null(LinkInspector.Normalize("javascript://alert(1)"));
    }

    [Theory]
    [InlineData("http://example.com/a.m3u8", StreamFormat.Hls)]
    [InlineData("http://example.com/a.ts", StreamFormat.MpegTs)]
    [InlineData("http://example.com/film.mkv", StreamFormat.Mkv)]
    [InlineData("rtsp://example.com/cam", StreamFormat.Rtsp)]
    [InlineData("rtmp://example.com/app/key", StreamFormat.Rtmp)]
    [InlineData("udp://@239.0.0.1:1234", StreamFormat.Udp)]
    [InlineData("http://example.com/play?type=m3u8", StreamFormat.Hls)]
    [InlineData("http://example.com/stream", StreamFormat.Unknown)]
    public void FormatDetection(string url, StreamFormat expected) =>
        Assert.Equal(expected, LinkInspector.Format(url));

    [Fact]
    public void PlaylistDetection()
    {
        Assert.True(LinkInspector.LooksLikePlaylist("http://example.com/list.m3u"));
        Assert.True(LinkInspector.LooksLikePlaylist("http://example.com/get.php?username=a&password=b&type=m3u_plus"));
        Assert.False(LinkInspector.LooksLikePlaylist("http://example.com/live/a.m3u8"));
    }
}

public class CustomizationTests
{
    private static readonly MediaItem Base = new()
    {
        Id = "a", Name = "Original", Group = "Groupe", Kind = MediaKind.Live,
        StreamUrl = "http://example.com/a.m3u8", LogoUrl = "https://example.com/a.png",
    };

    [Fact]
    public void OverrideAppliesNameGroupAndLogo()
    {
        var change = new ItemOverride { Name = "Renommée", Group = "Sport", LogoUrl = "https://example.com/b.png" };
        var result = change.Apply(Base);
        Assert.Equal("Renommée", result.Name);
        Assert.Equal("Sport", result.Group);
        Assert.Equal("https://example.com/b.png", result.LogoUrl);
        Assert.Equal(Base.Id, result.Id);
    }

    [Fact]
    public void BlankOverrideKeepsOriginal()
    {
        var change = new ItemOverride { Name = "   " };
        Assert.True(change.IsEmpty);
        Assert.Equal(Base, change.Apply(Base));
    }

    [Fact]
    public void RemoveLogo()
    {
        var change = new ItemOverride { RemoveLogo = true };
        Assert.Null(change.Apply(Base).LogoUrl);
        Assert.False(change.IsEmpty);
    }

    [Fact]
    public void CustomLinkBecomesMediaItem()
    {
        var link = new CustomLink { Name = "Ma chaîne", Url = "rtmp://example.com/app/key", Group = "  " };
        var item = link.ToMediaItem();
        Assert.True(item.IsCustomLink);
        Assert.Equal(CustomLink.DefaultGroup, item.Group);
        Assert.Equal(MediaKind.Live, item.Kind);
    }

    [Fact]
    public void TextHelpers()
    {
        Assert.Equal("Canal Démo", TextUtil.DisplayName("FR | Canal Démo"));
        Assert.Equal("CD", TextUtil.Initials("Canal Démo"));
        Assert.True(TextUtil.ContainsLoose("Télévision", "television"));
    }
}

public class LibraryTests
{
    [Fact]
    public void HiddenItemsAndOverridesAreApplied()
    {
        var library = new Library();
        var link = new CustomLink { Name = "Lien", Url = "http://example.com/a.m3u8" };
        var overrides = new Dictionary<string, ItemOverride>
        {
            [link.ItemId] = new ItemOverride { Group = "Sport" },
        };
        library.SetCustomization([link.ToMediaItem()], overrides);

        var item = Assert.Single(library.All(MediaKind.Live));
        Assert.Equal("Sport", item.Group);
        Assert.Equal(new[] { "Sport" }, library.Groups(MediaKind.Live));
        Assert.Equal("Mes liens", library.BaseItem(link.ItemId)!.Group);

        overrides[link.ItemId] = new ItemOverride { Hidden = true };
        library.SetCustomization([link.ToMediaItem()], overrides);
        Assert.Empty(library.Items);
        Assert.Single(library.HiddenItems);
    }

    [Fact]
    public async Task SearchIgnoresAccentsAndCase()
    {
        var library = new Library();
        library.SetCustomization(
            [new CustomLink { Name = "Télé Matin", Url = "http://example.com/a.m3u8" }.ToMediaItem()],
            new Dictionary<string, ItemOverride>());
        var results = await library.SearchAsync("tele");
        Assert.Single(results[MediaKind.Live]);
    }
}
