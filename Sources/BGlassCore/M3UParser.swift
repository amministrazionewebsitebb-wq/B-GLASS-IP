import Foundation

/// M3U / M3U8 (extended) playlist parser built for lists with hundreds of thousands of entries: unwanted kinds are never
/// allocated, URL prefixes and categories are shared, and "Show S01E02" entries are folded into one series item that keeps
/// its episodes in a compact text blob (see `episodes(of:)`).
public enum M3UParser {
    public struct Meta {
        public var epgUrl: String?
        public var count = 0            // entries read
    }

    /// One episode of an M3U series.
    public struct Ep {
        public var season = 0
        public var number = 0
        public var name = ""
        public var url = ""
    }

    private static let epPattern = try! NSRegularExpression(pattern: "^(.*?)[\\s._\\-]*s(\\d{1,3})\\s*[ex]\\s*(\\d{1,4}).*$", options: [.caseInsensitive])
    private static let ep2Pattern = try! NSRegularExpression(pattern: "^(.*?)[\\s._\\-]*(\\d{1,2})x(\\d{1,4}).*$", options: [.caseInsensitive])
    private static let sep = "\t"
    private static let abs = "\u{1}"

    // MARK: parse

    public static func parse(data: Data, srcId: Int, wantLive: Bool = true, wantMovies: Bool = true, wantSeries: Bool = true,
                             tick: ((Int) throws -> Void)? = nil, sink: (Item) -> Void) throws -> Meta {
        var meta = Meta()
        var seen = Set<String>()
        let cats = StrPool(20000), prefixes = StrPool(20000)
        var shows: [String: Show] = [:]
        var showOrder: [String] = []
        var cur: Item?
        var first = true
        var pendUA: String?, pendRef: String?                                  // #EXTVLCOPT lines, wherever they sit around the entry

        try forEachLine(data) { raw in
            var line = raw
            if first {
                first = false
                if line.unicodeScalars.first == "\u{FEFF}" { line = String(line.unicodeScalars.dropFirst()) }
            }
            if line.isEmpty { return }
            let b = Array(line.utf8)
            if b[0] == 35 {                                                       // '#'
                if line.hasPrefix("#EXTINF") {
                    cur = parseInf(line)
                } else if line.hasPrefix("#EXTM3U") {
                    var a: [String: String] = [:]
                    attrs(b, 7, b.count, &a)
                    let e = a["url-tvg"] ?? a["x-tvg-url"] ?? a["tvg-url"]
                    // several guides may be listed, separated by commas: the first one that is an address
                    if let e = e?.split(separator: ",").map({ String($0).trimmed }).first(where: { $0.contains("://") }) { meta.epgUrl = e }
                } else if line.hasPrefix("#EXTGRP:"), let c = cur {
                    if c.cat.isEmpty { c.cat = String(line.dropFirst(8)).trimmed }
                } else if line.hasPrefix("#EXTVLCOPT:") {
                    let o = String(line.dropFirst(11))
                    if let eq = o.firstIndex(of: "="), o.distance(from: o.startIndex, to: eq) > 0 {
                        let k = o[o.startIndex..<eq].lowercased().trimmed, v = String(o[o.index(after: eq)...]).trimmed
                        if k == "http-user-agent" { pendUA = v } else if k == "http-referrer" || k == "http-referer" { pendRef = v }
                    }
                }
                return
            }
            // only addresses are entries: stray text (an HTML fragment, a note) is skipped without losing the #EXTINF before it
            if !line.contains("://") { return }
            let item = cur ?? Item()
            if let u = pendUA, !u.isEmpty { item.ua = u }
            if let r = pendRef, !r.isEmpty, !line.contains("|") { line += "|Referer=" + r }       // kept with the address, read back when playing
            pendUA = nil; pendRef = nil
            meta.count += 1
            if let tick = tick, meta.count % 5000 == 0 { try tick(meta.count) }
            let kind = kindOf(line, item)
            var want = kind == .live ? wantLive : kind == .movie ? wantMovies : wantSeries
            if want && Hash.isSeparator(item.name) { want = false }              // decorative headers such as "----Italia----"
            if want {
                if item.name.isEmpty { item.name = lastSegment(line) }
                item.cat = cats.get(item.cat.isEmpty ? "Altro" : item.cat)
                item.src = srcId
                item.kind = kind
                if kind == .episode {
                    addEpisode(&shows, &showOrder, item, line, srcId, prefixes)
                } else {
                    let stable = (item.epgId ?? "") + "|" + item.name + "|" + item.cat
                    let key = "\(srcId):\(kindChar(kind)):\(Hash.fnv(stable))"
                    var n = 1
                    var k2 = key
                    while !seen.insert(k2).inserted { n += 1; k2 = key + "~" + String(n) }
                    item.key = k2
                    item.setUrl(line, prefixes: prefixes)
                    if !Hash.isSeparator(item.name) { sink(item) }
                }
            }
            cur = nil
        }
        for k in showOrder {
            guard let s = shows[k] else { continue }
            s.item.eps = s.blob
            s.item.extra = "\(s.count) " + (s.count == 1 ? "episodio" : "episodi")
            sink(s.item)
        }
        return meta
    }

    private final class Show {
        let item: Item
        var blob = ""
        let prefix: String
        var count = 0
        init(item: Item, prefix: String) { self.item = item; self.prefix = prefix }
    }

    private static func match(_ re: NSRegularExpression, _ s: String) -> (title: String, season: Int, ep: Int)? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [.anchored], range: NSRange(location: 0, length: ns.length)),
              m.range.length == ns.length else { return nil }
        return (ns.substring(with: m.range(at: 1)), Int(ns.substring(with: m.range(at: 2))) ?? 1, Int(ns.substring(with: m.range(at: 3))) ?? 0)
    }

    private static func isEpisodeName(_ s: String) -> Bool { match(epPattern, s) != nil }

    private static func addEpisode(_ shows: inout [String: Show], _ order: inout [String], _ e: Item, _ url: String, _ srcId: Int, _ prefixes: StrPool) {
        var title = e.name
        var season = 1, ep = 0
        if let m = match(epPattern, e.name) ?? match(ep2Pattern, e.name) {
            title = m.title.trimmed
            season = m.season
            ep = m.ep
        }
        if title.isEmpty { title = e.name }
        let sk = e.cat + "|" + title.lowercased()
        var s = shows[sk]
        if s == nil {
            let it = Item(src: srcId, kind: .series, key: "\(srcId):s:\(Hash.fnv(sk))", name: title, cat: e.cat)
            it.logo = e.logo
            let units = Array(url.utf16)
            var prefix = ""
            if let i = units.lastIndex(of: 47), i > 8 { prefix = prefixes.get(String(decoding: units[0...i], as: UTF16.self)) }
            it.ub = prefix
            s = Show(item: it, prefix: prefix)
            shows[sk] = s
            order.append(sk)
        }
        let show = s!
        show.count += 1
        if ep == 0 { ep = show.count }
        let tail = url.hasPrefix(show.prefix) ? String(url.dropFirst(show.prefix.count)) : abs + url
        show.blob += "\(season)\(sep)\(ep)\(sep)\(clean(e.name))\(sep)\(tail)\n"
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    /// Decodes the episodes stored in a series item (in playlist order).
    public static func episodes(of show: Item) -> [Ep] {
        guard let blob = show.eps, !blob.isEmpty else { return [] }
        let prefix = show.ub ?? ""
        var out: [Ep] = []
        for line in blob.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            if f.count != 4 { continue }
            var e = Ep()
            if let s = Int(f[0]), let n = Int(f[1]) { e.season = s; e.number = n } else { e.season = 1; e.number = out.count + 1 }
            e.name = String(f[2])
            let tail = String(f[3])
            e.url = tail.hasPrefix(abs) ? String(tail.dropFirst()) : prefix + tail
            out.append(e)
        }
        return out
    }

    static func kindChar(_ kind: Kind) -> Character {
        switch kind {
        case .movie: return "m"
        case .series: return "s"
        case .episode: return "e"
        case .live: return "l"
        }
    }

    /// The address decides first; when it says nothing ("http://host/user/pass/123"), two safe hints from the entry itself:
    /// an episode marker in the title (S01E02, 1x02) is never a live channel, and a group that starts with "VOD" holds films.
    static func kindOf(_ url: String, _ cur: Item?) -> Kind {
        let k = kindOf(url)
        guard k == .live, let cur = cur else { return k }
        let u = address(url).lowercased()
        if u.contains("/live/") || u.contains(".m3u8") || u.contains(".ts") { return k }
        if isEpisodeName(cur.name) { return .episode }
        let g = cur.cat.trimmed.lowercased()
        if g.hasPrefix("vod") {
            let rest = g.unicodeScalars.dropFirst(3)
            if rest.isEmpty || !isLetterOrDigit(rest.first!) { return .movie }
        }
        return k
    }

    static func kindOf(_ url: String) -> Kind {
        let u = address(url).lowercased()
        if u.contains("/series/") { return .episode }
        if u.contains("/movie/") { return .movie }
        var path = Substring(u)
        if let q = u.firstIndex(of: "?"), q != u.startIndex { path = u[u.startIndex..<q] }
        for ext in [".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".m4v"] where path.hasSuffix(ext) { return .movie }
        return .live
    }

    /// The address without the Kodi-style headers some lists append ("http://host/x.m3u8|User-Agent=…&Referer=…").
    public static func address(_ line: String) -> String {
        guard let bar = line.firstIndex(of: "|") else { return line }
        return String(line[line.startIndex..<bar])
    }

    /// The headers of a Kodi-style entry: "|User-Agent=Foo&Referer=http%3A%2F%2Fsite" -> ["User-Agent": "Foo", "Referer": "http://site"].
    public static func headers(_ line: String) -> [String: String] {
        guard let bar = line.firstIndex(of: "|") else { return [:] }
        var out: [String: String] = [:]
        for kv in line[line.index(after: bar)...].split(separator: "&") {
            guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { continue }
            var k = String(kv[kv.startIndex..<eq]).trimmed
            let raw = String(kv[kv.index(after: eq)...])
            let v = (raw.removingPercentEncoding ?? raw).trimmed
            switch k.lowercased() {
            case "user-agent", "useragent", "http-user-agent": k = "User-Agent"
            case "referer", "referrer", "http-referrer", "http-referer": k = "Referer"
            case "origin": k = "Origin"
            case "cookie": k = "Cookie"
            default: break
            }
            if !v.isEmpty { out[k] = v }
        }
        return out
    }

    private static func lastSegment(_ url: String) -> String {
        let url = address(url)
        var p = Substring(url)
        if let q = url.firstIndex(of: "?"), q != url.startIndex { p = url[url.startIndex..<q] }
        if let s = p.lastIndex(of: "/") { return String(p[p.index(after: s)...]) }
        return String(p)
    }

    static func parseInf(_ line: String) -> Item {
        let it = Item()
        let b = Array(line.utf8)
        let start = min(8, b.count)                                    // after "#EXTINF:"
        var comma = -1
        var quote: UInt8 = 0
        var i = start
        while i < b.count {
            let c = b[i]
            if quote == 0 && (c == 34 || (c == 39 && i > 0 && b[i - 1] == 61)) { quote = c }      // "…" or ='…'
            else if quote != 0 && c == quote { quote = 0 }
            else if c == 44 && quote == 0 { comma = i; break }
            i += 1
        }
        let headEnd = comma < 0 ? b.count : comma
        var a: [String: String] = [:]
        attrs(b, start, headEnd, &a)
        var title = comma < 0 ? "" : String(decoding: b[(comma + 1)...], as: UTF8.self).trimmed
        if title.isEmpty { title = a["tvg-name"] ?? "" }
        it.name = title
        it.cat = a["group-title"] ?? ""
        it.logo = firstNonEmpty(a["tvg-logo"], a["logo"], a["tvg-logo-small"])
        it.epgId = a["tvg-id"] ?? ""
        if let ch = firstNonEmpty(a["tvg-chno"], a["channel-number"], a["tvg-channo"]), let n = Int(ch.trimmed) { it.num = n }
        if let ua = a["http-user-agent"], !ua.isEmpty { it.ua = ua }
        return it
    }

    /// Parses key="value" / key=value pairs; keys are lower-cased.
    static func attrs(_ s: [UInt8], _ from: Int, _ to: Int, _ out: inout [String: String]) {
        let to = min(to, s.count)
        var i = from
        while i < to && s[i] == 32 { i += 1 }
        while i < to {
            while i < to && (s[i] == 32 || s[i] == 9) { i += 1 }
            let ks = i
            while i < to && s[i] != 61 && s[i] != 32 { i += 1 }
            if i >= to || s[i] != 61 { continue }
            let key = String(decoding: s[ks..<i], as: UTF8.self).lowercased()
            i += 1
            var val: String
            if i < to && (s[i] == 34 || s[i] == 39) {
                let quote = s[i]
                var ve = i + 1
                while ve < s.count && s[ve] != quote { ve += 1 }
                if ve >= s.count || ve > to { ve = to }
                val = String(decoding: s[(i + 1)..<max(i + 1, ve)], as: UTF8.self)
                i = ve + 1
            } else {
                let vs = i
                while i < to && s[i] != 32 { i += 1 }
                val = String(decoding: s[vs..<i], as: UTF8.self)
            }
            if !key.isEmpty { out[key] = val.trimmed }
        }
    }

    private static func firstNonEmpty(_ v: String?...) -> String? {
        for s in v { if let s = s, !s.trimmed.isEmpty { return s.trimmed } }
        return nil
    }

    // MARK: lines

    /// Calls `body` for every non-empty line (trimmed of control characters and spaces), whatever the line ending.
    static func forEachLine(_ data: Data, _ body: (String) throws -> Void) rethrows {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self)
            let n = p.count
            var start = 0
            var i = 0
            @inline(__always) func emit(_ a: Int, _ z: Int) throws {
                var a = a, z = z
                while a < z && p[a] <= 32 { a += 1 }
                while z > a && p[z - 1] <= 32 { z -= 1 }
                if z > a { try body(Lenient.text(UnsafeBufferPointer(rebasing: p[a..<z]))) }
            }
            while i < n {
                let c = p[i]
                if c == 10 || c == 13 {
                    try emit(start, i)
                    if c == 13 && i + 1 < n && p[i + 1] == 10 { i += 1 }
                    start = i + 1
                }
                i += 1
            }
            if start < n { try emit(start, n) }
        }
    }
}
