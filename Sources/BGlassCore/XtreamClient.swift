import Foundation

/// Xtream Codes "player_api.php" client.
public final class XtreamClient {
    public struct Account {
        public var ok = false
        public var status = ""
        public var expires = ""
        public var expTs: Int64 = 0
        public var maxConn = ""
        public var activeConn = ""
        public var message = ""
        public var hls = false
    }

    public struct Episode {
        public var id = "", title = "", ext = "", plot = "", image = "", duration = ""
        public var season = 0, episode = 0
    }

    public struct SeriesInfo {
        public var name = "", plot = "", cover = "", genre = "", year = "", rating = "", cast = "", director = "", backdrop = "", trailer = ""
        public var backdrops: [String] = []
        public var episodes: [Episode] = []
    }

    public struct VodInfo {
        public var plot = "", cast = "", director = "", genre = "", year = "", rating = "", duration = "", backdrop = "", poster = "", trailer = ""
        public var backdrops: [String] = []
    }

    public struct Prog {
        public var start: Int64 = 0, end: Int64 = 0
        public var title = "", desc = ""
    }

    private let s: Source
    public let base: String

    public init(_ s: Source) {
        self.s = s
        self.base = XtreamClient.normalizeBase(s.url)
    }

    // MARK: addresses

    /// "host:port", "http://host/get.php?..." or "http://host:80/c/" -> "http://host:80".
    public static func normalizeBase(_ input: String?) -> String {
        guard var t = input?.trimmed, !t.isEmpty else { return "" }
        if !t.contains("://") { t = "http://" + t }
        guard let u = URLComponents(string: t), let scheme = u.scheme?.lowercased(), let host = u.host?.lowercased(), !host.isEmpty else {
            var r = t
            while r.hasSuffix("/") { r.removeLast() }
            return r
        }
        var sb = "\(scheme)://\(host)"
        let explicit = u.port
        let port = explicit ?? (scheme == "https" ? 443 : 80)
        let isDefault = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        if !isDefault || explicit != nil { sb += ":\(port)" }
        let stop: Set<String> = ["c", "player_api.php", "get.php", "xmltv.php", "portal.php", "panel_api.php", "live", "movie", "series"]
        var path = ""
        for seg in u.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
            if seg.isEmpty || stop.contains(seg.lowercased()) { break }
            path += "/" + seg
        }
        return sb + path
    }

    /// Detects an Xtream "get.php?username=..&password=.." style M3U link. Returns (base, user, pass) or nil.
    public static func fromGetPhp(_ url: String?) -> (base: String, user: String, pass: String)? {
        guard let raw = url?.trimmed, !raw.isEmpty,
              let u = URLComponents(string: raw.contains("://") ? raw : "http://" + raw) else { return nil }
        guard let user = u.queryItems?.first(where: { $0.name == "username" })?.value,
              let pass = u.queryItems?.first(where: { $0.name == "password" })?.value else { return nil }
        let last = u.path.split(separator: "/").last.map { $0.lowercased() } ?? ""
        guard ["get.php", "playlist.php", "player_api.php", "xmltv.php"].contains(last) else { return nil }
        return (normalizeBase(raw), user, pass)
    }

    /// application/x-www-form-urlencoded style, what the panels expect for credentials.
    static func enc(_ v: String) -> String {
        var out = ""
        for b in v.utf8 {
            switch b {
            case 48...57, 65...90, 97...122, 46, 45, 42, 95: out.append(Character(Unicode.Scalar(b)))
            case 32: out.append("+")
            default: out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    private func api(_ action: String?, _ extra: String? = nil) -> String {
        var sb = base + "/player_api.php?username=" + XtreamClient.enc(s.user) + "&password=" + XtreamClient.enc(s.pass)
        if let a = action { sb += "&action=" + a }
        if let e = extra { sb += e }
        return sb
    }

    public var xmltvUrl: String { base + "/xmltv.php?username=" + XtreamClient.enc(s.user) + "&password=" + XtreamClient.enc(s.pass) }

    public func liveUrl(_ sid: String, fmt: String? = nil) -> String {
        var f = fmt ?? s.liveFmt
        if f == "auto" { f = s.hls ? "m3u8" : "ts" }
        return base + "/live/" + XtreamClient.enc(s.user) + "/" + XtreamClient.enc(s.pass) + "/" + sid + "." + f
    }

    public func movieUrl(_ sid: String, ext: String?) -> String {
        base + "/movie/" + XtreamClient.enc(s.user) + "/" + XtreamClient.enc(s.pass) + "/" + sid + "." + ((ext ?? "").isEmpty ? "mp4" : ext!)
    }

    public func episodeUrl(_ id: String, ext: String?) -> String {
        base + "/series/" + XtreamClient.enc(s.user) + "/" + XtreamClient.enc(s.pass) + "/" + id + "." + ((ext ?? "").isEmpty ? "mp4" : ext!)
    }

    // MARK: json helpers

    private func getJSON(_ url: String) async throws -> Any {
        let d = try await Net.data(url, ua: s.ua, insecure: s.insecure)
        do { return try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) }
        catch { throw NetError.invalid("Risposta non valida dal server") }
    }

    static func str(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) { return s }
        return ""
    }

    private static func int(_ v: String?) -> Int { Int((v ?? "").trimmed) ?? 0 }
    private static func int64(_ v: String?) -> Int64 { Int64((v ?? "").trimmed) ?? 0 }
    private static func nz(_ v: String?) -> String { (v ?? "").trimmed }
    private static func emptyNil(_ v: String?) -> String? { let t = (v ?? "").trimmed; return t.isEmpty ? nil : t }

    // MARK: account

    public func auth() async throws -> Account {
        let el = try await getJSON(api(nil))
        var a = Account()
        guard let o = el as? [String: Any] else { a.message = "Risposta non valida"; return a }
        guard let ui = o["user_info"] as? [String: Any] else { a.message = "Credenziali non valide"; return a }
        let auth = XtreamClient.str(ui["auth"])
        a.ok = auth == "1" || auth.lowercased() == "true"
        a.hls = XtreamClient.str(ui["allowed_output_formats"]).lowercased().contains("m3u8")
        a.status = XtreamClient.str(ui["status"])
        a.maxConn = XtreamClient.str(ui["max_connections"])
        a.activeConn = XtreamClient.str(ui["active_cons"])
        let exp = XtreamClient.str(ui["exp_date"])
        if exp.count >= 6 && exp.allDigits(), let ts = Int64(exp) {
            a.expTs = ts
            let f = DateFormatter()
            f.locale = Locale(identifier: "it_IT")
            f.dateFormat = "dd/MM/yyyy"
            a.expires = f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
        } else if !exp.isEmpty && exp != "null" {
            a.expires = exp
        } else {
            a.expires = "illimitato"
        }
        if !a.ok { a.message = a.status.isEmpty ? "Autenticazione rifiutata" : a.status }
        return a
    }

    // MARK: catalogues

    private func categories(_ action: String) async throws -> [String: String] {
        var m: [String: String] = [:]
        if let arr = try await getJSON(api(action)) as? [Any] {
            for e in arr {
                guard let o = e as? [String: Any] else { continue }
                m[XtreamClient.str(o["category_id"])] = XtreamClient.str(o["category_name"])
            }
        }
        return m
    }

    private func catName(_ cats: [String: String], _ id: String?) -> String {
        guard let id = id, let n = cats[id], !n.isEmpty else { return "Altro" }
        return n
    }

    /// Downloads a catalogue to a file and streams its objects.
    private func stream(_ url: String, keys: Set<String>, progress: ((Int64, Int64) -> Void)? = nil, _ body: ([String: String]) throws -> Void) async throws {
        let file = try await Net.download(url, ua: s.ua, insecure: s.insecure, progress: progress)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try Data(contentsOf: file, options: .alwaysMapped)
        try FlatJSON.forEachObject(in: data, keys: keys, body)
    }

    @discardableResult
    public func loadLive(progress: ((Int) -> Void)? = nil, sink: (Item) -> Void) async throws -> Int {
        let cats = try await categories("get_live_categories")
        var n = 0
        let src = s.id
        try await stream(api("get_live_streams"), keys: ["stream_id", "name", "category_id", "stream_icon", "epg_channel_id", "num"]) { f in
            guard let sid = f["stream_id"] else { return }
            let name = XtreamClient.nz(f["name"])
            if Hash.isSeparator(name) { return }                                   // list headers, not channels
            let it = Item(src: src, kind: .live, key: "\(src):l:\(sid)", name: name, cat: self.catName(cats, f["category_id"]))
            it.sid = sid
            it.logo = XtreamClient.emptyNil(f["stream_icon"])
            it.epgId = XtreamClient.nz(f["epg_channel_id"])
            it.num = XtreamClient.int(f["num"])
            sink(it)
            n += 1
            if n % 4000 == 0 { progress?(n) }
        }
        return n
    }

    @discardableResult
    public func loadVod(progress: ((Int) -> Void)? = nil, sink: (Item) -> Void) async throws -> Int {
        let cats = try await categories("get_vod_categories")
        var n = 0
        let src = s.id
        try await stream(api("get_vod_streams"), keys: ["stream_id", "name", "category_id", "stream_icon", "container_extension", "added", "rating"]) { f in
            guard let sid = f["stream_id"] else { return }
            let name = XtreamClient.nz(f["name"])
            if Hash.isSeparator(name) { return }                                   // "---- Vetrina ----" banners are not films
            let it = Item(src: src, kind: .movie, key: "\(src):m:\(sid)", name: name, cat: self.catName(cats, f["category_id"]))
            it.sid = sid
            it.logo = XtreamClient.emptyNil(f["stream_icon"])
            it.ext = XtreamClient.nz(f["container_extension"])
            it.added = XtreamClient.int(f["added"])
            let rating = f["rating"]
            it.extra = rating == nil || rating == "0" ? "" : rating
            sink(it)
            n += 1
            if n % 4000 == 0 { progress?(n) }
        }
        return n
    }

    @discardableResult
    public func loadSeries(progress: ((Int) -> Void)? = nil, sink: (Item) -> Void) async throws -> Int {
        let cats = try await categories("get_series_categories")
        var n = 0
        let src = s.id
        try await stream(api("get_series"), keys: ["series_id", "name", "category_id", "cover", "last_modified", "releaseDate", "rating"]) { f in
            guard let sid = f["series_id"] else { return }
            let name = XtreamClient.nz(f["name"])
            if Hash.isSeparator(name) { return }
            let it = Item(src: src, kind: .series, key: "\(src):s:\(sid)", name: name, cat: self.catName(cats, f["category_id"]))
            it.sid = sid
            it.logo = XtreamClient.emptyNil(f["cover"])
            it.added = XtreamClient.int(f["last_modified"])
            var year = XtreamClient.nz(f["releaseDate"])
            if year.count >= 4 { year = String(year.prefix(4)) }
            let rating = XtreamClient.nz(f["rating"])
            it.extra = (year + (rating.isEmpty || rating == "0" ? "" : "  " + rating)).trimmed
            sink(it)
            n += 1
            if n % 4000 == 0 { progress?(n) }
        }
        return n
    }

    // MARK: details

    /// "backdrop_path" is an array of image URLs on most panels, a single string on some.
    static func backdropList(_ info: [String: Any]?) -> [String] {
        guard let b = info?["backdrop_path"], !(b is NSNull) else { return [] }
        var out: [String] = []
        if let arr = b as? [Any] {
            for e in arr { if let u = (e as? String)?.trimmed, u.hasPrefix("http"), out.count < 6 { out.append(u) } }
        } else if let s = (b as? String)?.trimmed, s.hasPrefix("http") {
            out.append(s)
        }
        return out
    }

    public func seriesInfo(_ seriesId: String) async throws -> SeriesInfo {
        let el = try await getJSON(api("get_series_info", "&series_id=" + XtreamClient.enc(seriesId)))
        var si = SeriesInfo()
        guard let o = el as? [String: Any] else { return si }
        if let i = o["info"] as? [String: Any] {
            si.name = XtreamClient.str(i["name"])
            si.plot = XtreamClient.str(i["plot"])
            si.cover = XtreamClient.str(i["cover"])
            si.genre = XtreamClient.str(i["genre"])
            si.year = XtreamClient.str(i["releaseDate"])
            if si.year.count >= 4 { si.year = String(si.year.prefix(4)) }
            si.rating = XtreamClient.str(i["rating"])
            si.cast = XtreamClient.str(i["cast"])
            si.director = XtreamClient.str(i["director"])
            si.backdrops = XtreamClient.backdropList(i)
            si.backdrop = si.backdrops.first ?? ""
            si.trailer = XtreamClient.str(i["youtube_trailer"])
        }
        var groups: [[Any]] = []
        if let eps = o["episodes"] as? [String: Any] {
            for k in eps.keys.sorted() { if let g = eps[k] as? [Any] { groups.append(g) } }
        } else if let eps = o["episodes"] as? [Any] {
            for e in eps { if let g = e as? [Any] { groups.append(g) } }
        }
        for g in groups {
            for e in g {
                guard let eo = e as? [String: Any] else { continue }
                var ep = Episode()
                ep.id = XtreamClient.str(eo["id"])
                ep.title = XtreamClient.str(eo["title"])
                ep.ext = XtreamClient.str(eo["container_extension"])
                ep.season = XtreamClient.int(XtreamClient.str(eo["season"]))
                ep.episode = XtreamClient.int(XtreamClient.str(eo["episode_num"]))
                if let ei = eo["info"] as? [String: Any] {
                    ep.plot = XtreamClient.str(ei["plot"])
                    ep.image = XtreamClient.str(ei["movie_image"])
                    ep.duration = XtreamClient.str(ei["duration"])
                }
                si.episodes.append(ep)
            }
        }
        si.episodes.sort { $0.season != $1.season ? $0.season < $1.season : $0.episode < $1.episode }
        return si
    }

    public func vodInfo(_ vodId: String) async throws -> VodInfo {
        let el = try await getJSON(api("get_vod_info", "&vod_id=" + XtreamClient.enc(vodId)))
        var v = VodInfo()
        guard let o = el as? [String: Any], let i = o["info"] as? [String: Any] else { return v }
        func first(_ a: String, _ b: String) -> String { let x = XtreamClient.str(i[a]); return x.isEmpty ? XtreamClient.str(i[b]) : x }
        v.plot = first("plot", "description")
        v.cast = first("cast", "actors")
        v.director = XtreamClient.str(i["director"])
        v.genre = XtreamClient.str(i["genre"])
        v.year = first("releasedate", "releaseDate")
        if v.year.count >= 4 { v.year = String(v.year.prefix(4)) }
        v.rating = XtreamClient.str(i["rating"])
        v.duration = XtreamClient.str(i["duration"])
        v.poster = XtreamClient.str(i["movie_image"])
        v.trailer = XtreamClient.str(i["youtube_trailer"])
        v.backdrops = XtreamClient.backdropList(i)
        v.backdrop = v.backdrops.first ?? ""
        return v
    }

    /// now/next style listing for one channel; titles/descriptions are base64 on most panels.
    public func shortEpg(_ streamId: String, limit: Int) async throws -> [Prog] {
        let el = try await getJSON(api("get_short_epg", "&stream_id=" + XtreamClient.enc(streamId) + "&limit=\(limit)"))
        var out: [Prog] = []
        guard let o = el as? [String: Any], let ls = o["epg_listings"] as? [Any] else { return out }
        for e in ls {
            guard let o = e as? [String: Any] else { continue }
            var p = Prog()
            p.start = XtreamClient.int64(XtreamClient.str(o["start_timestamp"]))
            p.end = XtreamClient.int64(XtreamClient.str(o["stop_timestamp"]))
            if p.start == 0 || p.end == 0 { continue }
            p.title = XtreamClient.b64(XtreamClient.str(o["title"]))
            p.desc = XtreamClient.b64(XtreamClient.str(o["description"]))
            out.append(p)
        }
        return out
    }

    /// Base64 text when it decodes to clean text, otherwise the string itself (some panels send plain text).
    static func b64(_ s: String) -> String {
        if s.isEmpty { return s }
        var t = s.trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        t = t.filter { $0 != "\n" && $0 != "\r" && $0 != " " }
        while t.hasSuffix("=") { t.removeLast() }
        if t.isEmpty || t.count % 4 == 1 { return s }
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        guard let d = Data(base64Encoded: t), let r = String(data: d, encoding: .utf8) else { return s }
        for u in r.unicodeScalars where u == "\u{FFFD}" || (u.value < 32 && u != "\n" && u != "\r" && u != "\t") { return s }
        return r
    }
}
