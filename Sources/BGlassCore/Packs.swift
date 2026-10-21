import Foundation

/// Ready-made channel packs: a list of well known channel names per theme (sport, cinema, news...) that is matched,
/// by name, against whatever the provider's catalogue calls its channels. Matching is exact on a canonical form
/// (no HD/FHD tags, country prefixes, brackets, accents; "Uno" = "1"; "Tg24" = "Tg 24") so that a pack never picks the
/// wrong channel, and quality aware: HD is preferred, 4K is left out unless asked for.
public enum Packs {
    public final class Entry {
        public let id: String            // groupId/canonical-name, stable across runs
        public let name: String          // as shown to the user
        var keys: [String] = []          // canonical alias keys, first = primary
        var approx: [String] = []        // the same keys without a leading network word ("mediaset extra" -> "extra")
        var four = false                 // the entry itself is a 4K channel ("Sky Cinema 4K")
        init(id: String, name: String) { self.id = id; self.name = name }
        /// All comparable spellings of this entry (tests / diagnostics).
        public var aliasKeys: [String] { keys + approx }
    }

    public final class Group {
        public let id: String, title: String, desc: String
        var prefer = "", avoid = ""
        var anyCountry = false
        public internal(set) var entries: [Entry] = []
        init(id: String, title: String, desc: String) { self.id = id; self.title = title; self.desc = desc }
    }

    // MARK: definition file

    /// The groups, read once from `packs.txt`.
    public static let groups: [Group] = parse(loadText())

    public static func group(_ id: String) -> Group? { groups.first { $0.id == id } }

    static func loadText() -> String {
        #if BGLASS_PLAIN_BUILD
        if let p = ProcessInfo.processInfo.environment["BGLASS_PACKS"], let s = try? String(contentsOfFile: p, encoding: .utf8) { return s }
        return ""
        #else
        if let u = Bundle.module.url(forResource: "packs", withExtension: "txt"), let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        return ""
        #endif
    }

    /// Java-style split: trailing empty pieces are dropped.
    private static func splitTrim(_ s: String, _ sep: Character) -> [String] {
        var p = s.split(separator: sep, omittingEmptySubsequences: false).map { String($0) }
        while let l = p.last, l.isEmpty { p.removeLast() }
        return p
    }

    static func parse(_ text: String) -> [Group] {
        var out: [Group] = []
        var cur: Group?
        var seenInGroup = Set<String>()
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = String(raw).trimmed
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("@group") {
                let p = splitTrim(String(line.dropFirst(6)), "|").map { $0.trimmed }
                if p.isEmpty { continue }
                let g = Group(id: p[0], title: p.count > 1 ? p[1] : p[0], desc: p.count > 2 ? p[2] : "")
                if p.count > 3 {
                    for o in p[3].split(separator: ";") {
                        let o = String(o).trimmed
                        if o.hasPrefix("prefer=") { g.prefer = String(o.dropFirst(7)).trimmed.lowercased() }
                        else if o.hasPrefix("avoid=") { g.avoid = String(o.dropFirst(6)).trimmed.lowercased() }
                        else if o == "any=1" { g.anyCountry = true }
                    }
                }
                out.append(g)
                cur = g
                seenInGroup.removeAll()
                continue
            }
            guard let g = cur else { continue }
            var name = line, aliases = ""
            if let r = line.range(of: " = "), line.distance(from: line.startIndex, to: r.lowerBound) > 0 {
                name = String(line[line.startIndex..<r.lowerBound]).trimmed
                aliases = String(line[r.upperBound...]).trimmed
            }
            var lo = 1, hi = 1
            var ranged = false
            if let b = name.firstIndex(of: "{") {
                if let e = name[b...].firstIndex(of: "}"), let d = name[b...].firstIndex(of: "-"),
                   let l = Int(name[name.index(after: b)..<d]), let h = Int(name[name.index(after: d)..<e]) {
                    lo = l; hi = h; ranged = true
                }
            }
            for n in lo...max(lo, hi) {
                let nm = ranged ? expand(name, n) : name
                let c = canon(nm, "")
                if c.key.isEmpty || !seenInGroup.insert(c.key + (c.k4 ? "#4k" : "")).inserted { continue }
                let en = Entry(id: g.id + "/" + c.key + (c.k4 ? "#4k" : ""), name: nm)
                en.four = c.k4
                en.keys.append(c.key)
                if !aliases.isEmpty {
                    for a in splitTrim(aliases, "|") {
                        let an = ranged ? expand(a.trimmed, n) : a.trimmed
                        let ac = canon(an, "")
                        if !ac.key.isEmpty && !en.keys.contains(ac.key) { en.keys.append(ac.key) }
                        if ac.k4 { en.four = true }
                    }
                }
                for k in en.keys {
                    if let tk = trimNetwork(k), !en.keys.contains(tk), !en.approx.contains(tk) { en.approx.append(tk) }
                }
                g.entries.append(en)
            }
        }
        return out
    }

    private static func expand(_ s: String, _ n: Int) -> String {
        guard let b = s.firstIndex(of: "{"), let e = s[b...].firstIndex(of: "}") else { return s }
        return String(s[s.startIndex..<b]) + String(n) + String(s[s.index(after: e)...])
    }

    private static let entryNames: [String: String] = {
        var m: [String: String] = [:]
        for g in groups { for e in g.entries { m[e.id] = e.name } }
        return m
    }()

    /// Display name of a pack entry ("cinema/sky cinema 1" -> "Sky Cinema Uno HD").
    public static func entryName(_ entryId: String) -> String? { entryNames[entryId] }

    /// "IT: SKY TG24 HD", "|IT| Rai 1", "ITALIA - La7" -> the name without the country prefix. Everything else is left alone.
    public static func cleanName(_ raw: String?) -> String {
        guard let raw = raw else { return "" }
        let u = Array(raw.unicodeScalars)
        let n = u.count
        var j = 0
        while j < n && !isLetterOrDigit(u[j]) { j += 1 }
        var k = j
        while k < n && isLetterOrDigit(u[k]) { k += 1 }
        if k > j {
            let w = String(String.UnicodeScalarView(u[j..<k])).lowercased()
            if w == "it" || w == "ita" || w == "italia" || w == "italy" {
                var m = k
                while m < n && (u[m] == " " || u[m] == "]") { m += 1 }
                if m < n && delim(u[m]) {
                    while m < n && (delim(u[m]) || u[m] == " ") { m += 1 }
                    let rest = String(String.UnicodeScalarView(u[m..<n])).trimmed
                    if !rest.isEmpty { return rest }
                }
            }
        }
        return raw.trimmed
    }

    // MARK: canonical form

    /// A channel name reduced to what identifies it, plus the quality hints found in it.
    struct Canon {
        var key = ""
        var hd = false, fhd = false, sd = false, k4 = false, hevc = false, raw = false
        var adult = false                // never offered by a pack, whatever it is called
        var italian = false              // explicitly marked Italian: "IT:", "(ITA)", category "Italia"...
        var country = ""                 // leading "UK|", "FR:" ... (empty = none / Italian)
    }

    private static let foreign: Set<String> = [
        "uk", "us", "usa", "fr", "es", "de", "pt", "nl", "be", "pl", "ro", "ru", "tr", "ar", "gr", "al", "rs", "ch", "at",
        "se", "no", "dk", "fi", "cz", "hu", "bg", "hr", "si", "sk", "ua", "kr", "jp", "cn", "ph", "ca", "au", "nz", "il",
        "in", "br", "mx", "lat", "ex", "yu", "pk", "af", "ir", "ae", "sa", "eg", "ma", "dz", "tn",
    ]

    /// Full country / language words that start the category names of international lists ("Germany Sport", "UK Sports").
    private static let countryWords: Set<String> = [
        "usa", "united", "germany", "deutschland", "german", "france", "french", "francais", "spain", "spanish", "espana", "portugal", "portuguese",
        "turkey", "turkish", "arabic", "arab", "poland", "polish", "romania", "romanian", "russia", "russian", "albania", "albanian", "netherlands",
        "dutch", "belgium", "brazil", "brazilian", "india", "indian", "canada", "australia", "greece", "greek", "sweden", "swedish", "norway",
        "denmark", "finland", "czech", "hungary", "bulgaria", "croatia", "serbia", "ukraine", "israel", "latino", "latin", "africa", "asia", "balkan",
    ]

    private static func delim(_ c: Unicode.Scalar) -> Bool {
        c == "|" || c == ":" || c == "-" || c == "\u{2013}" || c == "\u{BB}" || c == ">" || c == "/" || c == "\u{2022}"
    }

    private static func number(_ w: String) -> String {
        switch w {
        case "uno": return "1"
        case "due": return "2"
        case "tre": return "3"
        case "quattro": return "4"
        case "cinque": return "5"
        default: return w
        }
    }

    private static func isQuality(_ w: String) -> Bool {
        switch w {
        case "hd", "fhd", "uhd", "sd", "4k", "8k", "720p", "1080p", "1080i", "2160p", "hevc", "h265", "h264", "x265", "raw", "hq", "lq", "hdr": return true
        default: return false
        }
    }

    /// Canonical form of a channel name; `cat` (the provider's category) only contributes country / 4K hints.
    static func canon(_ raw: String?, _ cat: String?) -> Canon {
        var c = Canon()
        guard let raw = raw else { return c }
        var lowered: [Unicode.Scalar] = []
        for u in raw.decomposedStringWithCompatibilityMapping.unicodeScalars where u.properties.generalCategory != .nonspacingMark {
            lowered.append(contentsOf: lowerScalar(u).unicodeScalars)
        }
        let s = lowered
        let n = s.count
        var toks: [String] = []
        var inBr: [Bool] = []
        var after: [Unicode.Scalar] = []       // first non-space char following the token (delimiter detection)
        var adj: [Unicode.Scalar] = []         // the char right after the token ("Al-Jazeera": '-' is glued, "IT - Rai 1": ' ')
        var spaced: [Bool] = []                // a space follows the delimiter ("05. Rai 1")
        var depth = 0
        func text(_ a: Int, _ z: Int) -> String { String(String.UnicodeScalarView(s[a..<z])) }
        func note(_ j: Int) {
            var k = j
            while k < n && s[k] == " " { k += 1 }
            after.append(k < n ? s[k] : " ")
            adj.append(j < n ? s[j] : " ")
            spaced.append(j + 1 < n && s[j + 1] == " ")
        }
        var i = 0
        while i < n {
            let ch = s[i]
            if ch == "[" || ch == "(" || ch == "{" { depth += 1; i += 1; continue }
            if ch == "]" || ch == ")" || ch == "}" { if depth > 0 { depth -= 1 }; i += 1; continue }
            var j = i
            var pk = i + 1
            while ch == "+" && pk < n && s[pk] == " " { pk += 1 }                       // "+ 1" is "+1"
            if ch == "+" && pk < n && isDigitScalar(s[pk]) {
                j = pk
                while j < n && isDigitScalar(s[j]) { j += 1 }
                toks.append("+" + text(pk, j))
                inBr.append(depth > 0)
                note(j)
                i = j
                continue
            } else if isLetterOrDigit(ch) {
                while j < n && isLetterOrDigit(s[j]) { j += 1 }
            } else { i += 1; continue }
            toks.append(text(i, j))
            inBr.append(depth > 0)
            note(j)
            i = j
        }
        var out: [String] = []
        var t = 0
        while t < toks.count {
            defer { t += 1 }
            let w = toks[t]
            // a glued dash or dot is part of the name ("Al-Jazeera", "20.Mediaset"), a separated one is a prefix delimiter ("IT - Rai 1")
            let ad = adj[t]
            let glued = ad == "-" || ad == "\u{2013}" || ad == "."
            // leading numbering added by some providers: "001 - Rai 1", "12| Rai 1", "05. Rai 1", "7) Rai 1", "0042 Rai 1"
            if out.isEmpty && t == 0 && t + 1 < toks.count && w.allDigits() {
                let first0 = w.unicodeScalars.first == "0"
                let byDelim = ad == "|" || ad == ":" || ad == "\u{BB}" || ad == ">" || ad == "/"
                let byDot = (ad == "." || ad == ")") && spaced[t]
                let bySpace = ad == " " && delim(after[t]) && (w.count >= 3 || first0)
                if byDelim || byDot || bySpace || (w.count >= 3 && first0) { continue }
            }
            // leading provider prefixes: "IT |", "UK:", "[IT]" ... ("Italia 1" is a channel, "Italia - 1" is not a prefix either)
            if out.isEmpty && !glued && delim(after[t]) && t + 1 < toks.count {
                let nx = toks[t + 1]
                let numberNext = nx.allDigits() || number(nx).allDigits()
                if w == "it" || w == "ita" || w == "italy" { c.italian = true; continue }
                if w == "italia" && !numberNext { c.italian = true; continue }
                if foreign.contains(w) { c.country = w; continue }
            }
            if inBr[t] && !w.hasPrefix("+") && !isQuality(w) {
                if w == "it" || w == "ita" { c.italian = true }
                if foreign.contains(w) && out.isEmpty { c.country = w }
                continue                                    // "(Backup)", "[Europe]"...
            }
            switch w {
            case "hd", "720p", "hdtv": c.hd = true; continue
            case "fhd", "1080p", "1080i", "fullhd": c.fhd = true; continue
            case "uhd", "4k", "8k", "2160p": c.k4 = true; continue
            case "sd", "576p", "480p": c.sd = true; continue
            case "hevc", "h265", "x265": c.hevc = true; continue
            case "raw": c.raw = true; continue
            case "ita", "it", "italy": c.italian = true; continue
            case "h264", "x264", "hq", "lq", "ld", "hdr", "50fps", "60fps", "fps", "backup", "bkp", "vip",
                 "mpeg2", "mpeg4", "aac", "ac3", "1080", "720", "2160", "576", "480":
                continue
            case "h":
                if t + 1 < toks.count && (toks[t + 1] == "265" || toks[t + 1] == "264") {
                    if toks[t + 1] == "265" { c.hevc = true }
                    t += 1
                    continue
                }
            case "full":
                if t + 1 < toks.count && toks[t + 1] == "hd" { c.fhd = true; t += 1; continue }
            default:
                break
            }
            if w.hasPrefix("+") { out.append(w); continue }
            // split letter/digit boundaries: canale5 -> canale 5, tg24 -> tg 24
            let ws = Array(w.unicodeScalars)
            var start = 0
            for p in 1...ws.count {
                if p == ws.count || isDigitScalar(ws[p]) != isDigitScalar(ws[p - 1]) {
                    out.append(number(String(String.UnicodeScalarView(ws[start..<p]))))
                    start = p
                }
            }
        }
        // "plus 1" / "plus1" is the "+1" timeshift channel
        var pi = 0
        while pi + 1 < out.count {
            if out[pi] == "plus" && out[pi + 1].allDigits() && pi > 0 {
                out[pi] = "+" + out[pi + 1]
                out.remove(at: pi + 1)
            }
            pi += 1
        }
        if c.k4 && (c.fhd || c.hd) { c.k4 = false }          // "4K-FHD" in a name marks a mixed feed, not a 4K channel
        let both = (raw + " " + (cat ?? "")).lowercased()
        if both.contains("xxx") || both.contains("porn") || both.contains("18+") || both.contains("adult") || both.contains("erotic") { c.adult = true }
        if let cat = cat, !cat.isEmpty {
            let lc = Array(cat.lowercased().unicodeScalars)
            // a "4K - FHD" category mixes qualities: the name's own tag (HD, FHD, SD) wins; an untagged name there counts as 4K
            let lcs = String(String.UnicodeScalarView(lc))
            if (lcs.contains("4k") || lcs.contains("uhd")) && !c.hd && !c.fhd && !c.sd { c.k4 = true }
            var e = 0
            while e < lc.count && !isLetterOrDigit(lc[e]) { e += 1 }
            var f = e
            while f < lc.count && isLetterOrDigit(lc[f]) { f += 1 }
            if f > e {
                let w = String(String.UnicodeScalarView(lc[e..<f]))
                var g = f
                while g < lc.count && lc[g] == " " { g += 1 }
                let edge = g >= lc.count || delim(lc[g])
                if w == "italia" || w == "italy" || w == "italian" || w == "italiano" || w == "italiani" || ((w == "it" || w == "ita") && edge) {
                    c.italian = true
                } else if c.country.isEmpty && ((f - e <= 3 && foreign.contains(w) && edge) || countryWords.contains(w)) {
                    c.country = w
                }
            }
        }
        c.key = out.joined(separator: " ")
        return c
    }

    // MARK: matching

    fileprivate final class Cand {
        let item: Item
        let canon: Canon
        let approx: Bool                 // matched after dropping a network/brand word ("Discovery Nove" for "Nove")
        init(_ item: Item, _ canon: Canon, _ approx: Bool) { self.item = item; self.canon = canon; self.approx = approx }
    }

    /// The digits of a name in order ("sky sport 24 +1" -> "24+1"): names that differ in a number are never the same channel.
    private static func digitsOf(_ flat: String) -> String {
        var b = ""
        for u in flat.unicodeScalars where u == "+" || isDigitScalar(u) { b.unicodeScalars.append(u) }
        return b
    }

    private static func within1(_ a: String, _ b: String) -> Bool {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        let la = x.count, lb = y.count
        if abs(la - lb) > 1 { return false }
        var i = 0
        while i < la && i < lb && x[i] == y[i] { i += 1 }
        if i == la && i == lb { return true }
        if la == lb { return Array(x[(i + 1)...]) == Array(y[(i + 1)...]) }                // one substituted letter
        if la > lb { return Array(x[(i + 1)...]) == Array(y[i...]) }                       // one extra letter in a
        return Array(y[(i + 1)...]) == Array(x[i...])                                      // one extra letter in b
    }

    /// Words providers wrap around a channel name ("Sky MTV Italia", "Discovery Real Time", "Samsung+ Fashion TV").
    private static let brand: Set<String> = [
        "sky", "discovery", "mediaset", "samsung", "warner", "wbd", "pluto", "rakuten", "plex", "tv", "channel", "italia", "italy",
        "live", "diretto", "direct", "europe",
    ]

    private static let network: Set<String> = ["mediaset", "discovery", "warner", "wbd", "samsung", "pluto", "rakuten", "plex"]

    /// "mediaset extra" -> "extra" when the rest is a real name (not just digits or brand words); nil otherwise.
    static func trimNetwork(_ key: String) -> String? {
        let t = key.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var a = 0
        while a < t.count - 1 && network.contains(t[a]) { a += 1 }
        if a == 0 { return nil }
        var b = ""
        var real = false
        for i in a..<t.count {
            if !b.isEmpty { b += " " }
            b += t[i]
            if !t[i].allDigits(allowPlus: true) && !brand.contains(t[i]) { real = true }
        }
        return real && flat(b).unicodeScalars.count >= 4 ? b : nil
    }

    /// "4 words, spaces removed": "super tennis" and "supertennis", "motor trend" and "motortrend" are the same channel.
    static func flat(_ key: String) -> String {
        key.contains(" ") ? key.replacingOccurrences(of: " ", with: "") : key
    }

    /// Lookup table over the live channels of a library snapshot.
    public final class Index {
        fileprivate var byKey: [String: [Cand]] = [:]
        fileprivate var bySig: [String: [Cand]] = [:]        // exact candidates by their digits, for the typo tier
        fileprivate var cache: [String: Result] = [:]
        fileprivate let lock = NSLock()
        public private(set) var channels = 0

        init(_ sn: Library.Snap) {
            var n = 0
            for it in sn.items {
                if it.kind != .live || it.name.isEmpty { continue }
                let c = Packs.canon(it.name, it.cat)
                if c.key.isEmpty || c.adult { continue }
                let exact = Cand(it, c, false)
                let fk = Packs.flat(c.key)
                add(fk, exact)
                if fk.unicodeScalars.count >= 9 { bySig[Packs.digitsOf(fk), default: []].append(exact) }
                n += 1
                // brand-trimmed variants: drop up to two brand words at the start and/or at the end, keep at least one real word
                let t = c.key.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                var seen: Set<String> = [fk]
                for a in 0...2 {
                    for cut in 0...2 {
                        if a == 0 && cut == 0 { continue }
                        let z = t.count - cut
                        if z - a < 1 { continue }
                        var ok = true
                        for i in 0..<a where ok { ok = Packs.brand.contains(t[i]) }
                        if z < t.count { for i in z..<t.count where ok { ok = Packs.brand.contains(t[i]) } }
                        if !ok { continue }
                        var b = ""
                        var digitsOnly = true
                        for i in a..<z {
                            b += t[i]
                            if !t[i].allDigits(allowPlus: true) { digitsOnly = false }
                        }
                        if digitsOnly || !seen.insert(b).inserted { continue }
                        add(b, Cand(it, c, true))
                    }
                }
            }
            channels = n
        }

        private func add(_ k: String, _ cd: Cand) { byKey[k, default: []].append(cd) }
    }

    private static let indexLock = NSLock()
    private static var lastSnap: Library.Snap?
    private static var lastIndex: Index?

    public static func index(_ sn: Library.Snap) -> Index {
        indexLock.lock(); defer { indexLock.unlock() }
        if lastSnap !== sn || lastIndex == nil { lastIndex = Index(sn); lastSnap = sn }
        return lastIndex!
    }

    public final class Result {
        public let entry: Entry
        public let item: Item?           // nil = not found
        public let quality: String       // "HD", "FHD", "SD", "4K" or ""
        public let why: String           // for missing entries: "non trovato", "solo 4K (escluso)"
        init(_ e: Entry, _ it: Item?, _ q: String, _ why: String) { entry = e; item = it; quality = q; self.why = why }
    }

    private static func qualityName(_ c: Canon) -> String {
        if c.k4 { return "4K" }
        if c.hd { return "HD" }
        if c.fhd { return "FHD" }
        if c.sd { return "SD" }
        return ""
    }

    private static func score(_ g: Group, _ c: Canon, _ cd: Cand, _ primary: Bool, _ penalty: Int) -> Int {
        var s = 0
        if c.k4 { s -= 200 }
        else if c.hd { s += 40 }
        else if c.fhd { s += 35 }
        else if c.sd { s += 8 }
        else { s += 30 }
        if c.hevc { s -= 12 }
        if c.raw { s -= 4 }
        let cat = cd.item.cat.lowercased()
        if !g.prefer.isEmpty && cat.contains(g.prefer) { s += 60 }
        if !g.avoid.isEmpty && cat.contains(g.avoid) { s -= 60 }
        if primary { s += 5 }
        if cd.approx { s -= 25 }
        if c.italian { s += 12 }                      // an explicit "IT" marker beats an unmarked copy in an international list
        s -= penalty
        if let e = cd.item.epgId, !e.isEmpty { s += 3 }
        return s
    }

    public static func resolve(_ g: Group, _ e: Entry, _ idx: Index, allow4k: Bool) -> Result {
        let ck = g.id + "/" + e.id + "/" + String(allow4k)
        idx.lock.lock()
        if let hit = idx.cache[ck] { idx.lock.unlock(); return hit }
        idx.lock.unlock()
        let r = resolveUncached(g, e, idx, allow4k)
        idx.lock.lock(); idx.cache[ck] = r; idx.lock.unlock()
        return r
    }

    private struct Pick {
        var best: Cand?
        var score = Int.min
        var saw4k = false
    }

    private static func consider(_ g: Group, _ e: Entry, _ l: [Cand]?, _ primary: Bool, _ penalty: Int, _ allow4k: Bool, _ p: inout Pick) {
        guard let l = l else { return }
        for cd in l {
            if !g.anyCountry && !cd.canon.country.isEmpty { continue }       // "UK | Eurosport": a foreign copy is worse than none
            let c4k = cd.canon.k4
            if e.four {                                   // a 4K entry only takes 4K channels, and only when 4K is allowed
                if !c4k { continue }
                if !allow4k { p.saw4k = true; continue }
            } else if c4k {                               // a 4K twin of an HD entry: last resort, ranked below everything else
                if !allow4k { p.saw4k = true; continue }
            }
            let sc = score(g, cd.canon, cd, primary, penalty)
            if sc > p.score { p.score = sc; p.best = cd }
        }
    }

    private static func resolveUncached(_ g: Group, _ e: Entry, _ idx: Index, _ allow4k: Bool) -> Result {
        var p = Pick()
        for (a, k) in e.keys.enumerated() { consider(g, e, idx.byKey[flat(k)], a == 0, 0, allow4k, &p) }
        for k in e.approx { consider(g, e, idx.byKey[flat(k)], false, 20, allow4k, &p) }
        if p.best == nil {
            // last tier: one wrong letter in a long name ("Atlantik", "Monecarlo"); the numbers must be identical
            for k in e.keys {
                let fk = flat(k)
                if fk.unicodeScalars.count < 9 { continue }
                guard let l = idx.bySig[digitsOf(fk)] else { continue }
                let near = l.filter { within1(fk, flat($0.canon.key)) }
                consider(g, e, near, false, 45, allow4k, &p)
            }
        }
        guard let best = p.best else { return Result(e, nil, "", p.saw4k ? "solo 4K (escluso)" : "non trovato") }
        return Result(e, best.item, qualityName(best.canon), "")
    }

    /// Comparable forms of a spelling: its own and the ones without brand words (public for tests).
    public static func variantFlats(_ name: String) -> Set<String> {
        let c = canon(name, "")
        var out = variants(c.key)
        out.insert(flat(c.key))
        return out
    }

    /// The comparable form of a channel name (public for diagnostics and tests).
    public static func flatKey(_ name: String) -> String { flat(canon(name, "").key) }

    /// True when two provider spellings are the same channel (equal, or equal after dropping brand words). Used by tests.
    public static func sameChannel(_ a: String, _ b: String) -> Bool {
        let x = canon(a, ""), y = canon(b, "")
        if flat(x.key) == flat(y.key) { return true }
        return !variants(x.key).isDisjoint(with: variants(y.key))
    }

    private static func variants(_ key: String) -> Set<String> {
        var out = Set<String>()
        let t = key.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for a in 0...2 {
            for cut in 0...2 {
                let z = t.count - cut
                if z - a < 1 { continue }
                var ok = true
                for i in 0..<a where ok { ok = brand.contains(t[i]) || network.contains(t[i]) }
                if z < t.count { for i in z..<t.count where ok { ok = brand.contains(t[i]) } }
                if !ok { continue }
                out.insert(t[a..<z].joined())
            }
        }
        return out
    }

    /// Resolves a whole group in definition order.
    public static func resolve(_ g: Group, _ idx: Index, allow4k: Bool) -> [Result] {
        g.entries.map { resolve(g, $0, idx, allow4k: allow4k) }
    }

    /// (entry id, channel key) for every enabled group, in definition order (the profile's own set removes duplicates).
    public static func resolveAll(enabled: OrderedKeySet, off: OrderedKeySet, _ idx: Index, allow4k: Bool) -> [(entry: String, key: String)] {
        var out: [(entry: String, key: String)] = []
        var seen = Set<String>()
        for g in groups where enabled.contains(g.id) {
            for e in g.entries where !off.contains(e.id) {
                let r = resolve(g, e, idx, allow4k: allow4k)
                if let it = r.item, seen.insert(e.id).inserted { out.append((e.id, it.key)) }
            }
        }
        return out
    }
}
