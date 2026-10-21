import Foundation

public struct VodDetails: Sendable {
    public var plot = "", cast = "", director = "", genre = "", year = "", rating = "", duration = "", backdrop = "", poster = "", trailer = ""
    public var backdrops: [String] = []

    public init(plot: String = "", cast: String = "", director: String = "", genre: String = "", year: String = "", rating: String = "",
                duration: String = "", backdrop: String = "", poster: String = "", trailer: String = "", backdrops: [String] = []) {
        self.plot = plot; self.cast = cast; self.director = director; self.genre = genre; self.year = year; self.rating = rating
        self.duration = duration; self.backdrop = backdrop; self.poster = poster; self.trailer = trailer; self.backdrops = backdrops
    }
}

public struct EpisodeRow: Identifiable, Hashable, Sendable {
    public var id: String { rk }
    public let rk: String                // resume key
    public let xtreamId: String?         // Xtream episode id
    public let m3uIndex: Int?            // M3U series: index in the show's episode blob
    public let title: String
    public let plot: String
    public let image: String?
    public let duration: String
    public let ext: String
    public let number: Int
    public let season: Int
    public let src: Int
}

public struct SeasonInfo: Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let episodes: [EpisodeRow]
}

public struct SeriesDetails: Sendable {
    public var name = "", plot = "", cover = "", genre = "", year = "", rating = "", cast = "", director = "", backdrop = ""
    public var seasons: [SeasonInfo] = []
}

extension Backend {
    private static let xtreamLink = try! NSRegularExpression(pattern: "^(https?://[^/?#]+)(?:/[^?#]*)?/(?:get|playlist)\\.php\\?(.*)$", options: [.caseInsensitive])
    private static let movieId = try! NSRegularExpression(pattern: "/movie/[^/]+/[^/]+/(\\d+)\\.[A-Za-z0-9]+$")

    /// The Xtream account behind an M3U link ("…/get.php?username=…&password=…"): its film details (plot, backdrops, TMDB genres) can be used.
    public static func xtreamBehind(_ s: Source?) -> Source? {
        guard let s = s, s.type == .m3u else { return nil }
        let url = s.url.trimmed
        let ns = url as NSString
        guard let m = xtreamLink.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var user: String?, pass: String?
        for kv in ns.substring(with: m.range(at: 2)).split(separator: "&") {
            guard let e = kv.firstIndex(of: "="), e != kv.startIndex else { continue }
            let k = kv[kv.startIndex..<e].lowercased()
            let v = String(kv[kv.index(after: e)...]).removingPercentEncoding ?? String(kv[kv.index(after: e)...])
            if k == "username" { user = v } else if k == "password" { pass = v }
        }
        guard let u = user, let p = pass else { return nil }
        var x = s
        x.type = .xtream; x.url = ns.substring(with: m.range(at: 1)); x.user = u; x.pass = p
        return x
    }

    /// Xtream source and stream id to ask about a film, whether the list was added as Xtream or as an Xtream-made M3U link.
    func movieApi(_ it: Item) -> (Source, String)? {
        guard let s = lib.source(it.src), it.kind == .movie else { return nil }
        if s.type == .xtream { return it.sid.map { (s, $0) } }
        guard let x = Backend.xtreamBehind(s), let u = it.url else { return nil }
        let ns = u as NSString
        guard let m = Backend.movieId.firstMatch(in: u, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (x, ns.substring(with: m.range(at: 1)))
    }

    static func joinGenres(_ tmdbText: String?) -> String { Genres.parse(tmdbText).joined(separator: "|") }

    // MARK: film and series pages

    public func vodDetails(_ key: String) async -> VodDetails? {
        guard let it = lib.snap.byKey[key] else { return nil }
        if let c = detailCache.get(key) { return c }
        guard let s = lib.source(it.src) else { return nil }
        var r = VodDetails()
        do {
            if it.kind == .movie, let (api, sid) = movieApi(it) {
                let v = try await XtreamClient(api).vodInfo(sid)
                r = VodDetails(plot: v.plot, cast: v.cast, director: v.director, genre: v.genre, year: v.year, rating: v.rating, duration: v.duration,
                               backdrop: v.backdrop, poster: v.poster, trailer: v.trailer, backdrops: v.backdrops)
                genres.put(it.key, Backend.joinGenres(v.genre))
            } else if it.kind == .series, s.type == .xtream, let sid = it.sid {
                let si = try await seriesFor(it, XtreamClient(s), sid)
                r = VodDetails(plot: si.plot, cast: si.cast, director: si.director, genre: si.genre, year: si.year, rating: si.rating, duration: "",
                               backdrop: si.backdrop, poster: si.cover, trailer: si.trailer, backdrops: si.backdrops)
            } else { return nil }
        } catch { return nil }
        detailCache.put(key, r)
        return r
    }

    private func seriesFor(_ it: Item, _ x: XtreamClient, _ sid: String) async throws -> XtreamClient.SeriesInfo {
        if let c = seriesCache.get(it.key) { return c }
        let si = try await x.seriesInfo(sid)
        seriesCache.put(it.key, si)
        return si
    }

    public func clearDetailCaches() { detailCache.clear(); seriesCache.clear() }

    /// Stores the details of a title as if the provider had answered (demos and tests).
    public func primeDetails(_ key: String, _ d: VodDetails) { detailCache.put(key, d) }

    public func seriesDetails(_ key: String) async throws -> SeriesDetails {
        let sn = lib.snap
        guard let it = sn.byKey[key] else { throw BackendError.message("Serie non trovata") }
        let s = lib.source(it.src)
        var r = SeriesDetails()
        var bySeason: [Int: [EpisodeRow]] = [:]
        if let s = s, s.type == .xtream, let sid = it.sid {
            let si = try await seriesFor(it, XtreamClient(s), sid)
            r.name = it.name; r.plot = si.plot; r.cover = si.cover; r.genre = si.genre; r.year = si.year; r.rating = si.rating
            r.cast = si.cast; r.director = si.director; r.backdrop = si.backdrop
            for e in si.episodes {
                bySeason[e.season, default: []].append(EpisodeRow(
                    rk: "\(s.id):e:\(e.id)", xtreamId: e.id, m3uIndex: nil, title: e.title.isEmpty ? "Episodio \(e.episode)" : e.title, plot: e.plot,
                    image: e.image.isEmpty ? nil : e.image, duration: e.duration, ext: e.ext, number: e.episode, season: e.season, src: s.id))
            }
        } else {
            r.name = it.name; r.cover = it.logo ?? ""; r.genre = it.cat
            let eps = M3UParser.episodes(of: it)
            let order = eps.indices.sorted { eps[$0].season != eps[$1].season ? eps[$0].season < eps[$1].season : eps[$0].number < eps[$1].number }
            for i in order {
                let e = eps[i]
                bySeason[e.season, default: []].append(EpisodeRow(
                    rk: "\(it.key)#\(e.season)x\(e.number)", xtreamId: nil, m3uIndex: i, title: e.name, plot: "", image: it.logo, duration: "",
                    ext: "", number: e.number, season: e.season, src: it.src))
            }
        }
        r.seasons = bySeason.keys.sorted().map { SeasonInfo(number: $0, episodes: bySeason[$0]!) }
        return r
    }

    /// The address of one episode of a series page.
    public func resolveEpisode(_ ep: EpisodeRow, seriesKey: String) -> Play? {
        guard let s = lib.source(ep.src) else { return nil }
        var p = Play()
        p.ua = s.ua
        p.insecure = s.insecure
        if let id = ep.xtreamId {
            p.url = XtreamClient(s).episodeUrl(id, ext: ep.ext.isEmpty ? "mp4" : ep.ext)
            return p
        }
        if let i = ep.m3uIndex, let show = lib.snap.byKey[seriesKey] {
            let eps = M3UParser.episodes(of: show)
            if eps.indices.contains(i) { p.url = eps[i].url; return p }
        }
        return nil
    }

    // MARK: TMDB genres (background, gentle)

    /// Asks the provider for one film's details and remembers the genres TMDB gave it. Returns false when the provider failed (back off).
    public func fetchGenres(for key: String) async -> Bool {
        guard let it = lib.snap.byKey[key], let (api, sid) = movieApi(it) else { genres.put(key, ""); return true }
        do {
            let v = try await XtreamClient(api).vodInfo(sid)
            genres.put(key, Backend.joinGenres(v.genre))
            return true
        } catch { return false }
    }

    /// What the viewer is most likely to see first: recent, top rated, trending, then the first films of the first categories.
    public func genreCandidates(profile p: Profile) -> [String] {
        if p.movies.isEmpty { return [] }
        let sn = lib.snap
        let n = 80
        var recent = [Item](), top = [Item](), hot = [Item](), heads = [Item]()
        var perCat: [String: Int] = [:]
        let hotAfter = Int(Date().timeIntervalSince1970) - 45 * 86400
        for k in p.movies {
            guard let it = sn.byKey[k], !Hash.isSeparator(it.name) else { continue }
            if it.added > 0 { recent.append(it) }
            let r = Backend.rateOf(it)
            if r > 0 { top.append(it); if it.added > hotAfter && r >= 6 { hot.append(it) } }
            let c = perCat[it.cat] ?? (perCat.count >= 40 ? -1 : 0)
            if c < 0 { continue }
            if c < 12 { heads.append(it); perCat[it.cat] = c + 1 }
        }
        recent = Array(recent.sorted { $0.added > $1.added }.prefix(n))
        top = Array(top.sorted { Backend.rateOf($0) != Backend.rateOf($1) ? Backend.rateOf($0) > Backend.rateOf($1) : $0.added > $1.added }.prefix(n))
        hot = Array(hot.sorted { Backend.rateOf($0) > Backend.rateOf($1) }.prefix(n))
        var want: [String] = []
        var seen = Set<String>()
        for it in hot + recent + top + heads where seen.insert(it.key).inserted && genres.get(it.key) == nil { want.append(it.key) }
        return want
    }
}

/// A tiny thread-safe dictionary used as a cache.
final class SafeCache<V> {
    private var m: [String: V] = [:]
    private let lock = NSLock()
    func get(_ k: String) -> V? { lock.lock(); defer { lock.unlock() }; return m[k] }
    func put(_ k: String, _ v: V) { lock.lock(); m[k] = v; lock.unlock() }
    func clear() { lock.lock(); m.removeAll(); lock.unlock() }
}
