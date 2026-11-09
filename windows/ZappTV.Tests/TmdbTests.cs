using System.Text.Json;
using ZappTV.Core;
using ZappTV.Core.Tmdb;

namespace ZappTV.Tests;

public class TitleCleanerTests
{
    [Theory]
    [InlineData("FR - Avatar (2009) [4K]", "Avatar", 2009)]
    [InlineData("|FR| Dune : Deuxième partie 2024", "Dune : Deuxième partie", 2024)]
    [InlineData("[VF] Inception MULTI 1080p", "Inception", null)]
    [InlineData("WALL-E", "WALL-E", null)]
    [InlineData("1917", "1917", null)]
    [InlineData("Breaking Bad S01 E02", "Breaking Bad", null)]
    [InlineData("EN: The.Matrix.1999", "The Matrix", 1999)]
    public void CleansPlaylistNames(string name, string title, int? year)
    {
        var (cleanTitle, cleanYear) = TitleCleaner.Clean(name);
        Assert.Equal(title, cleanTitle);
        Assert.Equal(year, cleanYear);
    }

    [Fact]
    public void KeyIgnoresAccentsCaseAndArticle()
    {
        Assert.Equal(TitleCleaner.Key("Amélie"), TitleCleaner.Key("AMELIE"));
        Assert.Equal("matrix", TitleCleaner.Key("The Matrix"));
        Assert.Equal("dune deuxieme partie", TitleCleaner.Key("Dune : Deuxième partie"));
    }
}

public class TmdbParsingTests
{
    [Fact]
    public void SearchPrefersExactTitle()
    {
        using var doc = JsonDocument.Parse("""
            {"results":[{"id":1,"title":"Avatar : La voie de l'eau"},{"id":19995,"title":"Avatar","original_title":"Avatar"}]}
            """);
        Assert.Equal(19995, TmdbClient.ParseSearch(doc.RootElement, "Avatar"));
        Assert.Equal(1, TmdbClient.ParseSearch(doc.RootElement, "Autre chose"));
    }

    [Fact]
    public void ParsesMovieDetails()
    {
        using var doc = JsonDocument.Parse("""
            {"id":19995,"title":"Avatar","original_title":"Avatar","release_date":"2009-12-15","vote_average":7.588,"vote_count":32000,
             "overview":"Malgré sa paralysie…","tagline":"Entrez dans le monde de Pandora.","runtime":162,
             "poster_path":"/p.jpg","backdrop_path":"/b.jpg","genres":[{"id":28,"name":"Action"},{"id":12,"name":"Aventure"}],
             "credits":{"cast":[{"name":"Sam Worthington","character":"Jake Sully","profile_path":"/s.jpg"}],
                        "crew":[{"job":"Producer","name":"X"},{"job":"Director","name":"James Cameron"}]},
             "videos":{"results":[{"site":"YouTube","type":"Teaser","key":"tease","iso_639_1":"en"},
                                  {"site":"YouTube","type":"Trailer","key":"frtrailer","iso_639_1":"fr","official":true}]},
             "images":{"logos":[{"file_path":"/en.png","iso_639_1":"en"},{"file_path":"/fr.png","iso_639_1":"fr"}]}}
            """);
        var info = TmdbClient.ParseDetails(doc.RootElement, TmdbKind.Movie);
        Assert.Equal("Avatar", info.Title);
        Assert.Null(info.OriginalTitle);
        Assert.Equal(2009, info.Year);
        Assert.Equal(7.6, info.Rating);
        Assert.Equal("2 h 42", info.Runtime);
        Assert.Equal(["Action", "Aventure"], info.Genres);
        Assert.Equal("James Cameron", info.Director);
        Assert.Equal("Jake Sully", info.Cast[0].Character);
        Assert.Equal("https://image.tmdb.org/t/p/w185/s.jpg", info.Cast[0].Photo);
        Assert.Equal("https://www.youtube.com/watch?v=frtrailer", info.TrailerUrl);
        Assert.Equal("https://image.tmdb.org/t/p/w500/fr.png", info.Logo);
        Assert.Equal("https://image.tmdb.org/t/p/w1280/b.jpg", info.Backdrop);
    }

    [Fact]
    public void ParsesSeriesDetails()
    {
        using var doc = JsonDocument.Parse("""
            {"id":1396,"name":"Breaking Bad","original_name":"Breaking Bad","first_air_date":"2008-01-20","number_of_seasons":5,
             "episode_run_time":[47],"created_by":[{"name":"Vince Gilligan"}],"vote_average":8.9}
            """);
        var info = TmdbClient.ParseDetails(doc.RootElement, TmdbKind.Tv);
        Assert.Equal(TmdbKind.Tv, info.Kind);
        Assert.Equal(5, info.Seasons);
        Assert.Equal("47 min", info.Runtime);
        Assert.Equal("Vince Gilligan", info.Director);
    }

    [Fact]
    public void ParsesTrendingAndSkipsPeople()
    {
        using var doc = JsonDocument.Parse("""
            {"results":[{"id":1,"media_type":"movie","title":"Film","release_date":"2026-10-01","backdrop_path":"/a.jpg","vote_average":7.2},
                        {"id":2,"media_type":"person","name":"Quelqu'un"},
                        {"id":3,"media_type":"tv","name":"Série","first_air_date":"2025-05-05"}]}
            """);
        var trends = TmdbClient.ParseTrending(doc.RootElement);
        Assert.Equal(2, trends.Count);
        Assert.Equal(TmdbKind.Tv, trends[1].Kind);
        Assert.Equal(2026, trends[0].Year);
    }

    [Fact]
    public async Task WithoutKeyFindsNothing()
    {
        var client = new TmdbClient("");
        Assert.Null(await client.FindAsync("Avatar", MediaKind.Movie));
    }
}
