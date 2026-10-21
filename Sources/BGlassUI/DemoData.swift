import BGlassCore
import Foundation

/// A made-up library (fictional titles) used to preview the screens and to try the app with no provider at all.
public enum DemoData {
    private struct Lcg {
        var s: UInt64
        mutating func next(_ n: Int) -> Int {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Int((s >> 33) % UInt64(max(n, 1)))
        }
    }

    @MainActor
    public static func model(dir: URL) -> AppModel {
        let app = AppModel(dir: dir)
        let b = app.backend
        var s = Source()
        s.name = "Il mio provider"; s.type = .m3u; s.url = "http://demo.invalid/list.m3u"; s.nLive = 24; s.nMovies = 96; s.nSeries = 14
        s.expTs = Int64(Date().timeIntervalSince1970) + 9 * 86400; s.expires = "29/10/2026"; s.maxConn = "2"; s.activeConn = "0"
        s.updated = Int64(Date().timeIntervalSince1970 * 1000) - 3_600_000
        s = b.lib.addSource(s)
        var items: [Item] = []
        var rng = Lcg(s: 11)

        // live channels
        let channels: [(String, String)] = [
            ("Rai 1 HD", "Generalisti"), ("Rai 2 HD", "Generalisti"), ("Rai 3 HD", "Generalisti"), ("Rete 4 HD", "Generalisti"), ("Canale 5 HD", "Generalisti"),
            ("Italia 1 HD", "Generalisti"), ("La7 HD", "Generalisti"), ("TV8 HD", "Generalisti"), ("Nove HD", "Generalisti"),
            ("Sky Sport Uno HD", "Sport"), ("Sky Sport Calcio HD", "Sport"), ("Sky Sport Tennis HD", "Sport"), ("Eurosport 1 HD", "Sport"),
            ("Sky Cinema Uno HD", "Cinema"), ("Sky Cinema Azione HD", "Cinema"), ("Sky Atlantic HD", "Cinema"),
            ("Rai News 24", "News"), ("Sky TG24 HD", "News"), ("Cartoonito", "Bambini"), ("Boing", "Bambini"),
            ("Discovery Channel", "Documentari"), ("Real Time HD", "Documentari"), ("DMAX", "Documentari"), ("MTV", "Musica"),
        ]
        let shows = ["Telegiornale", "La vita in diretta", "Il commissario", "Serata di gala", "Notizie del mattino", "Documentario: il mare", "Film della sera", "Quiz show", "Sport live", "Il tempo"]
        var guide: [String: [Prog]] = [:]
        let now = Int64(Date().timeIntervalSince1970)
        let base = (now / 1800) * 1800
        for (i, (n, c)) in channels.enumerated() {
            let it = Item(src: s.id, kind: .live, key: "\(s.id):l:\(100 + i)", name: n, cat: c)
            it.sid = "\(100 + i)"
            it.epgId = "ch\(i).it"
            it.us = "http://demo.invalid/live/\(100 + i).m3u8"
            items.append(it)
            var t = base - 3600 - Int64(rng.next(1800))
            var progs: [Prog] = []
            while t < now + 8 * 3600 {
                let len = Int64(1800 + rng.next(4) * 1800)
                progs.append(Prog(t, t + len, shows[rng.next(shows.count)], "Una descrizione di esempio del programma."))
                t += len
            }
            guide["ch\(i).it"] = progs
        }
        b.epg.putSource(s.id, guide, names: [:])

        // films
        let adj = ["Ultimo", "Silenzioso", "Rosso", "Eterno", "Lontano", "Segreto", "Selvaggio", "Dorato", "Perduto", "Nero", "Fragile", "Veloce"]
        let noun = ["Orizzonte", "Viaggio", "Respiro", "Confine", "Giardino", "Inverno", "Ritorno", "Faro", "Deserto", "Signore", "Cielo", "Sentiero"]
        let cats = ["Azione", "Commedia", "Thriller", "Horror", "Fantascienza", "Animazione", "Documentari", "Film più visti", "Netflix 2025"]
        var used = Set<String>()
        var n = 0
        while n < 96 {
            let name = "\(noun[rng.next(noun.count)]) \(adj[rng.next(adj.count)])"
            if !used.insert(name).inserted { continue }
            let cat = n < 12 ? "Film più visti" : cats[rng.next(cats.count - 1)]
            let it = Item(src: s.id, kind: .movie, key: "\(s.id):m:\(500 + n)", name: "\(name) (\(1995 + rng.next(31)))", cat: cat)
            it.sid = "\(500 + n)"
            it.extra = String(format: "%.1f", 5.0 + Double(rng.next(45)) / 10)
            it.added = Int(now) - rng.next(120) * 86400
            it.us = "http://demo.invalid/movie/\(500 + n).mp4"
            items.append(it)
            n += 1
        }
        // series (each with a few episodes kept as an M3U blob)
        let serieNames = ["Le Luci di Marlow", "Dopo la Pioggia", "Il Quarto Piano", "Cronache dal Faro", "Oltre il Confine", "Casa Aurelio", "Frequenze", "Il Collezionista", "Terra Bruciata", "Nove Giorni", "Stazione Nord", "L'Isola", "Quel Giugno", "Specchi"]
        for (i, nm) in serieNames.enumerated() {
            let it = Item(src: s.id, kind: .series, key: "\(s.id):s:\(900 + i)", name: nm, cat: i < 5 ? "Serie più viste" : (i % 2 == 0 ? "Drammatico" : "Commedia"))
            it.sid = "\(900 + i)"
            it.extra = "\(2018 + i % 7)  \(String(format: "%.1f", 6.5 + Double(rng.next(25)) / 10))"
            it.added = Int(now) - rng.next(60) * 86400
            it.ub = "http://demo.invalid/series/\(900 + i)/"
            var blob = ""
            for season in 1...2 { for ep in 1...5 { blob += "\(season)\t\(ep)\tEpisodio \(ep) della stagione \(season)\t\(season)-\(ep).mp4\n" } }
            it.eps = blob
            items.append(it)
        }
        b.lib.replaceSource(s.id, items)

        // a profile with everything selected, one film and one series half way
        var p = b.profiles.create(name: "Bruno", color: 0)
        let pid = p.id
        b.profiles.update(pid) { prof in
            for it in items {
                switch it.kind {
                case .live: prof.live.insert(it.key)
                case .movie: prof.movies.insert(it.key)
                case .series: prof.series.insert(it.key)
                default: break
                }
            }
            prof.favs = [items[0].key, items[9].key]
            prof.resume["\(s.id):m:503"] = 2_400_000
            prof.done["\(s.id):m:503"] = 6_300_000
            prof.resumeAt["\(s.id):m:503"] = Profile.nowMillis() - 60_000
            prof.resume["\(s.id):s:900#1x3"] = 900_000
            prof.done["\(s.id):s:900#1x3"] = 2_700_000
            prof.resumeAt["\(s.id):s:900#1x3"] = Profile.nowMillis() - 600_000
            prof.resumeParent["\(s.id):s:900#1x3"] = "\(s.id):s:900"
            prof.resumeLabel["\(s.id):s:900#1x3"] = "S1 E3 · Episodio 3 della stagione 1"
        }
        b.profiles.create(name: "Giulia", color: 3)
        b.profiles.create(name: "Ospiti", color: 2, pin: "1234")
        p = b.profiles.get(pid) ?? p

        // what the provider would say about a film
        for it in items where it.kind == .movie {
            b.primeDetails(it.key, VodDetails(
                plot: "Un viaggio ai confini del mondo conosciuto: una squadra improbabile, un segreto custodito da decenni e una scelta che cambierà tutto. Una storia di amicizia, coraggio e seconde possibilità.",
                cast: "Marta Rinaldi, Paolo Ferretti, Elena Costa", director: "Luca Moretti", genre: "Azione, Avventura", year: "2024", rating: it.extra ?? "",
                duration: "1h 52m", backdrop: "", poster: "", trailer: "", backdrops: []))
            if let g = Genres.of(it.cat) { b.genres.put(it.key, g) }
        }
        app.enterDemo(p)
        return app
    }
}
