import Foundation

/// Other qualities of the same live channel, recognised from what the list itself says, never from how a provider organises it
/// (no category, group or server names, no channel lists, no provider rules).
///
/// Two entries are offered as qualities of one channel only when ALL of this holds:
///  - they come from the same list (`Item.src`);
///  - what is left of their names once the quality, codec and language tags are taken away is the same (numbers, "+1", "Plus", a
///    city or a country prefix all count: "Sky Sport 1" and "Sky Sport 2" are never mixed);
///  - their guide ids do not contradict each other (two different ids = two different channels; one missing id is only unknown);
///  - they declare different qualities (two entries with the same declared quality are duplicates, not choices).
/// Everything else is left alone: a channel with no recognisable variant simply has no choice, and nothing is guessed.
/// The quality is the one the name DECLARES: nothing proves the real resolution (the player reports that once it plays).
public enum Variants {
    /// Declared quality of an entry.
    public static let undeclared = 0, sd = 1, hd = 2, fhd = 3, uhd = 4, conflict = -1

    /// Text for the viewer.
    public static func label(_ q: Int) -> String {
        switch q {
        case sd: return "SD"
        case hd: return "HD"
        case fhd: return "Full HD"
        case uhd: return "4K"
        default: return "Standard"
        }
    }

    /// Short stable text kept in the profile.
    public static func code(_ q: Int) -> String? {
        switch q {
        case sd: return "SD"
        case hd: return "HD"
        case fhd: return "FHD"
        case uhd: return "UHD"
        case undeclared: return "STD"
        default: return nil
        }
    }

    /// Inverse of `code`; `conflict` when the text is not a quality.
    public static func fromCode(_ c: String?) -> Int {
        switch c {
        case "SD": return sd
        case "HD": return hd
        case "FHD": return fhd
        case "UHD": return uhd
        case "STD": return undeclared
        default: return conflict
        }
    }

    // MARK: reading a name

    /// What a name says: the words that identify the channel, and the quality it declares.
    public struct Name {
        public var core = ""
        public var quality = Variants.undeclared
    }

    /// Lower case; symbols that merely look like letters ("ᴴᴰ", "ｈｄ") and accents are folded. Names are mostly ASCII: no cost for them.
    private static func fold(_ s: String) -> String {
        var ascii = true
        for b in s.utf8 where b > 127 { ascii = false; break }
        if ascii { return s.lowercased() }
        var out = ""
        for u in s.decomposedStringWithCompatibilityMapping.unicodeScalars where u.properties.generalCategory != .nonspacingMark {
            out += lowerScalar(u)
        }
        return out
    }

    // Quality tags written as a resolution (they win over the generic words) and as words. A bare number ("720") may just as well be
    // part of a channel's name, so only the forms that cannot be anything else count ("720p", "1080i").
    private static func resolution(_ t: String) -> Int {
        switch t {
        case "360p", "480p", "480i", "540p", "576p", "576i": return sd
        case "720p", "720i": return hd
        case "1080p", "1080i": return fhd
        case "2160p": return uhd
        default: return 0
        }
    }

    private static func word(_ t: String) -> Int {
        switch t {
        case "sd", "sdtv": return sd
        case "fhd", "fullhd": return fhd
        case "uhd", "uhdtv", "4k": return uhd
        default: return 0
        }
    }

    /// Tags that say how the picture is coded or which language it is in, not which channel it is.
    private static func noise(_ t: String) -> Bool {
        switch t {
        case "hevc", "h265", "h264", "x264", "x265", "avc", "hdr", "hdr10", "25fps", "30fps", "50fps", "60fps", "fps", "it", "ita": return true
        default: return false
        }
    }

    public static func parse(_ raw: String?) -> Name {
        var out = Name()
        guard let raw = raw, !raw.isEmpty else { return out }
        let s = Array(fold(raw).unicodeScalars)
        let len = s.count
        var toks: [String] = []
        var w = ""
        for i in 0...len {
            let c: Unicode.Scalar = i < len ? s[i] : " "
            if isLetterOrDigit(c) { w.unicodeScalars.append(c); continue }
            if !w.isEmpty { toks.append(w); w = "" }
            if c == "+" && i + 1 < len && isDigitScalar(s[i + 1]) { w = "+" }                // "+1" is part of the channel's name
        }
        var resMask = 0, wordMask = 0
        var generic = false
        var core = ""
        let n = toks.count
        var i = 0
        while i < n {
            defer { i += 1 }
            let t = toks[i]
            let nx = i + 1 < n ? toks[i + 1] : ""
            if t == "full" && nx == "hd" { wordMask |= 1 << fhd; i += 1; continue }
            if t == "ultra" && nx == "hd" { wordMask |= 1 << uhd; i += 1; continue }
            if t == "hd" && nx == "ready" { generic = true; i += 1; continue }
            if (t == "h" || t == "x") && (nx == "264" || nx == "265") { i += 1; continue }
            if t == "hd" || t == "hdtv" { generic = true; continue }
            let r = resolution(t)
            if r != 0 { resMask |= 1 << r; continue }
            let q = word(t)
            if q != 0 { wordMask |= 1 << q; continue }
            if noise(t) { continue }
            if !core.isEmpty { core += " " }
            core += t
        }
        out.core = core
        out.quality = decide(resMask, wordMask, generic)
        return out
    }

    /// A resolution wins over the generic "HD"; tags that disagree make the name unusable for choosing (never guessed).
    private static func decide(_ resMask: Int, _ wordMask: Int, _ generic: Bool) -> Int {
        if resMask.nonzeroBitCount > 1 || wordMask.nonzeroBitCount > 1 { return conflict }
        let r = resMask == 0 ? 0 : resMask.trailingZeroBitCount
        let wq = wordMask == 0 ? 0 : wordMask.trailingZeroBitCount
        var q = r != 0 ? r : wq
        if r != 0 && wq != 0 && r != wq { return conflict }
        if generic {
            if q == 0 { return hd }
            if q == sd { return conflict }                    // "SD HD"
        }
        if q == 0 { q = undeclared }
        return q
    }

    /// Where a viewer's quality preference for this channel is kept: the list plus the identifying words, so list order and numbering do not matter.
    public static func anchor(_ it: Item) -> String { "\(it.src)|\(parse(it.name).core)" }

    // MARK: grouping

    /// The qualities of one channel, best first. `keys[i]` plays at quality `q[i]`.
    public final class Group {
        public let keys: [String]
        public let q: [Int]
        public let strong: Bool
        init(keys: [String], q: [Int], strong: Bool) { self.keys = keys; self.q = q; self.strong = strong }

        public func indexOfQuality(_ quality: Int) -> Int { q.firstIndex(of: quality) ?? -1 }
    }

    /// Result for one library snapshot. Only entries that really have another quality are stored.
    public final class Index {
        fileprivate var byKey: [String: Group] = [:]
        public fileprivate(set) var groups = 0
        public fileprivate(set) var live = 0
        public var members: Int { byKey.count }
        public func group(of key: String) -> Group? { byKey[key] }
    }

    /// One pass over the channels; nothing is kept but the groups.
    public static func build(_ items: [Item]) -> Index {
        let idx = Index()
        var buckets: [String: [(Item, Int)]] = [:]
        for it in items {
            if it.kind != .live || it.key.isEmpty { continue }
            idx.live += 1
            let nm = parse(it.name)
            if nm.core.isEmpty || nm.quality == conflict { continue }
            buckets["\(it.src)\u{1}\(nm.core)", default: []].append((it, nm.quality))
        }
        for l in buckets.values {
            if l.count < 2 { continue }
            // split by guide id: two different ids are two channels; an entry without an id could belong to either, so it stays out
            var byEpg: [String: [(Item, Int)]] = [:]
            var noEpg: [(Item, Int)] = []
            for e in l {
                let id = (e.0.epgId ?? "").trimmed.lowercased()
                if id.isEmpty { noEpg.append(e); continue }
                byEpg[id, default: []].append(e)
            }
            if byEpg.count <= 1 {
                var all: [(Item, Int)] = []
                var shared = false
                for g in byEpg.values { all.append(contentsOf: g); shared = g.count >= 2 }
                all.append(contentsOf: noEpg)
                if put(idx, all, shared) { idx.groups += 1 }
            } else {
                for g in byEpg.values where g.count >= 2 { if put(idx, g, true) { idx.groups += 1 } }
            }
        }
        return idx
    }

    /// Keeps one entry per declared quality (the first in the list) and registers every member; false when there is no choice to offer.
    private static func put(_ idx: Index, _ members: [(Item, Int)], _ strong: Bool) -> Bool {
        var best = [Item?](repeating: nil, count: 5)
        for (it, q) in members where best[q] == nil { best[q] = it }
        if best.compactMap({ $0 }).count < 2 { return false }
        var keys: [String] = [], qs: [Int] = []
        for q in stride(from: uhd, through: undeclared, by: -1) {
            if let b = best[q] { keys.append(b.key); qs.append(q) }
        }
        let g = Group(keys: keys, q: qs, strong: strong)
        for (it, _) in members { idx.byKey[it.key] = g }
        return true
    }

    /// Builds the index once per library snapshot (a refresh publishes a new snapshot, which builds a new one on first use).
    public final class Cache {
        private let lock = NSLock()
        private var builtFor: Library.Snap?
        private var built = Index()

        public init() {}

        public func index(_ snap: Library.Snap) -> Index {
            lock.lock(); defer { lock.unlock() }
            if builtFor !== snap { built = build(snap.items); builtFor = snap }
            return built
        }

        /// The index if it exists for this snapshot, without building it.
        public func peek(_ snap: Library.Snap) -> Index? {
            lock.lock(); defer { lock.unlock() }
            return builtFor === snap ? built : nil
        }
    }
}
