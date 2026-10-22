import Foundation

// MARK: view models

/// A poster / tile as the screens need it.
public struct Card: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let kind: Kind
    public let name: String
    public let logo: String?
    public let extra: String
    public let added: Int
    public let rate: Double              // 0 = unknown
    public let progress: Int64           // resume position in ms (0 = none)
    public let duration: Int64

    public var fraction: Double? {
        guard progress > 0, duration > 0 else { return nil }
        return min(1, Double(progress) / Double(duration))
    }

    /// "Film (2026)" -> "Film"
    public var title: String { Backend.cleanTitle(name) }
}

public struct Row: Identifiable, Sendable {
    public var id: String { rowId + "|" + title }
    public let rowId: String             // trend, recent, top, because, cat
    public let title: String
    public let total: Int
    public let items: [Card]
    public let cats: [String]?           // category rows can be paged: these are the categories behind them
    public let genre: String?
}

public struct LiveChannel: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let num: Int
    public let name: String
    public let logo: String?
    public let cat: String
    public let fav: Bool
    public let hasEpg: Bool
    public let radio: Bool
}

public struct SearchResults: Sendable {
    public var live: [Card] = [], movies: [Card] = [], series: [Card] = []
    public var liveTotal = 0, moviesTotal = 0, seriesTotal = 0
    public init() {}
    public var isEmpty: Bool { live.isEmpty && movies.isEmpty && series.isEmpty }
}

public struct CatInfo: Identifiable, Hashable, Sendable {
    public var id: String { "\(src)|\(name)" }
    public let src: Int
    public let name: String
    public let label: String
    public let count: Int
    public let selected: Int
}

public struct PackInfo: Identifiable, Sendable {
    public var id: String { group }
    public let group: String
    public let title: String
    public let desc: String
    public let total: Int
    public let found: Int
    public let enabled: Bool
    public let missing: [String]
}

public struct PackEntryInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let found: Bool
    public let chosen: String
    public let quality: String
    public let why: String
    public let off: Bool
}

public struct QualityOption: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let code: String
    public let label: String
    public let current: Bool
}

// MARK: helpers

extension Backend {
    /// "Film (2026)" -> "Film"
    public static func cleanTitle(_ name: String) -> String {
        let ns = name as NSString
        return yearSuffix.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmed
    }

    private static let yearSuffix = try! NSRegularExpression(pattern: "\\s*\\((?:19|20)\\d\\d\\)\\s*$")

    private static let titleKeyBrackets = try! NSRegularExpression(pattern: "\\[[^\\]]*\\]")
    private static let titleKeyTags = try! NSRegularExpression(pattern: "\\b(4k|uhd|fhd|hevc|h265|h 265|multi|sub ?ita|ita)\\b")

    /// Same film listed twice (other category, other quality): equal after dropping punctuation, bracket tags and quality words.
    static func titleKey(_ name: String) -> String {
        var t = name.lowercased()
        t = titleKeyBrackets.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: " ")
        t = titleKeyTags.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: " ")
        var out = ""
        for u in t.unicodeScalars where isLetterOrDigit(u) { out.unicodeScalars.append(u) }
        return out
    }

    /// Rating out of 10 as the provider wrote it in `extra` ("2025  7.4", "8.1", "78%"); 0 when there is none.
    static func ratingOf(_ it: Item) -> Double {
        guard let ex = it.extra, !ex.isEmpty else { return 0 }
        var t = ex.trimmed
        if let sp = t.lastIndex(of: " ") { t = String(t[t.index(after: sp)...]) }
        if t.hasSuffix("%") { t.removeLast() }
        if t.count == 4, t.allDigits(), t.hasPrefix("19") || t.hasPrefix("20") { return 0 }       // a year ("2026"), not a rating
        guard let v = Double(t.replacingOccurrences(of: ",", with: ".")), v >= 0, v <= 100 else { return 0 }
        return v > 10 ? v / 10 : v                                                                   // some panels rate out of 100
    }

    static func rateOf(_ it: Item) -> Float {
        if it.rate < 0 { it.rate = Float(ratingOf(it)) }
        return it.rate
    }

    /// Adult categories stay out of sight unless switched on in expert mode, and always for protected profiles.
    public func hideAdult(_ p: Profile?) -> Bool { !settings.bool("showAdult", false) || (p?.kids ?? false) }

    func card(_ it: Item, _ p: Profile?) -> Card {
        let r = Backend.rateOf(it)
        return Card(key: it.key, kind: it.kind, name: it.name, logo: it.logo, extra: it.extra ?? "", added: it.added,
                    rate: r > 0 ? (Double(r) * 10).rounded() / 10 : 0, progress: p?.resume[it.key] ?? 0, duration: p?.done[it.key] ?? 0)
    }

    // MARK: Netflix style rows

    /// Keeps the `cap` best items seen (a min-heap whose root is the worst of them).
    private struct BoundedHeap {
        let cap: Int
        let worse: (Item, Item) -> Bool          // a is worse than b
        var a: [Item] = []

        init(cap: Int, worse: @escaping (Item, Item) -> Bool) { self.cap = cap; self.worse = worse }

        mutating func offer(_ x: Item) {
            if a.count < cap {
                a.append(x)
                var i = a.count - 1
                while i > 0 {
                    let p = (i - 1) / 2
                    if worse(a[i], a[p]) { a.swapAt(i, p); i = p } else { break }
                }
            } else if !a.isEmpty && worse(a[0], x) {
                a[0] = x
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < a.count && worse(a[l], a[m]) { m = l }
                    if r < a.count && worse(a[r], a[m]) { m = r }
                    if m == i { break }
                    a.swapAt(i, m)
                    i = m
                }
            }
        }

        func bestFirst() -> [Item] { a.sorted { worse($1, $0) } }
    }

    private static let olderFirst: (Item, Item) -> Bool = { $0.added < $1.added }
    private static let worseFirst: (Item, Item) -> Bool = { a, b in
        let x = Backend.rateOf(a), y = Backend.rateOf(b)
        return x != y ? x < y : a.added < b.added
    }

    private final class CatAcc {
        var count = 0
        var genre: String?
        var head: [Item] = []
    }

    private struct RowPlan {
        let id: String, title: String, total: Int, items: [Item], cats: [String]?
        var genre: String?
    }

    /// Rows for the movies / series pages, whatever the provider calls its categories: what is trending (the provider's own
    /// "most watched / new" categories, or recent + well rated), recently added, top rated, "because you watched", then one row per
    /// genre (categories with the same genre merged, in a fixed sensible order), then every other category (platforms, years,
    /// collections) in the provider's order. One pass over the selection keeps only a few candidates per row, so a 100,000-film
    /// profile costs milliseconds, not seconds; rows are produced from `offset` on, `limit` at a time.
    /// The titles a page is built from: the whole catalogue (`all`) or what the profile keeps in its list.
    func pool(_ p: Profile, _ kind: Kind, all: Bool, _ sn: Library.Snap) -> [Item] {
        all ? sn.items.filter { $0.kind == kind } : p.set(kind).compactMap { sn.byKey[$0] }
    }

    public func vodRows(profile p: Profile, kind: Kind, per: Int = 30, offset: Int = 0, limit: Int = Int.max, only: Set<String>? = nil, all: Bool = false) -> (total: Int, rows: [Row]) {
        let sn = lib.snap
        let n = max(per * 3, 12), keep = per * 2 + 4
        let noAdult = hideAdult(p)
        var cats: [String: CatAcc] = [:]
        let tmdb = kind == .movie && settings.get("tmdbGenres", "1") == "1"
        var tg: [String: BoundedHeap] = [:]                              // TMDB genre -> best films
        var gtotal: [String: Int] = [:]                                  // genre -> films in it (by category name or TMDB, once each)
        var recentQ = BoundedHeap(cap: n, worse: Backend.olderFirst)
        var topQ = BoundedHeap(cap: n, worse: Backend.worseFirst)
        var hotQ = BoundedHeap(cap: n, worse: Backend.worseFirst)
        let hotAfter = Int(Date().timeIntervalSince1970) - 45 * 86400
        for it in pool(p, kind, all: all, sn) {
            if Hash.isSeparator(it.name) { continue }                                         // list banners saved by an older version
            if noAdult && Genres.isAdult(it.cat) { continue }
            let c: CatAcc
            if let e = cats[it.cat] { c = e } else {
                c = CatAcc()
                c.genre = Genres.isTrending(it.cat) ? nil : Genres.of(it.cat)
                cats[it.cat] = c
            }
            c.count += 1
            if c.head.count < keep { c.head.append(it) }
            var gtmp: [String] = []
            if let g = c.genre { gtmp.append(g) }
            if tmdb, let gs = genres.get(it.key), !gs.isEmpty {
                for g in gs.split(separator: "|").map(String.init) {
                    tg[g, default: BoundedHeap(cap: keep, worse: Backend.worseFirst)].offer(it)
                    if !gtmp.contains(g) { gtmp.append(g) }
                }
            }
            for g in gtmp { gtotal[g, default: 0] += 1 }
            if it.added > 0 { recentQ.offer(it) }
            let r = Backend.rateOf(it)
            if r > 0 {
                topQ.offer(it)
                if it.added > hotAfter && r >= 6 { hotQ.offer(it) }
            }
        }
        var order: [String: Int] = [:]
        var oi = 0
        for s in lib.sources { for c in sn.categories(src: s.id, kind: kind) where order[c.name] == nil { order[c.name] = oi; oi += 1 } }
        let names = cats.keys.sorted { (order[$0] ?? Int.max) < (order[$1] ?? Int.max) }

        var plan: [RowPlan] = []
        // 1. trending: the provider's own popular / new categories, else recent and well rated
        let trendCats = names.filter { Genres.isTrending($0) }
        if trendCats.isEmpty {
            let hot = hotQ.bestFirst()
            if hot.count >= 6 { plan.append(RowPlan(id: "trend", title: "Di tendenza", total: hot.count, items: hot, cats: nil)) }
        } else {
            for c in trendCats {
                plan.append(RowPlan(id: "cat", title: trendCats.count == 1 ? "Di tendenza" : c, total: cats[c]!.count, items: cats[c]!.head, cats: [c]))
            }
        }
        // 2. recently added, 3. top rated
        let recent = recentQ.bestFirst()
        if recent.count >= 4 { plan.append(RowPlan(id: "recent", title: kind == .movie ? "Film aggiunti di recente" : "Serie aggiunte di recente", total: recent.count, items: recent, cats: nil)) }
        let top = topQ.bestFirst()
        if top.count >= 6 { plan.append(RowPlan(id: "top", title: "I più votati", total: top.count, items: top, cats: nil)) }
        // 4. because you watched: more from the category of the last thing watched
        var lastKey: String?
        var lastAt: Int64 = 0
        for (k, at) in p.resumeAt where at > lastAt { lastAt = at; lastKey = p.resumeParent[k] ?? k }
        if let lk = lastKey, let seen = sn.byKey[lk], seen.kind == kind, let acc = cats[seen.cat] {
            let more = acc.head.filter { $0.key != seen.key && p.resume[$0.key] == nil }
            if more.count >= 6 { plan.append(RowPlan(id: "because", title: "Perché hai guardato «\(Backend.cleanTitle(seen.name))»", total: more.count, items: more, cats: nil)) }
        }
        // 5. genres: categories that are just a genre (merged) plus what TMDB says about films in any category, 6. everything else
        var genreCats: [String: [String]] = [:]
        var genreOrder: [String] = []
        var others: [String] = []
        for c in names {
            if trendCats.contains(c) { continue }
            guard let g = cats[c]!.genre else { others.append(c); continue }
            if genreCats[g] == nil { genreOrder.append(g) }
            genreCats[g, default: []].append(c)
        }
        var genreNames = genreOrder
        for g in tg.keys.sorted() where genreCats[g] == nil { genreNames.append(g) }
        genreNames = genreNames.enumerated().sorted { (Genres.rank($0.element), $0.offset) < (Genres.rank($1.element), $1.offset) }.map { $0.element }
        for g in genreNames {
            let cs = genreCats[g] ?? []
            var items: [Item] = tg[g]?.bestFirst() ?? []                      // what TMDB says is this genre, best first
            for c in cs { items.append(contentsOf: cats[c]!.head) }
            var rp = RowPlan(id: "cat", title: g, total: gtotal[g] ?? items.count, items: items, cats: cs)
            rp.genre = g
            if items.count >= (cs.isEmpty ? 6 : 1) { plan.append(rp) }        // a genre known only from TMDB needs a few films to be a row
        }
        for c in others { plan.append(RowPlan(id: "cat", title: c, total: cats[c]!.count, items: cats[c]!.head, cats: [c])) }

        var rows: [Row] = []
        var seenRows = 0
        for r in plan {
            if let o = only, !o.contains(r.id) { continue }
            let idx = seenRows
            seenRows += 1
            if idx < offset || rows.count >= limit { continue }
            var unique: [Item] = []
            var inRow = Set<String>()
            for it in r.items {
                if unique.count >= per { break }
                if inRow.insert(Backend.titleKey(it.name)).inserted { unique.append(it) }
            }
            // only category rows page (their cats tell the page what to ask for); the others are cut at `per`
            let paged = r.cats != nil
            rows.append(Row(rowId: r.id, title: r.title, total: paged ? r.total : unique.count, items: unique.map { card($0, p) }, cats: r.cats, genre: r.genre))
        }
        return (seenRows, rows)
    }

    /// The items of a profile's selection, filtered by categories (or a genre), paged: the "see all" screen of a row.
    public func vodItems(profile p: Profile, kind: Kind, cats: [String]? = nil, genre: String? = nil, offset: Int = 0, limit: Int = 60, all: Bool = false) -> (total: Int, items: [Card]) {
        let sn = lib.snap
        let catSet = cats.map { Set($0) }
        var out: [Card] = []
        var total = 0
        let noAdult = hideAdult(p)
        for it in pool(p, kind, all: all, sn) {
            if noAdult && Genres.isAdult(it.cat) { continue }
            if let g = genre, !g.isEmpty {
                let gs = genres.get(it.key)
                let byTmdb = gs.map { ("|" + $0 + "|").contains("|" + g + "|") } ?? false
                if !byTmdb && !(catSet?.contains(it.cat) ?? false) { continue }
            } else if let cs = catSet, !cs.contains(it.cat) { continue }
            if total >= offset && out.count < limit { out.append(card(it, p)) }
            total += 1
        }
        return (total, out)
    }

    /// Categories of a profile's selection with their counts (the filter chips of the movies / series pages).
    public func vodCategories(profile p: Profile, kind: Kind) -> [(name: String, count: Int)] {
        let sn = lib.snap
        var counts: [String: Int] = [:]
        var order: [String] = []
        let noAdult = hideAdult(p)
        for k in p.set(kind) {
            guard let it = sn.byKey[k] else { continue }
            if noAdult && Genres.isAdult(it.cat) { continue }
            if counts[it.cat] == nil { order.append(it.cat) }
            counts[it.cat, default: 0] += 1
        }
        return order.map { ($0, counts[$0]!) }
    }

    // MARK: continue watching

    /// Films and episodes started and not finished, newest first; episodes show up as their series.
    public func continueWatching(profile p: Profile, limit: Int = 20) -> [Card] {
        let sn = lib.snap
        var seen = Set<String>()
        var out: [Card] = []
        for (k, _) in p.resumeAt.sorted(by: { $0.value > $1.value }) {
            guard let pos = p.resume[k] else { continue }
            let showKey = p.resumeParent[k]
            let shown = showKey ?? k
            guard let it = sn.byKey[shown], seen.insert(shown).inserted else { continue }
            if it.kind == .live { continue }
            out.append(Card(key: it.key, kind: it.kind, name: it.name, logo: it.logo, extra: p.resumeLabel[k] ?? (it.extra ?? ""), added: it.added,
                            rate: 0, progress: pos, duration: p.done[k] ?? 0))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: search

    /// The search box: every word typed must appear in the name (accents and case ignored). Results of the three catalogues in one
    /// pass, best matches first (name starts with the text, then a word starts with it, then anywhere). Needs at least 3 letters.
    public func search(_ text: String, profile p: Profile, everything: Bool = false, limit: Int = 60) -> SearchResults {
        let q = Hash.fold(text).trimmed
        var res = SearchResults()
        if q.unicodeScalars.count < 3 { return res }
        let noAdult = hideAdult(p)
        let toks = q.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let first = toks[0]
        let sn = lib.snap
        var hits: [[(Item, Int)]] = [[], [], []]
        var found = [0, 0, 0]
        let cap = 4000
        func consider(_ x: Item) {
            let kr = x.kind.rawValue
            if kr < 0 || kr > 2 { return }
            if noAdult && Genres.isAdult(x.cat) { return }
            let sk = Library.searchKey(x)
            for t in toks where !sk.contains(t) { return }
            found[kr] += 1
            if hits[kr].count < cap { hits[kr].append((x, sk.hasPrefix(first) ? 3 : sk.contains(" " + first) ? 2 : 1)) }
        }
        if everything { for x in sn.items { consider(x) } }
        else { for kind in [Kind.live, .movie, .series] { for key in p.set(kind) { if let x = sn.byKey[key] { consider(x) } } } }
        for k in 0..<3 {
            let l = hits[k].sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
            var rows: [Card] = []
            var seenTitle = Set<String>()
            var dups = 0
            for (x, _) in l {
                if k != 0 && !seenTitle.insert(Backend.titleKey(x.name)).inserted { dups += 1; continue }       // the same film in several categories / qualities: once
                if rows.count >= limit { continue }
                rows.append(card(x, p))
            }
            let total = max(rows.count, found[k] - dups)
            switch k {
            case 0: res.live = rows; res.liveTotal = total
            case 1: res.movies = rows; res.moviesTotal = total
            default: res.series = rows; res.seriesTotal = total
            }
        }
        return res
    }

    /// Works out the folded names in the background so the first letters typed in Search are answered at once.
    public func warmSearch() { for it in lib.snap.items { _ = Library.searchKey(it) } }

    // MARK: live

    public func liveList(profile p: Profile) -> [LiveChannel] {
        let sn = lib.snap
        let titles = packTitles(p), names = packNames(p)
        let favs = Set(p.favs)
        var out: [LiveChannel] = []
        var n = 0
        for k in p.live {
            guard let it = sn.byKey[k] else { continue }
            n += 1
            let pt = titles[k]
            let radio = pt == "Radio" || it.cat.lowercased().contains("radio")
            out.append(LiveChannel(key: k, num: n, name: names[k] ?? Packs.cleanName(it.name), logo: it.logo, cat: pt ?? it.cat,
                                   fav: favs.contains(k), hasEpg: epgKey(it) != nil, radio: radio))
        }
        return out
    }

    public func nowNext(keys: [String], now: Int64 = Int64(Date().timeIntervalSince1970)) -> [String: (now: Prog?, next: Prog?)] {
        let sn = lib.snap
        var out: [String: (now: Prog?, next: Prog?)] = [:]
        for k in keys {
            guard let it = sn.byKey[k], let ek = epgKey(it) else { continue }
            let nn = epg.nowNext(ek, now: now)
            if nn.now == nil && nn.next == nil { continue }
            out[k] = nn
        }
        return out
    }

    public func epgWindow(keys: [String], from: Int64, to: Int64) -> [String: [Prog]] {
        let sn = lib.snap
        var out: [String: [Prog]] = [:]
        for k in keys { out[k] = sn.byKey[k].map { epg.range(epgKey($0), from: from, to: to) } ?? [] }
        return out
    }

    public func item(_ key: String) -> Item? { lib.snap.byKey[key] }

    public func cards(_ keys: [String], profile p: Profile?) -> [Card] {
        let sn = lib.snap
        return keys.compactMap { sn.byKey[$0].map { card($0, p) } }
    }

    // MARK: qualities of a channel

    private static let variantCache = Variants.Cache()

    /// The other qualities of a channel that the list itself declares (see `Variants`); empty when there is no choice.
    public func qualityOptions(for key: String) -> (current: Int, options: [QualityOption], sure: Bool) {
        let sn = lib.snap
        guard let it = sn.byKey[key], it.kind == .live else { return (Variants.undeclared, [], false) }
        let mine = Variants.parse(it.name).quality
        let g = Backend.variantCache.index(sn).group(of: key)
        var opts: [QualityOption] = []
        if let g = g {
            for i in 0..<g.keys.count {
                opts.append(QualityOption(key: g.keys[i], code: Variants.code(g.q[i]) ?? "STD", label: Variants.label(g.q[i]), current: g.q[i] == mine))
            }
        }
        return (mine, opts, g?.strong ?? false)
    }

    /// Builds the index of qualities in the background shortly after a channel starts, so the quality list opens at once.
    public func warmVariants() { _ = Backend.variantCache.index(lib.snap) }

    /// Applies the quality the viewer chose earlier for this channel, if (and only if) the channel really has it. Nothing is invented.
    public func withPreferredQuality(_ it: Item, profile p: Profile?) -> Item {
        guard let p = p, p.hasQualityPrefs else { return it }
        let want = Variants.fromCode(p.quality(Variants.anchor(it)))
        if want == Variants.conflict || Variants.parse(it.name).quality == want { return it }
        let sn = lib.snap
        guard let g = Backend.variantCache.index(sn).group(of: it.key) else { return it }
        let i = g.indexOfQuality(want)
        return i < 0 ? it : (sn.byKey[g.keys[i]] ?? it)
    }

    // MARK: profile actions

    @discardableResult
    public func toggleFav(_ profileId: String, key: String) -> Bool {
        var on = false
        profiles.update(profileId, light: true) { p in
            if let i = p.favs.firstIndex(of: key) { p.favs.remove(at: i); on = false } else { p.favs.append(key); on = true }
        }
        return on
    }

    public func touchRecent(_ profileId: String, key: String) {
        let isLive = lib.snap.byKey[key]?.kind == .live
        profiles.update(profileId, light: true) { p in
            p.touchRecent(key)
            if isLive { p.last = key }
        }
    }

    public func saveResume(_ profileId: String, key: String, pos: Int64, dur: Int64, parent: String?, label: String?) {
        profiles.update(profileId, light: true) { $0.saveResume(key, pos: pos, dur: dur, parent: parent, label: label) }
    }

    public func clearResume(_ profileId: String, key: String? = nil) {
        profiles.update(profileId, light: true) { p in
            if let k = key { p.clearResume(k) } else { for k in Array(p.resume.keys) { p.clearResume(k) } }
        }
    }

    public func setQuality(_ profileId: String, key: String, code: String) {
        guard let it = lib.snap.byKey[key], it.kind == .live, Variants.fromCode(code) != Variants.conflict else { return }
        profiles.update(profileId, light: true) { $0.setQuality(Variants.anchor(it), code) }
    }

    // MARK: choosing the content (set-up screens)

    public func libCategories(profile p: Profile?, kind: Kind, src: Int = -1) -> [CatInfo] {
        let sn = lib.snap
        var sel: [String: Int] = [:]
        if let p = p { for k in p.set(kind) { if let it = sn.byKey[k] { sel["\(it.src)|\(it.cat)", default: 0] += 1 } } }
        let sources = lib.sources
        let noAdult = hideAdult(p)
        var out: [CatInfo] = []
        for s in sources where src < 0 || s.id == src {
            for c in sn.categories(src: s.id, kind: kind) {
                if noAdult && Genres.isAdult(c.name) { continue }
                out.append(CatInfo(src: s.id, name: c.name, label: sources.count > 1 && src < 0 ? c.name + "  ·  " + s.name : c.name,
                                   count: c.count, selected: sel["\(s.id)|\(c.name)"] ?? 0))
            }
        }
        return out
    }

    public struct Brief: Identifiable, Hashable, Sendable {
        public var id: String { key }
        public let key: String, name: String, cat: String
        public let logo: String?
        public let src: Int
        public let kind: Kind
        public let extra: String
        public let selected: Bool
    }

    public func libItems(profile p: Profile?, kind: Kind, src: Int = -1, cat: String? = nil, query: String = "", selectedOnly: Bool = false, offset: Int = 0, limit: Int = 60) -> (total: Int, items: [Brief]) {
        let sn = lib.snap
        func brief(_ it: Item) -> Brief {
            Brief(key: it.key, name: it.name, cat: it.cat, logo: it.logo, src: it.src, kind: it.kind, extra: it.extra ?? "", selected: p?.has(it.kind, it.key) ?? false)
        }
        let noAdult = hideAdult(p)
        if selectedOnly, let p = p {
            let toks = query.lowercased().trimmed.split(separator: " ").map(String.init)
            var out: [Brief] = []
            var total = 0
            for k in p.set(kind) {
                guard let it = sn.byKey[k] else { continue }
                if src >= 0 && it.src != src { continue }
                if let c = cat, !c.isEmpty, c != it.cat { continue }
                if noAdult && Genres.isAdult(it.cat) { continue }
                let n = it.name.lowercased()
                if !toks.allSatisfy({ n.contains($0) }) { continue }
                if total >= offset && out.count < limit { out.append(brief(it)) }
                total += 1
            }
            return (total, out)
        }
        let r = sn.search(src: src, kind: kind, cat: (cat?.isEmpty ?? true) ? nil : cat, query: query, offset: offset, limit: limit, noAdult: noAdult)
        return (r.total, r.items.map(brief))
    }

    /// Adds or removes items from a profile's selection; returns how many are selected afterwards.
    @discardableResult
    public func select(_ profileId: String, kind: Kind, keys: [String], on: Bool) -> Int {
        var count = 0
        profiles.update(profileId) { p in
            if on { p.update(kind) { s in for k in keys { s.insert(k) } } }
            else {
                p.update(kind) { s in s.remove(contentsOf: keys) }
                if kind == .live { p.packForget(Set(keys)) }
            }
            count = p.set(kind).count
        }
        return count
    }

    @discardableResult
    public func selectCategory(_ profileId: String, kind: Kind, src: Int, cat: String, on: Bool) -> Int {
        let sn = lib.snap
        let items = src >= 0 ? sn.inCategory(src: src, kind: kind, cat: cat) : sn.search(kind: kind, cat: cat).items
        return select(profileId, kind: kind, keys: items.map { $0.key }, on: on)
    }

    @discardableResult
    public func selectQuery(_ profileId: String, kind: Kind, src: Int, cat: String?, query: String, on: Bool) -> Int {
        let p = profiles.get(profileId)
        let items = lib.snap.search(src: src, kind: kind, cat: cat, query: query, noAdult: hideAdult(p)).items
        return select(profileId, kind: kind, keys: items.map { $0.key }, on: on)
    }

    public func clearSelection(_ profileId: String, kind: Kind) {
        profiles.update(profileId) { p in
            if kind == .live { p.packForget(p.live.keySet) }
            p.update(kind) { $0.removeAll() }
        }
    }

    public func moveSelected(_ profileId: String, kind: Kind, key: String, by dir: Int) {
        profiles.update(profileId) { p in
            p.update(kind) { s in
                var l = s.array
                guard let i = l.firstIndex(of: key), l.indices.contains(i + dir) else { return }
                l.swapAt(i, i + dir)
                s.reorder(l)
            }
        }
    }

    public func moveSelected(_ profileId: String, kind: Kind, from: IndexSet, to: Int) {
        profiles.update(profileId) { p in
            p.update(kind) { s in
                var l = s.array
                let moving = from.sorted().map { l[$0] }
                for i in from.sorted(by: >) { l.remove(at: i) }
                l.insert(contentsOf: moving, at: to - from.filter { $0 < to }.count)       // same as SwiftUI's onMove contract
                s.reorder(l)
            }
        }
    }

    public func sortSelected(_ profileId: String, kind: Kind, byCategory: Bool) {
        let sn = lib.snap
        profiles.update(profileId) { p in
            p.update(kind) { s in
                let l = s.array.sorted { x, y in
                    guard let a = sn.byKey[x], let b = sn.byKey[y] else { return sn.byKey[x] != nil }
                    if byCategory {
                        let c = a.cat.caseInsensitiveCompare(b.cat)
                        if c != .orderedSame { return c == .orderedAscending }
                    }
                    return a.name.caseInsensitiveCompare(b.name) == .orderedAscending
                }
                s.reorder(l)
            }
        }
    }

    public func copySelection(from: String, to: String) {
        guard let f = profiles.get(from) else { return }
        profiles.update(to) { t in t.live = f.live; t.movies = f.movies; t.series = f.series }
    }

    // MARK: packs

    public func packsList(profile p: Profile) -> [PackInfo] {
        let idx = Packs.index(lib.snap)
        let k4 = allow4k
        return Packs.groups.map { g in
            var found = 0
            var missing: [String] = []
            for e in g.entries {
                if Packs.resolve(g, e, idx, allow4k: k4).item != nil { found += 1 } else if missing.count < 6 { missing.append(e.name) }
            }
            return PackInfo(group: g.id, title: g.title, desc: g.desc, total: g.entries.count, found: found, enabled: p.packs.contains(g.id), missing: missing)
        }
    }

    public func packDetail(profile p: Profile, group gid: String) -> [PackEntryInfo] {
        guard let g = Packs.group(gid) else { return [] }
        let idx = Packs.index(lib.snap)
        let k4 = allow4k
        return g.entries.map { e in
            let r = Packs.resolve(g, e, idx, allow4k: k4)
            return PackEntryInfo(name: e.name, found: r.item != nil, chosen: r.item?.name ?? "", quality: r.quality, why: r.why, off: p.packOff.contains(e.id))
        }
    }

    public func setPack(_ profileId: String, group gid: String, on: Bool) {
        guard let g = Packs.group(gid) else { return }
        profiles.update(profileId) { p in
            if on {
                p.packs.insert(gid)
                for e in g.entries { p.packOff.remove(e.id) }
            } else { p.packs.remove(gid) }
        }
        syncPacks(profileId)
    }
}
