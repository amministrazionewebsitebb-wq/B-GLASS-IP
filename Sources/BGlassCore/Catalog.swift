import Foundation

/// Which channels the TV page shows.
public enum LiveFilter: Hashable, Sendable {
    /// The well known channels, found by name in the list (see `mainChannels`) and numbered like a TV remote.
    case main
    case favorites
    case all
    case category(src: Int, name: String)
}

public struct LiveCategory: Identifiable, Hashable, Sendable {
    public var id: String { "\(src)|\(name)" }
    public let src: Int
    public let name: String
    public let label: String
    public let count: Int
}

extension Backend {
    /// Packs that make the "main" channel list (radio and foreign news stay out of it).
    static let mainGroups = ["intrattenimento", "sport", "cinema", "documentari", "news_it", "bambini", "musica", "altri"]

    private static let mainLock = NSLock()
    private static var mainSnap: Library.Snap?
    private static var mainList: [(key: String, name: String)] = []

    /// "Sky Cinema Uno HD" -> "Sky Cinema Uno": the packs name the HD feed, the viewer just wants the channel.
    static func plainChannelName(_ n: String) -> String {
        for suffix in [" HD", " FHD", " UHD"] where n.hasSuffix(suffix) { return String(n.dropLast(suffix.count)) }
        return n
    }

    /// The channels a viewer looks for first (Rai, Mediaset, Sky, sport, cinema, news, kids...), picked out of the list by the pack
    /// matcher, in a fixed sensible order, with clean names. Nobody has to choose anything: it is worked out once per catalogue.
    public func mainChannels() -> [(key: String, name: String)] {
        let sn = lib.snap
        Backend.mainLock.lock()
        if Backend.mainSnap === sn { let l = Backend.mainList; Backend.mainLock.unlock(); return l }
        Backend.mainLock.unlock()
        let idx = Packs.index(sn)
        var out: [(key: String, name: String)] = []
        var seen = Set<String>()
        for gid in Backend.mainGroups {
            guard let g = Packs.group(gid) else { continue }
            for e in g.entries {
                let r = Packs.resolve(g, e, idx, allow4k: false)
                guard let it = r.item, !it.cat.lowercased().contains("radio") else { continue }          // a TV list: radios stay out
                if seen.insert(it.key).inserted { out.append((it.key, Backend.plainChannelName(e.name))) }
            }
        }
        Backend.mainLock.lock()
        Backend.mainSnap = sn
        Backend.mainList = out
        Backend.mainLock.unlock()
        return out
    }

    /// Provider categories of live channels (adult ones only when allowed), in the provider's order.
    public func liveCategories(profile p: Profile?) -> [LiveCategory] {
        let sn = lib.snap
        let sources = lib.sources
        let noAdult = hideAdult(p)
        var out: [LiveCategory] = []
        for s in sources {
            for c in sn.categories(src: s.id, kind: .live) where !(noAdult && Genres.isAdult(c.name)) {
                out.append(LiveCategory(src: s.id, name: c.name, label: sources.count > 1 ? "\(c.name) · \(s.name)" : c.name, count: c.count))
            }
        }
        return out
    }

    private func row(_ it: Item, num: Int, name: String?, favs: Set<String>) -> LiveChannel {
        LiveChannel(key: it.key, num: num, name: name ?? Packs.cleanName(it.name), logo: it.logo, cat: it.cat, fav: favs.contains(it.key),
                    hasEpg: epgKey(it) != nil, radio: it.cat.lowercased().contains("radio"))
    }

    /// The channels of a filter, numbered.
    public func channels(_ f: LiveFilter, profile p: Profile) -> [LiveChannel] {
        let sn = lib.snap
        let favs = Set(p.favs)
        let main = mainChannels()
        var names: [String: String] = [:]
        for m in main { names[m.key] = m.name }
        let noAdult = hideAdult(p)
        switch f {
        case .main:
            return main.enumerated().compactMap { i, m in sn.byKey[m.key].map { row($0, num: i + 1, name: m.name, favs: favs) } }
        case .favorites:
            return p.favs.compactMap { sn.byKey[$0] }.enumerated().map { i, it in row(it, num: i + 1, name: names[it.key], favs: favs) }
        case .all:
            var out: [LiveChannel] = []
            var n = 0
            for it in sn.items where it.kind == .live {
                if noAdult && Genres.isAdult(it.cat) { continue }
                n += 1
                out.append(row(it, num: it.num > 0 ? it.num : n, name: names[it.key], favs: favs))
            }
            return out
        case .category(let src, let name):
            return sn.inCategory(src: src, kind: .live, cat: name).enumerated().map { i, it in
                row(it, num: it.num > 0 ? it.num : i + 1, name: names[it.key], favs: favs)
            }
        }
    }

    /// Rows for the given channels, in that order (the player's channel list).
    public func channelRows(_ keys: [String], profile p: Profile) -> [LiveChannel] {
        let sn = lib.snap
        let favs = Set(p.favs)
        var names: [String: String] = [:]
        for m in mainChannels() { names[m.key] = m.name }
        return keys.compactMap { sn.byKey[$0] }.enumerated().map { i, it in row(it, num: i + 1, name: names[it.key], favs: favs) }
    }

    /// The display name of one channel (a clean name for the main ones).
    public func channelName(_ key: String) -> String {
        if let m = mainChannels().first(where: { $0.key == key }) { return m.name }
        return Packs.cleanName(lib.snap.byKey[key]?.name ?? "")
    }

    /// The channels whose guide is worth downloading: the main ones, everybody's favourites and the first channels of the list.
    public func guideKeys(limit: Int = 1500) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ k: String) { if seen.insert(k).inserted { out.append(k) } }
        for m in mainChannels() { add(m.key) }
        for p in profiles.all { p.favs.forEach(add); p.live.forEach(add) }
        var n = 0
        for it in lib.snap.items where it.kind == .live && n < limit {
            if Genres.isAdult(it.cat) { continue }
            add(it.key)
            n += 1
        }
        return out
    }

    /// "La mia lista": the films and series the viewer saved, the latest first.
    public func myList(profile p: Profile, limit: Int = 40) -> [Card] {
        let sn = lib.snap
        var out: [Card] = []
        for k in (p.movies.array + p.series.array).reversed() {
            guard let it = sn.byKey[k] else { continue }
            out.append(card(it, p))
            if out.count >= limit { break }
        }
        return out
    }

    public func inMyList(_ p: Profile?, _ key: String) -> Bool {
        guard let p = p, let it = lib.snap.byKey[key] else { return false }
        return p.has(it.kind, key)
    }

    /// Adds or removes a film or series from "La mia lista"; returns whether it is in it afterwards.
    @discardableResult
    public func toggleMyList(_ profileId: String, key: String) -> Bool {
        guard let it = lib.snap.byKey[key], it.kind == .movie || it.kind == .series else { return false }
        let on = !(profiles.get(profileId)?.has(it.kind, key) ?? false)
        select(profileId, kind: it.kind, keys: [key], on: on)
        return on
    }
}
