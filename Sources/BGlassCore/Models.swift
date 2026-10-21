import Foundation

public enum Kind: Int, Codable, CaseIterable, Sendable {
    case live = 0, movie = 1, series = 2, episode = 3
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to a default when the key is missing or unreadable (files written by older versions).
    func value<T: Decodable>(_ key: Key, _ def: T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return def
    }
}

/// One playable thing (live channel, movie or series). Series from M3U lists keep their episodes in `eps`.
public final class Item: @unchecked Sendable {
    public var key: String
    public var src: Int
    public var kind: Kind
    public var name: String
    public var cat: String
    public var logo: String?
    public var ub: String?            // shared URL prefix (M3U), see url()
    public var us: String?            // URL suffix, or the whole URL when ub is nil
    public var ext: String?           // container extension for xtream vod/series
    public var sid: String?           // xtream stream/series id
    public var epgId: String?         // tvg-id / epg_channel_id
    public var num = 0                // provider channel number (0 = none)
    public var extra: String?         // year/rating/etc. free text for VOD cards
    public var parent: String?        // (legacy) series key for episode items
    public var season = 0
    public var episode = 0
    public var ua: String?            // per-stream UA override (#EXTVLCOPT)
    public var sk: String?            // folded name used by the search box (not stored; filled on first use)
    public var rate: Float = -1       // parsed rating (not stored; filled on first use)
    public var added = 0              // unix seconds the provider added it (0 = unknown)
    public var eps: String?           // M3U series: one episode per line  season \t number \t title \t url-suffix

    public init(src: Int = 0, kind: Kind = .live, key: String = "", name: String = "", cat: String = "") {
        self.src = src
        self.kind = kind
        self.key = key
        self.name = name
        self.cat = cat
    }

    public var epgKey: String? {
        guard let e = epgId, !e.isEmpty else { return nil }
        return "\(src):\(e.lowercased())"
    }

    /// Full URL for direct (M3U) items, nil for Xtream items (their URL is built from sid).
    public var url: String? {
        guard let us = us else { return nil }
        if let ub = ub { return ub + us }
        return us
    }

    /// Stores a URL as (shared prefix + tail); lossless, saves ~100 bytes per item on big lists.
    public func setUrl(_ u: String?, prefixes: StrPool?) {
        guard let u = u else { ub = nil; us = nil; return }
        let units = Array(u.utf16)
        if let prefixes = prefixes, let i = units.lastIndex(of: 47), i > 8, i < units.count - 1 {
            ub = prefixes.get(String(decoding: units[0...i], as: UTF16.self))
            us = String(decoding: units[(i + 1)...], as: UTF16.self)
        } else {
            ub = nil
            us = u
        }
    }
}

public enum SourceType: Int, Codable, Sendable { case m3u = 0, xtream = 1 }

/// A provider: an M3U URL or an Xtream Codes account.
public struct Source: Codable, Equatable, Identifiable, Sendable {
    public var id = 0
    public var name = ""
    public var type: SourceType = .xtream
    public var url = ""              // M3U URL or Xtream server base (http://host:port)
    public var user = ""
    public var pass = ""
    public var ua = ""               // custom User-Agent (blank = default)
    public var epgUrl = ""           // custom XMLTV url (blank = auto)
    public var epgAuto = ""          // url-tvg found in the M3U header
    public var insecure = false      // accept bad TLS certs
    public var wantLive = true
    public var wantMovies = true
    public var wantSeries = true
    public var liveFmt = "auto"      // xtream live output: auto | ts | m3u8
    public var hls = false           // the panel offers m3u8 (from allowed_output_formats)
    public var fmtChecked = false
    public var fmtVer = 2
    public var updated: Int64 = 0    // last successful refresh (epoch ms)
    public var nLive = 0
    public var nMovies = 0
    public var nSeries = 0
    public var status = ""           // last error / info
    public var expires = ""          // xtream account expiry (text)
    public var maxConn = ""
    public var expTs: Int64 = 0      // account expiry, epoch seconds (0 = unknown / unlimited)
    public var activeConn = ""

    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, 0); name = c.value(.name, ""); type = c.value(.type, .xtream); url = c.value(.url, "")
        user = c.value(.user, ""); pass = c.value(.pass, ""); ua = c.value(.ua, ""); epgUrl = c.value(.epgUrl, "")
        epgAuto = c.value(.epgAuto, ""); insecure = c.value(.insecure, false)
        wantLive = c.value(.wantLive, true); wantMovies = c.value(.wantMovies, true); wantSeries = c.value(.wantSeries, true)
        liveFmt = c.value(.liveFmt, "auto"); hls = c.value(.hls, false); fmtChecked = c.value(.fmtChecked, false)
        fmtVer = c.value(.fmtVer, 2); updated = c.value(.updated, 0)
        nLive = c.value(.nLive, 0); nMovies = c.value(.nMovies, 0); nSeries = c.value(.nSeries, 0)
        status = c.value(.status, ""); expires = c.value(.expires, ""); maxConn = c.value(.maxConn, "")
        expTs = c.value(.expTs, 0); activeConn = c.value(.activeConn, "")
    }
}

/// Insertion-ordered set of keys: O(1) membership, stable order (what a viewer picked, in the order they picked it).
public struct OrderedKeySet: Codable, Equatable, Sequence, Sendable {
    public private(set) var array: [String] = []
    private var members: Set<String> = []

    public init() {}
    public init<S: Sequence>(_ s: S) where S.Element == String { for k in s { insert(k) } }

    public init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        self.init(try c.decode([String].self))
    }

    public func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        try c.encode(array)
    }

    public var count: Int { array.count }
    public var isEmpty: Bool { array.isEmpty }
    public func contains(_ k: String) -> Bool { members.contains(k) }
    public func makeIterator() -> IndexingIterator<[String]> { array.makeIterator() }
    public var keySet: Set<String> { members }

    @discardableResult
    public mutating func insert(_ k: String) -> Bool {
        if members.insert(k).inserted { array.append(k); return true }
        return false
    }

    @discardableResult
    public mutating func remove(_ k: String) -> Bool {
        guard members.remove(k) != nil else { return false }
        if let i = array.firstIndex(of: k) { array.remove(at: i) }
        return true
    }

    /// Removes many keys in one pass; returns the ones that were really there.
    @discardableResult
    public mutating func remove<S: Sequence>(contentsOf keys: S) -> [String] where S.Element == String {
        let drop = Set(keys).intersection(members)
        if drop.isEmpty { return [] }
        array.removeAll { drop.contains($0) }
        members.subtract(drop)
        return Array(drop)
    }

    public mutating func removeAll() { array.removeAll(); members.removeAll() }

    /// Replaces the order wholesale (sorting, moving); the members must stay the same.
    public mutating func reorder(_ keys: [String]) {
        array = keys
        members = Set(keys)
    }

    public mutating func retain(where keep: (String) -> Bool) {
        array.removeAll { !keep($0) }
        members = Set(array)
    }
}

public struct QualityPref: Codable, Equatable, Sendable {
    public var anchor: String
    public var code: String
}

/// A viewer: own name/colour/PIN and, above all, their own hand-picked content.
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: String = ""
    public var name: String = ""
    public var color = 0
    public var pin = ""
    public var kids = false
    public var created: Int64 = 0

    public var live = OrderedKeySet()      // ordered channel keys
    public var movies = OrderedKeySet()
    public var series = OrderedKeySet()
    public var favs: [String] = []         // favourite live keys
    public var recent: [String] = []       // last watched (live/movies/episodes), newest first
    public var resume: [String: Int64] = [:]       // vod key -> position ms
    public var done: [String: Int64] = [:]         // vod key -> duration ms (for progress bars)
    public var last: String?                       // last live channel key
    public var resumeAt: [String: Int64] = [:]     // vod key -> when the position was last saved (ms)
    public var resumeParent: [String: String] = [:]   // episode key -> series key (so the series shows up in "continue watching")
    public var resumeLabel: [String: String] = [:]    // episode key -> "S2 E5 · Title"

    // Channel packs (see Packs): enabled groups, the channel each entry resolved to at the last sync, and the entries
    // the viewer removed by hand (they stay out until the group is switched off and on again).
    public var packs = OrderedKeySet()
    public var packMap: [String: String] = [:]
    public var packOff = OrderedKeySet()

    /// The quality the viewer chose for a channel (Variants.anchor -> Variants.code); used only when that quality really exists for it.
    public var qpref: [QualityPref] = []

    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.value(.id, ""); name = c.value(.name, ""); color = c.value(.color, 0); pin = c.value(.pin, "")
        kids = c.value(.kids, false); created = c.value(.created, 0)
        live = c.value(.live, OrderedKeySet()); movies = c.value(.movies, OrderedKeySet()); series = c.value(.series, OrderedKeySet())
        favs = c.value(.favs, []); recent = c.value(.recent, [])
        resume = c.value(.resume, [:]); done = c.value(.done, [:]); last = c.value(.last, nil)
        resumeAt = c.value(.resumeAt, [:]); resumeParent = c.value(.resumeParent, [:]); resumeLabel = c.value(.resumeLabel, [:])
        packs = c.value(.packs, OrderedKeySet()); packMap = c.value(.packMap, [:]); packOff = c.value(.packOff, OrderedKeySet())
        qpref = c.value(.qpref, [])
    }

    public static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Saves or clears a film / episode position.
    public mutating func saveResume(_ key: String, pos: Int64, dur: Int64, parent: String? = nil, label: String? = nil, now: Int64 = Profile.nowMillis()) {
        if key.isEmpty { return }
        var dur = dur
        if dur <= 0, let d = done[key] { dur = d }
        if dur > 0 && Double(pos) > Double(dur) * 0.95 { clearResume(key); return }       // finished
        if pos <= 3000 { return }
        resume[key] = pos
        done[key] = dur
        resumeAt[key] = now
        if let p = parent, !p.isEmpty { resumeParent[key] = p }
        if let l = label, !l.isEmpty { resumeLabel[key] = l }
        while resume.count > 60 {                                                       // keep the newest 60
            var oldest: String?
            var t = Int64.max
            for k in resume.keys {
                let v = resumeAt[k] ?? 0
                if v < t { t = v; oldest = k }
            }
            guard let o = oldest else { break }
            clearResume(o)
        }
    }

    public mutating func clearResume(_ key: String) {
        resume[key] = nil; done[key] = nil; resumeAt[key] = nil; resumeParent[key] = nil; resumeLabel[key] = nil
    }

    /// Called when live channels leave the profile by hand: remember that their pack entries were refused.
    public mutating func packForget(_ keys: Set<String>) {
        if packMap.isEmpty { return }
        for (entry, ch) in packMap where keys.contains(ch) {
            packOff.insert(entry)
            packMap[entry] = nil
        }
    }

    public func quality(_ anchor: String) -> String? { qpref.first { $0.anchor == anchor }?.code }
    public var hasQualityPrefs: Bool { !qpref.isEmpty }

    public mutating func setQuality(_ anchor: String, _ code: String) {
        qpref.removeAll { $0.anchor == anchor }
        qpref.append(QualityPref(anchor: anchor, code: code))
        while qpref.count > 300 { qpref.removeFirst() }                                 // the oldest choices go first
    }

    public func set(_ kind: Kind) -> OrderedKeySet {
        switch kind {
        case .movie: return movies
        case .series: return series
        default: return live
        }
    }

    public mutating func update(_ kind: Kind, _ body: (inout OrderedKeySet) -> Void) {
        switch kind {
        case .movie: body(&movies)
        case .series: body(&series)
        default: body(&live)
        }
    }

    public func has(_ kind: Kind, _ key: String) -> Bool { set(kind).contains(key) }

    public mutating func touchRecent(_ key: String) {
        recent.removeAll { $0 == key }
        recent.insert(key, at: 0)
        if recent.count > 40 { recent.removeLast(recent.count - 40) }
    }

    public mutating func remapKeys(_ m: [String: String]) {
        if m.isEmpty { return }
        for kind in [Kind.live, .movie, .series] {
            update(kind) { s in
                var changed = false
                var l = s.array
                for i in l.indices { if let n = m[l[i]] { l[i] = n; changed = true } }
                if changed { s = OrderedKeySet(l) }
            }
        }
        for i in favs.indices { if let n = m[favs[i]] { favs[i] = n } }
        for i in recent.indices { if let n = m[recent[i]] { recent[i] = n } }
        if let l = last, let n = m[l] { last = n }
        for (a, b) in m {                                   // positions follow the film to its new key
            if resume[a] != nil && resume[b] == nil {
                resume[b] = resume.removeValue(forKey: a)
                if let d = done.removeValue(forKey: a) { done[b] = d }
                if let at = resumeAt.removeValue(forKey: a) { resumeAt[b] = at }
                if let pa = resumeParent.removeValue(forKey: a) { resumeParent[b] = m[pa] ?? pa }
                if let la = resumeLabel.removeValue(forKey: a) { resumeLabel[b] = la }
            }
        }
        for (k, v) in resumeParent { if let n = m[v] { resumeParent[k] = n } }
    }
}
