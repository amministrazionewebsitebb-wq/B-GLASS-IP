import Foundation

public enum BackendError: Error, LocalizedError {
    case message(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .cancelled: return "Caricamento annullato"
        }
    }
}

/// (phase, done, total): "auth", "live", "movies", "series", "part" (kind in total), "m3u" (total = percent, -1 unknown), "index", "save", "epg".
public typealias ProgressFn = (_ phase: String, _ done: Int, _ total: Int) -> Void

public struct Play: Sendable {
    public var url = ""
    public var ua = ""
    /// The same channel in other forms (the other live format, the address without one), tried in turn when it does not play.
    public var alts: [String] = []
    public var alt: String? { alts.first }
    public var insecure = false
    public var headers: [String: String] = [:]     // Referer, Origin, Cookie a list asks for (the User-Agent is `ua`)
}

/// Everything that is not UI or player: sources, profiles, library, guide.
public final class Backend {
    public let dir: URL
    public let lib: Library
    public let profiles: ProfileStore
    public let epg: EPGStore
    public let settings: Settings
    public let genres: GenreCache
    let detailCache = SafeCache<VodDetails>()
    let seriesCache = SafeCache<XtreamClient.SeriesInfo>()

    public init(dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dir = dir
        lib = Library(dir: dir)
        profiles = ProfileStore(dir: dir)
        epg = EPGStore(file: dir.appendingPathComponent("epg.bgl"))
        settings = Settings(dir: dir)
        genres = GenreCache(dir: dir)
    }

    /// `onBasics`: settings, profiles and the lists are in (the profile chooser can show), the items are still loading.
    /// `onLive`: the live channels are in too (a profile and the TV page can open), films and series still loading.
    /// `onGuide`: the saved guide is in. It is read beside the films, so opening a profile never waits for it.
    /// Returns when everything is loaded.
    public func loadAll(onBasics: (() -> Void)? = nil, onLive: (() -> Void)? = nil, onGuide: (() -> Void)? = nil) {
        settings.load()
        profiles.load()
        let guide = DispatchGroup()
        lib.load(onSources: onBasics, onLive: { [self] in
            guide.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                self.epg.load()
                onGuide?()
                guide.leave()
            }
            onLive?()
        })
        guide.wait()
        genres.load()
    }

    // MARK: sources

    /// Live account details of an Xtream source (status, expiry, connections); keeps the stored copy up to date.
    public func account(_ s: Source) async throws -> XtreamClient.Account { try await accountVia(s, api: s) }

    /// The same, asking `api` (the Xtream panel behind an M3U link) and storing the answer on `s`.
    public func accountVia(_ s: Source, api: Source) async throws -> XtreamClient.Account {
        let a = try await XtreamClient(api).auth()
        if a.ok {
            var changed = false
            lib.mutateSource(s.id) { x in
                changed = x.expires != a.expires || x.expTs != a.expTs || x.maxConn != a.maxConn
                x.expires = a.expires; x.expTs = a.expTs; x.maxConn = a.maxConn; x.activeConn = a.activeConn
            }
            if changed { lib.save() }
        }
        return a
    }

    /// The result of checking a list before it is added: what to tell the person, and the list as it actually works
    /// (another port, User-Agent or certificate option may have been needed).
    public struct Checked: Sendable {
        public var source: Source
        public var summary: String
    }

    /// Validates a source without storing anything.
    public func check(_ s: Source) async throws -> Checked {
        Diag.secret(s.user, s.pass)
        if s.type == .xtream {
            let f = try await XtreamClient.discover(s)
            let a = f.account
            if !a.ok { throw BackendError.message(a.message.isEmpty ? "Utente o password non validi" : a.message) }
            var text = "Account " + (a.status.isEmpty ? "attivo" : a.status.lowercased()) + " · scade: " + a.expires
                + (a.maxConn.isEmpty ? "" : " · connessioni: " + a.maxConn)
            if !f.note.isEmpty { text += "\nSistemato da solo: " + f.note + "." }
            return Checked(source: f.source, summary: text)
        }
        let (t, head) = try await probeList(s)
        var text = Gzip.isGzip(head) ? "Lista M3U (compressa) raggiungibile" : "Lista M3U raggiungibile"
        if t.ua != s.ua { text += "\nSistemato da solo: il server accetta solo il riconoscimento «\(t.ua)»." }
        if t.insecure && !s.insecure { text += "\nSistemato da solo: certificato HTTPS non valido accettato." }
        return Checked(source: t, summary: text)
    }

    /// Kept for callers that only want the words.
    public func test(_ s: Source) async throws -> String { try await check(s).summary }

    /// True when the first bytes look like a playlist (extended M3U, or a plain list of addresses), not a web page or an error.
    static func looksLikePlaylist(_ head: Data) -> Bool {
        if Gzip.isGzip(head) { return true }
        if Lenient.isHTML(head) { return false }
        let t = Lenient.text(head.prefix(65536))
        if t.contains("#EXTM3U") || t.contains("#EXTINF") { return true }
        return t.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).prefix(20).contains { $0.contains("://") }
    }

    /// Opens an M3U link the way its host wants: as typed, then as the other usual players when the host refuses (HTTP error or
    /// a web page), accepting a broken certificate when that is the only problem. Returns the working settings and the first bytes.
    func probeList(_ s: Source) async throws -> (Source, Data) {
        let uas = s.ua.isEmpty ? Net.userAgents : [s.ua]
        var firstError: Error?
        var insecure = s.insecure
        var i = 0
        while i < uas.count {
            try Task.checkCancellation()
            var t = s
            t.ua = s.ua.isEmpty && i == 0 ? "" : uas[i]
            t.insecure = insecure
            do {
                let head = try await Net.peek(t.url, ua: t.ua, insecure: t.insecure, bytes: 4096)
                if Backend.looksLikePlaylist(head) { return (t, head) }
                firstError = firstError ?? BackendError.message("Il link non porta a una lista M3U: il server ha mandato \(Lenient.describe(head)).")
                i += 1
            } catch {
                if error is CancellationError { throw error }
                firstError = firstError ?? error
                if let u = error as? URLError {
                    if XtreamClient.certificateProblem(u), !insecure { insecure = true; continue }
                    break                                                         // unreachable: another name will not help
                }
                if case NetError.http(let c) = error, c == 404 || c == 410 { break }
                i += 1
            }
        }
        throw firstError ?? BackendError.message("Il link non risponde")
    }

    private let cancelLock = NSLock()
    private var cancelled = Set<Int>()

    public func cancel(_ id: Int) { cancelLock.lock(); cancelled.insert(id); cancelLock.unlock() }
    private func clearCancel(_ id: Int) { cancelLock.lock(); cancelled.remove(id); cancelLock.unlock() }

    private func check(_ id: Int) throws {
        cancelLock.lock(); let c = cancelled.contains(id); cancelLock.unlock()
        if c { throw BackendError.cancelled }
        try Task.checkCancellation()
    }

    private func isCancel(_ e: Error) -> Bool {
        if e is CancellationError { return true }
        if case BackendError.cancelled = e { return true }
        return false
    }

    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    private func wantedKeys() -> Set<String> {
        var k = Set<String>()
        for p in profiles.all { k.formUnion(p.live.keySet); k.formUnion(p.movies.keySet); k.formUnion(p.series.keySet) }
        return k
    }

    /// `liveOnly`: reload just the channel list of an Xtream source (a second or two) and leave movies/series untouched.
    public func refreshSource(_ id: Int, liveOnly: Bool = false, progress: ProgressFn? = nil) async throws {
        guard let s = lib.source(id) else { throw BackendError.message("Sorgente inesistente") }
        Diag.secret(s.user, s.pass)
        Diag.log("Aggiorno «\(s.name)» (\(s.type == .xtream ? "Xtream" : "M3U"))")
        clearCancel(id)
        defer { clearCancel(id) }
        if s.type == .xtream { try await refreshXtream(s, liveOnly: liveOnly, progress: progress) }
        else { try await refreshM3U(s, progress: progress) }
    }

    private func refreshXtream(_ s: Source, liveOnly: Bool, progress: ProgressFn?) async throws {
        let id = s.id
        progress?("auth", 0, 0)
        var found: XtreamClient.Found?
        var attempt = 0
        while found == nil {                            // a busy panel times out now and then: try again before failing
            attempt += 1
            do {
                let f = try await XtreamClient.discover(s)
                if f.account.ok || f.account.rejected || attempt >= 2 { found = f; break }
            } catch {
                if isCancel(error) || attempt >= 2 { throw error }
                if let u = error as? URLError, u.code == .cannotFindHost || u.code == .notConnectedToInternet { throw error }
            }
            try check(id)
            try await pause(Double(attempt) * 2)
            try check(id)
        }
        try check(id)
        let acc = found!.account
        if !acc.ok { throw BackendError.message(acc.message.isEmpty ? "Utente o password non validi" : acc.message) }
        // the way in that worked (another port, User-Agent, certificate) is kept for the next time and for playing
        let way = found!.source
        lib.mutateSource(id) {
            $0.url = way.url; $0.ua = way.ua; $0.insecure = way.insecure
            $0.expires = acc.expires; $0.expTs = acc.expTs; $0.activeConn = acc.activeConn; $0.maxConn = acc.maxConn; $0.hls = acc.hls; $0.fmtChecked = true
        }
        let x = XtreamClient(lib.source(id) ?? way)
        let before = lib.source(id) ?? s

        // The three catalogues download separately and are published as soon as each is ready: the channels (a few hundred KB)
        // are usable long before the 100k movies finish.
        let wanted = wantedKeys()
        var parts = 0
        var failed: [Kind: Error] = [:]
        var firstFailure: Error?

        @Sendable func loadKind(_ kind: Kind) async throws -> Int {
            let phase = kind == .live ? "live" : kind == .movie ? "movies" : "series"
            progress?(phase, 0, 0)
            var list: [Item] = []
            var n = 0
            var attempt = 0
            // providers drop a connection now and then (several downloads from one address, a busy panel): try again before giving up
            while true {
                attempt += 1
                do {
                    list.removeAll(keepingCapacity: true)
                    let tick: (Int) -> Void = { progress?(phase, $0, 0) }
                    switch kind {
                    case .live: n = try await x.loadLive(progress: tick) { list.append($0) }
                    case .movie: n = try await x.loadVod(progress: tick) { list.append($0) }
                    default: n = try await x.loadSeries(progress: tick) { list.append($0) }
                    }
                    break
                } catch {
                    if isCancel(error) || attempt >= 3 { throw error }
                    try check(id)
                    try await pause(Double(attempt) * 2.5)
                    try check(id)
                }
            }
            try check(id)
            // an empty answer where there were channels is a hiccup of the panel, not an empty list: keep what we had
            let had = kind == .live ? before.nLive : kind == .movie ? before.nMovies : before.nSeries
            if n == 0 && had > 0 { throw BackendError.message("Il server ha mandato un elenco vuoto") }
            let remap = lib.replaceKinds(id, kinds: [kind], list, wanted: wanted)
            if !remap.isEmpty { profiles.updateAll { $0.remapKeys(remap) } }
            lib.mutateSource(id) { src in
                switch kind {
                case .live: src.nLive = n
                case .movie: src.nMovies = n
                default: src.nSeries = n
                }
                src.updated = Int64(Date().timeIntervalSince1970 * 1000)
            }
            progress?("part", n, kind.rawValue)
            return n
        }

        for kind in [Kind.live, .movie, .series] {
            let want = kind == .live ? s.wantLive : kind == .movie ? s.wantMovies : s.wantSeries
            if liveOnly && kind != .live { continue }
            if !want {
                lib.mutateSource(id) { src in
                    switch kind {
                    case .live: src.nLive = 0
                    case .movie: src.nMovies = 0
                    default: src.nSeries = 0
                    }
                }
            }
        }
        // the channels first and on their own (small, and what the viewer needs at once), then films and series together
        if s.wantLive {
            do { _ = try await loadKind(.live); parts += 1 }
            catch { if isCancel(error) { throw error }; failed[.live] = error; firstFailure = firstFailure ?? error }
        }
        if !liveOnly {
            await withTaskGroup(of: (Kind, Error?).self) { group in
                if s.wantMovies { group.addTask { do { _ = try await loadKind(.movie); return (.movie, nil) } catch { return (.movie, error) } } }
                if s.wantSeries { group.addTask { do { _ = try await loadKind(.series); return (.series, nil) } catch { return (.series, error) } } }
                for await (kind, err) in group {
                    if let e = err { failed[kind] = e; firstFailure = firstFailure ?? e } else { parts += 1 }
                }
            }
        }
        if failed.values.contains(where: { isCancel($0) }) { throw BackendError.cancelled }
        try check(id)
        if parts == 0 {
            if let f = firstFailure { throw f }
            throw BackendError.message("Nessun contenuto trovato nella sorgente")
        }
        var status = ""
        if !failed.isEmpty {
            let names: [(Kind, String)] = [(.live, "canali TV"), (.movie, "film"), (.series, "serie TV")]
            let what = names.filter { failed[$0.0] != nil }.map { $0.1 }.joined(separator: ", ")
            status = "Non sono riuscito a caricare: \(what). Il server non ha risposto: riprova tra poco (Le mie liste › Aggiorna)."
        }
        lib.mutateSource(id) { $0.status = status; $0.updated = Int64(Date().timeIntervalSince1970 * 1000) }
        progress?("save", 0, 0)
        await Task.detached(priority: .utility) { [lib] in lib.save() }.value
    }

    private func refreshM3U(_ s: Source, progress: ProgressFn?) async throws {
        var s = s
        let id = s.id
        progress?("m3u", 0, 0)
        var items: [Item] = []
        var kinds = [0, 0, 0, 0]
        var meta = M3UParser.Meta()
        var attempt = 0
        while true {                                    // a dropped download is tried again (twice) before giving up
            attempt += 1
            do {
                items.removeAll(keepingCapacity: true)
                kinds = [0, 0, 0, 0]
                if attempt == 1 {
                    // how the host wants to be asked (User-Agent, certificate); remembered on the list when it differs
                    let (t, _) = try await probeList(s)
                    if t.ua != s.ua || t.insecure != s.insecure {
                        lib.mutateSource(id) { $0.ua = t.ua; $0.insecure = t.insecure }
                        s = lib.source(id) ?? t
                    }
                }
                let file = try await Net.download(s.url, ua: s.ua, insecure: s.insecure) { got, total in
                    progress?("m3u", 0, total > 0 ? Int(min(99, got * 100 / total)) : -1)
                }
                defer { try? FileManager.default.removeItem(at: file) }
                let data = try Data(contentsOf: file, options: .alwaysMapped)
                if Backend.isStreamPlaylist(data) {
                    // the link is one channel (an HLS playlist), not a list of channels
                    let it = Item(src: id, kind: .live, key: "\(id):l:\(Hash.fnv(s.url))", name: s.name, cat: "Canali")
                    it.setUrl(s.url, prefixes: nil)
                    items = [it]; kinds[Kind.live.rawValue] = 1
                    break
                }
                meta = try M3UParser.parse(data: data, srcId: id, wantLive: s.wantLive, wantMovies: s.wantMovies, wantSeries: s.wantSeries, tick: { n in
                    try self.check(id)
                    progress?("m3u", n, -1)
                }) { items.append($0); kinds[$0.kind.rawValue] += 1 }
                break
            } catch {
                if isCancel(error) { throw error }
                if case NetError.http(let c) = error, (400...499).contains(c) { throw error }      // wrong address / account: retrying will not help
                if attempt >= 3 { throw error }
                try check(id)
                progress?("m3u", 0, -1)
                try await pause(Double(attempt) * 3)
                try check(id)
            }
        }
        try check(id)
        if items.isEmpty {
            throw BackendError.message(meta.count == 0 ? "La lista non contiene canali, film o serie (nessun indirizzo trovato)." : "Nessun contenuto trovato nella sorgente")
        }
        Diag.log("Lista letta: \(kinds[0]) canali, \(kinds[1]) film, \(kinds[2]) serie")
        progress?("index", items.count, 0)
        let remap = lib.replaceSource(id, items, wanted: wantedKeys())
        if !remap.isEmpty { profiles.updateAll { $0.remapKeys(remap) } }
        lib.mutateSource(id) { src in
            src.epgAuto = meta.epgUrl ?? ""
            src.nLive = kinds[Kind.live.rawValue]; src.nMovies = kinds[Kind.movie.rawValue]; src.nSeries = kinds[Kind.series.rawValue]
            src.updated = Int64(Date().timeIntervalSince1970 * 1000)
            src.status = ""
        }
        progress?("save", items.count, 0)
        await Task.detached(priority: .utility) { [lib] in lib.save() }.value
    }

    public func deleteSource(_ id: Int) {
        // What the viewer picked from this list and that another list also has (the same provider added twice, a list replaced by a
        // newer one) moves over to that list instead of disappearing.
        let before = lib.snap
        var wanted = wantedKeys()
        for p in profiles.all { wanted.formUnion(p.resume.keys); wanted.formUnion(p.favs); wanted.formUnion(p.recent) }
        var targets: [String: String] = [:]                 // kind|name -> key in the removed list
        for k in wanted {
            if let it = before.byKey[k], it.src == id { targets["\(it.kind.rawValue)|\(Hash.norm(it.name))"] = k }
        }
        if !targets.isEmpty {
            var remap: [String: String] = [:]
            for it in before.items where it.src != id {
                if let old = targets["\(it.kind.rawValue)|\(Hash.norm(it.name))"], remap[old] == nil { remap[old] = it.key }
            }
            profiles.updateAll { $0.remapKeys(remap) }
        }
        lib.removeSource(id)
        epg.clearSource(id)
        // drop dangling keys from every profile
        let sn = lib.snap
        profiles.updateAll { p in
            for kind in [Kind.live, .movie, .series] { p.update(kind) { $0.retain { sn.byKey[$0] != nil } } }
            p.favs.removeAll { sn.byKey[$0] == nil }
            p.recent.removeAll { sn.byKey[$0] == nil }
        }
        lib.save()
        epg.save()
    }

    // MARK: channel packs

    private let packLock = NSLock()

    public var allow4k: Bool { settings.get("packs4k", "0") == "1" }

    /// Re-matches the enabled packs of one profile against the current catalogue: channels that appeared are added, channels that
    /// vanished (or were replaced by a better copy) are dropped, everything else keeps its place. Never touches a profile when the
    /// catalogue looks empty. Returns true when the profile changed.
    @discardableResult
    public func syncPacks(_ profileId: String) -> Bool {
        packLock.lock(); defer { packLock.unlock() }
        guard let p = profiles.get(profileId) else { return false }
        if p.packs.isEmpty && p.packMap.isEmpty { return false }
        let idx = Packs.index(lib.snap)
        if idx.channels == 0 { return false }
        let list = Packs.resolveAll(enabled: p.packs, off: p.packOff, idx, allow4k: allow4k)
        var now: [String: String] = [:]
        for (e, k) in list { now[e] = k }
        let oldKeys = Set(p.packMap.values)
        let newKeys = list.map { $0.key }
        let newSet = Set(newKeys)
        var changed = now != p.packMap
        for k in oldKeys where !newSet.contains(k) && p.live.contains(k) { changed = true }
        for k in newKeys where !p.live.contains(k) { changed = true }
        if !changed { return false }
        profiles.update(profileId) { p in
            for k in oldKeys where !newSet.contains(k) { p.live.remove(k) }
            for k in newKeys { p.live.insert(k) }
            p.packMap = now
        }
        return true
    }

    /// Syncs every profile; returns the ids of those that changed.
    public func syncAllPacks() -> [String] { profiles.all.map { $0.id }.filter { syncPacks($0) } }

    /// Curated display name for each channel a profile got from a pack ("Sky Cinema Uno HD" instead of "IT: SKY CINEMA UNO FHD").
    public func packNames(_ p: Profile) -> [String: String] {
        var out: [String: String] = [:]
        for (entry, key) in p.packMap {
            if let nm = Packs.entryName(entry), out[key] == nil { out[key] = nm }
        }
        return out
    }

    /// Group title for each channel a profile got from a pack (used as its category on the TV page).
    public func packTitles(_ p: Profile) -> [String: String] {
        if p.packMap.isEmpty { return [:] }
        var titles: [String: String] = [:]
        for g in Packs.groups { titles[g.id] = g.title }
        var out: [String: String] = [:]
        for (entry, key) in p.packMap {
            let gid = entry.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if let t = titles[gid], out[key] == nil { out[key] = t }
        }
        return out
    }

    // MARK: guide

    private static let getPhp = try! NSRegularExpression(pattern: "^(https?://[^/?#]+)(?:/[^?#]*)?/(?:get|playlist)\\.php\\?(.*)$", options: [.caseInsensitive])

    /// An M3U link made by an Xtream panel (".../get.php?username=..&password=..") has its guide at ".../xmltv.php" with the same account.
    public static func xmltvFromM3U(_ url: String?) -> String? {
        guard let url = url?.trimmed else { return nil }
        let ns = url as NSString
        guard let m = getPhp.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var user: String?, pass: String?
        for kv in ns.substring(with: m.range(at: 2)).split(separator: "&") {
            guard let e = kv.firstIndex(of: "="), e != kv.startIndex else { continue }
            let k = kv[kv.startIndex..<e].lowercased()
            let v = String(kv[kv.index(after: e)...])
            if k == "username" { user = v } else if k == "password" { pass = v }
        }
        guard let u = user, let p = pass else { return nil }
        return ns.substring(with: m.range(at: 1)) + "/xmltv.php?username=" + u + "&password=" + p
    }

    /// Downloads the guide of the given channels (default: the channels the profiles picked).
    public func refreshEpg(keys: [String]? = nil, progress: ProgressFn? = nil) async {
        let sn = lib.snap
        var ids: [Int: Set<String>] = [:]
        var names: [Int: Set<String>] = [:]
        var wantedItems: [Int: [Item]] = [:]
        var seen = Set<String>()
        let wanted = keys ?? profiles.all.flatMap { $0.live.array }
        for k in wanted {
            guard let it = sn.byKey[k], seen.insert(k).inserted else { continue }
            if ids[it.src] == nil { ids[it.src] = []; names[it.src] = []; wantedItems[it.src] = [] }
            if let e = it.epgId, !e.isEmpty { ids[it.src]!.insert(e.lowercased()) }
            names[it.src]!.insert(Hash.norm(it.name))
            wantedItems[it.src]!.append(it)
        }
        let now = Int64(Date().timeIntervalSince1970)
        var step = 0
        for s in lib.sources {
            guard let wi = ids[s.id] else { continue }
            if Task.isCancelled { return }
            step += 1
            progress?("epg", step, ids.count)
            let url: String? = !s.epgUrl.trimmed.isEmpty ? s.epgUrl.trimmed
                : (s.type == .xtream ? XtreamClient(s).xmltvUrl : (!s.epgAuto.isEmpty ? s.epgAuto : Backend.xmltvFromM3U(s.url)))
            var ok = false
            if let url = url, !url.isEmpty {
                do {
                    let file = try await Net.download(url, ua: s.ua, insecure: s.insecure)
                    defer { try? FileManager.default.removeItem(at: file) }
                    let wn = names[s.id]
                    let r = try await Task.detached(priority: .utility) {
                        try XMLTV.parse(file: file, wantedIds: wi, wantedNames: wn, from: now - 3 * 3600, to: now + 36 * 3600)
                    }.value
                    if !r.progs.isEmpty { epg.putSource(s.id, r.progs, names: r.nameToId); ok = true }
                } catch { }
            }
            if !ok && s.type == .xtream { await shortEpgFill(s, wantedItems[s.id] ?? []) }
        }
        epg.save()
    }

    private func shortEpgFill(_ s: Source, _ items: [Item]) async {
        let x = XtreamClient(s)
        let deadline = Date().addingTimeInterval(180)
        let todo = Array(items.filter { $0.sid != nil }.prefix(400))           // one request per channel: only the first ones
        var next = 0
        await withTaskGroup(of: Void.self) { group in
            func add() {
                guard next < todo.count, Date() < deadline, !Task.isCancelled else { return }
                let it = todo[next]
                next += 1
                group.addTask { [epg] in
                    if let l = try? await x.shortEpg(it.sid!, limit: 12) {
                        epg.putChannel("\(s.id):xt\(it.sid!)", l.map { Prog($0.start, $0.end, $0.title, $0.desc) })
                    }
                }
            }
            for _ in 0..<4 { add() }
            for await _ in group { add() }
        }
    }

    /// Guide key for an item (matches both XMLTV ids, names and Xtream short-EPG fallbacks).
    public func epgKey(_ it: Item) -> String? {
        if let k = epg.resolve(epgKey: it.epgKey, src: it.src, normName: Hash.norm(it.name)) { return k }
        if let sid = it.sid, epg.has("\(it.src):xt\(sid)") { return "\(it.src):xt\(sid)" }
        return nil
    }

    // MARK: playback

    private static let plainStream = try! NSRegularExpression(pattern: "^(https?://[^/]+)/([^/]+)/([^/]+)/(\\d+)$")

    /// Remembers whether the panel offers HLS (one cheap call, only once per source).
    private func checkFormats(_ s: Source) async {
        if s.fmtChecked { return }
        if let a = try? await XtreamClient(s).auth() {
            lib.mutateSource(s.id) { $0.hls = a.hls; $0.fmtChecked = true }
            lib.save()
        }
    }

    /// True when the data is a single HLS stream (a channel), not an IPTV list.
    static func isStreamPlaylist(_ d: Data) -> Bool {
        let t = Lenient.text(d.prefix(8192))
        return t.contains("#EXTM3U") && (t.contains("#EXT-X-STREAM-INF") || t.contains("#EXT-X-TARGETDURATION")) && !t.contains("#EXTINF:-1")
    }

    public func resolve(_ it: Item) async -> Play? {
        let s = lib.source(it.src)
        var p = Play()
        if let s = s { p.ua = s.ua; p.insecure = s.insecure; Diag.secret(s.user, s.pass) }
        if let u = it.ua, !u.isEmpty { p.ua = u }
        if let line = it.url {
            // Kodi-style headers after "|" belong to the request, not to the address
            let direct = M3UParser.address(line)
            var h = M3UParser.headers(line)
            if let ua = h.removeValue(forKey: "User-Agent") { p.ua = ua }
            p.headers = h
            p.url = direct
            if it.kind == .live {          // Xtream-style "http://host/user/pass/123": the HLS twin is /live/user/pass/123.m3u8
                let ns = direct as NSString
                if let m = Backend.plainStream.firstMatch(in: direct, range: NSRange(location: 0, length: ns.length)) {
                    let live = "\(ns.substring(with: m.range(at: 1)))/live/\(ns.substring(with: m.range(at: 2)))/\(ns.substring(with: m.range(at: 3)))/\(ns.substring(with: m.range(at: 4)))"
                    p.alts = [live + ".m3u8", live + ".ts"]
                }
            }
            return p
        }
        guard var s = s, let sid = it.sid else { return nil }
        if it.kind == .live, s.liveFmt == "auto" {
            await checkFormats(s)
            s = lib.source(s.id) ?? s
        }
        let x = XtreamClient(s)
        switch it.kind {
        case .live:
            p.url = x.liveUrl(sid)
            // the other format of the same channel (many panels serve both even when they declare one), then the old style address
            p.alts = [x.liveUrl(sid, fmt: p.url.hasSuffix(".m3u8") ? "ts" : "m3u8"), x.plainLiveUrl(sid)]
        case .movie: p.url = x.movieUrl(sid, ext: it.ext)
        case .episode: p.url = x.episodeUrl(sid, ext: it.ext)
        case .series: return nil
        }
        return p
    }
}
