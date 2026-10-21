import Foundation

/// Turns the category names of any provider ("Azione", "Action | 4K", "Film Commedia", "Sci-Fi") into one genre name, so categories that
/// mean the same thing become one row and the rows come in a sensible order. Only a category that is *just* a genre is merged:
/// "Commedia Italiana" or "Netflix Film" stay what they are. Works with Italian, English, Spanish, French and German names.
public enum Genres {
    /// Display names in the order the rows are shown.
    public static let order = [
        "Azione", "Avventura", "Commedia", "Drammatico", "Thriller", "Horror", "Fantascienza", "Fantasy", "Animazione", "Anime",
        "Famiglia", "Romantico", "Crime", "Mistero", "Documentari", "Guerra", "Western", "Musicale", "Biografico", "Storico", "Sport",
    ]

    private static let word: [String: String] = {
        var m: [String: String] = [:]
        func add(_ genre: String, _ words: String...) { for w in words { m[w] = genre } }
        add("Azione", "azione", "action", "accion", "aktion", "acao")
        add("Avventura", "avventura", "avventure", "adventure", "aventura", "aventure", "abenteuer")
        add("Commedia", "commedia", "commedie", "comedy", "comedia", "comedie", "komodie", "comedias")
        add("Drammatico", "drammatico", "dramma", "drammatici", "drama", "drame", "dramas")
        add("Thriller", "thriller", "suspense", "suspence")
        add("Horror", "horror", "terror", "orrore", "paura", "horreur")
        add("Fantascienza", "fantascienza", "scifi", "sci-fi", "sciencefiction", "fiction")
        add("Fantasy", "fantasy", "fantastico")
        add("Animazione", "animazione", "animation", "animacion", "animated", "cartoni", "cartoon", "cartoons", "animati")
        add("Anime", "anime", "manga")
        add("Famiglia", "famiglia", "family", "familia", "famille", "familie", "kids", "bambini", "ragazzi")
        add("Romantico", "romantico", "romance", "romantic", "sentimentale", "romantica")
        add("Crime", "crime", "crimine", "poliziesco", "giallo", "noir", "krimi", "policial", "criminal")
        add("Mistero", "mistero", "mystery", "misterio")
        add("Documentari", "documentario", "documentari", "documentary", "documentaries", "documental", "doc")
        add("Guerra", "guerra", "war", "guerre", "krieg")
        add("Western", "western")
        add("Musicale", "musical", "musicale", "musica", "music")
        add("Biografico", "biografico", "biografia", "biography", "biopic", "biografie")
        add("Storico", "storico", "storia", "history", "historical", "historia")
        add("Sport", "sport", "sports", "sportivo")
        return m
    }()

    private static let filler: Set<String> = [
        "film", "films", "movie", "movies", "serie", "series", "tv", "4k", "uhd", "fhd", "hd", "sd", "it", "ita", "italia",
        "vod", "peliculas", "filme", "di", "e", "and", "the", "de", "del", "la", "el", "les", "des", "der", "die", "das", "du", "da", "do",
        "category", "categoria", "multi",
    ]

    /// Lower case, accents removed.
    static func plain(_ s: String) -> String {
        var out = ""
        for u in s.decomposedStringWithCanonicalMapping.unicodeScalars where u.properties.generalCategory != .nonspacingMark {
            out += lowerScalar(u)
        }
        return out
    }

    /// The genre this category is called, or nil when it is something else (a platform, a year, a mix, a country...).
    public static func of(_ category: String?) -> String? {
        guard let category = category else { return nil }
        let s = plain(category)
        var words: [String] = []
        var w = ""
        for u in s.unicodeScalars {
            if isLetterOrDigit(u) || u == "-" { w.unicodeScalars.append(u); continue }
            if !w.isEmpty { words.append(w); w = "" }
        }
        if !w.isEmpty { words.append(w) }
        var genre: String?
        for x in words {
            if filler.contains(x) { continue }
            guard let g = word[x] else {
                if x == "sci" || x == "science" || x == "ciencia" {
                    if let cur = genre, cur != "Fantascienza" { return nil }
                    genre = "Fantascienza"
                    continue
                }
                return nil                                    // an unknown word: not a plain genre
            }
            if let cur = genre, cur != g { return nil }       // "Azione e Avventura": a mix, keep it as it is
            genre = g
        }
        return genre
    }

    private static let andPattern = try! NSRegularExpression(pattern: "\\s+(?:&|e|and|y|und|et)\\s+|\\s*&\\s*", options: [])

    /// The genres of a film as TMDB writes them ("Azione, Avventura, Fantascienza", "Science Fiction", "Sci-Fi & Fantasy"), as our genre
    /// names, main genre first, at most four. Anything that is not a genre ("Film TV") is dropped.
    public static func parse(_ text: String?) -> [String] {
        guard let text = text else { return [] }
        var out: [String] = []
        for part in text.split(whereSeparator: { ",/|;".contains($0) }) {
            let p = String(part)
            let marked = andPattern.stringByReplacingMatches(in: p, options: [], range: NSRange(location: 0, length: (p as NSString).length), withTemplate: "\u{0}")
            for tok in marked.split(separator: "\u{0}") {
                let t = String(tok).trimmed
                if t.isEmpty { continue }
                var g = of(t)
                if g == nil {
                    let pl = plain(t).replacingOccurrences(of: " ", with: "")
                    if pl == "sciencefiction" || pl == "scifi" || pl == "scifi&fantasy" { g = "Fantascienza" }
                }
                if let g = g, !out.contains(g), out.count < 4 { out.append(g) }
            }
        }
        return out
    }

    private static let adultLock = NSLock()
    private static var adultCache: [String: Bool] = [:]

    /// Categories for adults only ("XXX Amateur", "Adult 18+", "Porn", "Erotic"): hidden unless the viewer switches them on.
    public static func isAdult(_ category: String?) -> Bool {
        guard let category = category, !category.isEmpty else { return false }
        adultLock.lock()
        if let b = adultCache[category] { adultLock.unlock(); return b }
        adultLock.unlock()
        var s = " "
        var lastSpace = true
        for u in plain(category).unicodeScalars {
            let v = u.value
            if (v >= 97 && v <= 122) || (v >= 48 && v <= 57) || u == "+" { s.unicodeScalars.append(u); lastSpace = false }
            else if !lastSpace { s += " "; lastSpace = true }
        }
        if !lastSpace { s += " " }
        let a = s.contains(" xxx") || s.contains("porn") || s.contains(" 18+") || s.contains("18 +") || s.contains(" adult") || s.contains(" adulti ")
            || s.contains("erotic") || s.contains("hentai") || s.contains(" sex ") || s.contains(" hard ")
        adultLock.lock()
        if adultCache.count < 20000 { adultCache[category] = a }
        adultLock.unlock()
        return a
    }

    /// Position of a genre in `order` (unknown = last).
    public static func rank(_ genre: String) -> Int { order.firstIndex(of: genre) ?? order.count }

    /// Categories that hold what is popular right now: kept whole and shown first.
    public static func isTrending(_ category: String?) -> Bool {
        guard let category = category else { return false }
        let s = plain(category)
        let keys = ["trend", "tendenz", "popular", "piu visti", "most watched", "top 10", "top10", "top 20", "oggi al cinema",
                    "in sala", "box office", "novita", "nuovi", "new release", "latest", "recenti", "ultime uscite", "piu votati", "top rated"]
        for k in keys where s.contains(k) { return true }
        return false
    }
}
