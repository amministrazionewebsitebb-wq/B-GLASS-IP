@testable import BGlassCore
import Foundation

func runGenresChecks(_ h: Harness) {
    h.suite("genres: plain genres in several languages") {
        h.equal(Genres.of("Azione"), "Azione")
        h.equal(Genres.of("Action | 4K"), "Azione")
        h.equal(Genres.of("FILM AZIONE"), "Azione")
        h.equal(Genres.of("IT: Commedia HD"), "Commedia")
        h.equal(Genres.of("Dramma"), "Drammatico")
        h.equal(Genres.of("Sci-Fi"), "Fantascienza")
        h.equal(Genres.of("Science Fiction"), "Fantascienza")
        h.equal(Genres.of("Serie Animazione"), "Animazione")
        h.equal(Genres.of("Películas de Terror"), "Horror")
        h.equal(Genres.of("Thriller"), "Thriller")
        h.equal(Genres.of("Documentary"), "Documentari")
    }
    h.suite("genres: mixes, platforms and years are left alone") {
        h.isNil(Genres.of("Commedia Italiana"))
        h.isNil(Genres.of("Netflix Film"))
        h.isNil(Genres.of("Anno 2024"))
        h.isNil(Genres.of("Azione e Avventura"))
        h.isNil(Genres.of("Disney+"))
        h.isNil(Genres.of("4K"))
        h.isNil(Genres.of("Video Musicali - Concerti"))
        h.isNil(Genres.of(nil))
    }
    h.suite("genres: trending and order") {
        h.check(Genres.isTrending("Film più visti ultima settimana"))
        h.check(Genres.isTrending("Film piu visti ultima settimana"))
        h.check(Genres.isTrending("Oggi al Cinema"))
        h.check(Genres.isTrending("Recenti: 2025-2026"))
        h.check(Genres.isTrending("Top 10 Italia"))
        h.check(Genres.isTrending("Film più votati"), "accented 'più votati' must count")
        h.check(!Genres.isTrending("Azione"))
        h.check(Genres.rank("Azione") < Genres.rank("Commedia"))
        h.check(Genres.rank("Commedia") < Genres.rank("Horror"))
        h.equal(Genres.rank("Sconosciuto"), Genres.order.count)
    }
    h.suite("genres: TMDB text") {
        h.equal(Genres.parse("Azione, Avventura, Fantascienza"), ["Azione", "Avventura", "Fantascienza"])
        h.equal(Genres.parse("Action & Adventure"), ["Azione", "Avventura"])
        h.equal(Genres.parse("Sci-Fi & Fantasy"), ["Fantascienza", "Fantasy"])
        h.equal(Genres.parse("Science Fiction, Thriller"), ["Fantascienza", "Thriller"])
        h.equal(Genres.parse("Dramma / Storia / Musica"), ["Drammatico", "Storico", "Musicale"])
        h.equal(Genres.parse("Romantico, Commedia, Film TV"), ["Romantico", "Commedia"])
        h.check(Genres.parse("Film TV").isEmpty)
        h.check(Genres.parse("").isEmpty)
        h.check(Genres.parse(nil).isEmpty)
        h.equal(Genres.parse("Azione, Avventura, Commedia, Drammatico, Thriller, Horror").count, 4)
    }
    h.suite("genres: adult categories") {
        h.check(Genres.isAdult("XXX Amateur"))
        h.check(Genres.isAdult("XXX 4K"))
        h.check(Genres.isAdult("Adult 18+"))
        h.check(Genres.isAdult("|IT| PORN"))
        h.check(Genres.isAdult("Film Erotici"))
        h.check(!Genres.isAdult("Commedia"))
        h.check(!Genres.isAdult("Sport - UFC"))
        h.check(!Genres.isAdult("Anni '90"))
        h.check(!Genres.isAdult("Essex Docs"))
        h.check(!Genres.isAdult(nil))
    }
}
