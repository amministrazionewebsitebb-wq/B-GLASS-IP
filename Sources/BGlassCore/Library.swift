import Foundation

/// All sources and every item they offer. Readers use an immutable `Snap`; writers swap it.
public final class Library {
    public struct Cat {
        public var name: String
        public var count: Int
    }

    /// Immutable view of the library.
    public final class Snap {
        public let items: [Item]
        public let byKey: [String: Item]
        private struct Table {
            var order: [String] = []
            var items: [String: [Item]] = [:]
            mutating func add(_ it: Item) {
                if items[it.cat] == nil { order.append(it.cat); items[it.cat] = [it] } else { items[it.cat]!.append(it) }
            }
        }
        private let cats: [String: Table]          // "src:kind" -> categories in first-seen order

        public init(_ items: [Item]) {
            self.items = items
            var by = [String: Item](minimumCapacity: items.count)
            var cs: [String: Table] = [:]
            for it in items {
                by[it.key] = it
                cs["\(it.src):\(it.kind.rawValue)", default: Table()].add(it)         // in place: copying the table per item would be quadratic
            }
            byKey = by
            cats = cs
        }

        public func categories(src: Int, kind: Kind) -> [Cat] {
            guard let t = cats["\(src):\(kind.rawValue)"] else { return [] }
            return t.order.map { Cat(name: $0, count: t.items[$0]?.count ?? 0) }
        }

        public func inCategory(src: Int, kind: Kind, cat: String) -> [Item] {
            cats["\(src):\(kind.rawValue)"]?.items[cat] ?? []
        }

        /// Case-insensitive "all words contained" search. src < 0 = every source, cat nil = any. `noAdult` leaves out the categories for adults.
        public func search(src: Int = -1, kind: Kind, cat: String? = nil, query: String? = nil, offset: Int = 0, limit: Int = Int.max, noAdult: Bool = false) -> (items: [Item], total: Int) {
            let toks = (query ?? "").lowercased().trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            var out: [Item] = []
            var total = 0
            let pool: [Item] = (cat != nil && src >= 0) ? inCategory(src: src, kind: kind, cat: cat!) : items
            for it in pool {
                if it.kind != kind { continue }
                if src >= 0 && it.src != src { continue }
                if let c = cat, c != it.cat { continue }
                if noAdult && Genres.isAdult(it.cat) { continue }
                if !toks.isEmpty {
                    let n = it.name.lowercased()
                    var ok = true
                    for t in toks where !n.contains(t) { ok = false; break }
                    if !ok { continue }
                }
                if total >= offset && out.count < limit { out.append(it) }
                total += 1
            }
            return (out, total)
        }
    }

    /// The folded name of an item, worked out once.
    public static func searchKey(_ it: Item) -> String {
        skLock.lock(); defer { skLock.unlock() }                 // the warm-up thread and a search can ask for the same item at once
        if let k = it.sk { return k }
        let k = Hash.fold(it.name)
        it.sk = k
        return k
    }

    private static let skLock = NSLock()

    private let dir: URL
    private let lock = NSLock()
    private let publishLock = NSLock()          // one catalogue is published at a time
    private let ioLock = NSLock()               // one file write at a time
    private var _snap = Snap([])
    private var _sources: [Source] = []
    private var nextId = 1
    private var _loaded = false

    public init(dir: URL) { self.dir = dir }

    public var snap: Snap { lock.lock(); defer { lock.unlock() }; return _snap }
    public var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return _loaded }
    public var sources: [Source] { lock.lock(); defer { lock.unlock() }; return _sources }

    public func source(_ id: Int) -> Source? { lock.lock(); defer { lock.unlock() }; return _sources.first { $0.id == id } }

    @discardableResult
    public func addSource(_ s: Source) -> Source {
        lock.lock(); defer { lock.unlock() }
        var s = s
        s.id = nextId
        nextId += 1
        _sources.append(s)
        return s
    }

    public func updateSource(_ s: Source) {
        lock.lock(); defer { lock.unlock() }
        if let i = _sources.firstIndex(where: { $0.id == s.id }) { _sources[i] = s }
    }

    /// Changes a stored source in place (several loads may report at the same time, so read-modify-write happens under the lock).
    @discardableResult
    public func mutateSource(_ id: Int, _ body: (inout Source) -> Void) -> Source? {
        lock.lock(); defer { lock.unlock() }
        guard let i = _sources.firstIndex(where: { $0.id == id }) else { return nil }
        body(&_sources[i])
        return _sources[i]
    }

    public func removeSource(_ id: Int) {
        lock.lock()
        _sources.removeAll { $0.id == id }
        lock.unlock()
        publishLock.lock(); defer { publishLock.unlock() }
        let keep = snap.items.filter { $0.src != id }
        setSnap(Snap(keep))
    }

    private func setSnap(_ s: Snap) { lock.lock(); _snap = s; lock.unlock() }

    @discardableResult
    public func replaceSource(_ srcId: Int, _ fresh: [Item], wanted: Set<String>? = nil) -> [String: String] {
        replaceKinds(srcId, kinds: nil, fresh, wanted: wanted)
    }

    /// Replaces the items of one source (only the given kinds when `kinds` is not nil) so a catalogue can be published piece by piece:
    /// live channels first, movies and series when they arrive. Returns old-key -> new-key for the items a profile had selected (`wanted`)
    /// whose key changed but whose (kind, normalized name) still matches, so selections survive a refresh. Nothing is computed for the
    /// other 99% of the list.
    @discardableResult
    public func replaceKinds(_ srcId: Int, kinds: Set<Kind>?, _ fresh: [Item], wanted: Set<String>?) -> [String: String] {
        publishLock.lock(); defer { publishLock.unlock() }
        let old = snap
        var remap: [String: String] = [:]
        var merged: [Item] = []
        merged.reserveCapacity(old.items.count + fresh.count)
        var lost: [Item] = []
        var freshKeys: Set<String>?
        for it in old.items {
            let replaced = it.src == srcId && (kinds == nil || kinds!.contains(it.kind))
            if !replaced { merged.append(it); continue }
            if let w = wanted, w.contains(it.key) {
                if freshKeys == nil { freshKeys = Set(fresh.map { $0.key }) }
                if !freshKeys!.contains(it.key) { lost.append(it) }
            }
        }
        if !lost.isEmpty {
            var candidates: [String: Item] = [:]
            var dup = Set<String>()
            var targets = Set<String>()
            for it in lost { targets.insert("\(it.kind.rawValue)|\(Hash.norm(it.name))") }
            for f in fresh {
                let nk = "\(f.kind.rawValue)|\(Hash.norm(f.name))"
                if !targets.contains(nk) { continue }
                if candidates[nk] != nil { dup.insert(nk) } else { candidates[nk] = f }
            }
            for it in lost {
                let nk = "\(it.kind.rawValue)|\(Hash.norm(it.name))"
                if let f = candidates[nk], !dup.contains(nk) { remap[it.key] = f.key }
            }
        }
        merged.append(contentsOf: fresh)
        setSnap(Snap(merged))
        return remap
    }

    // MARK: persistence

    private static let magic: [UInt8] = Array("BGL1".utf8)
    public static let version: Int32 = 1

    private var file: URL { dir.appendingPathComponent("library.bgl") }

    public func save() {
        let (srcs, nid, items): ([Source], Int, [Item]) = {
            lock.lock(); defer { lock.unlock() }
            return (_sources, nextId, _snap.items)
        }()
        ioLock.lock(); defer { ioLock.unlock() }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var w = ByteWriter()
            w.raw(Library.magic)
            w.i32(Library.version)
            w.i32(Int32(nid))
            w.long(String(decoding: try JSONEncoder().encode(srcs), as: UTF8.self))
            // each kind keeps its own order; the live channels sit in a block of their own so start-up can read them first
            let live = items.filter { $0.kind == .live }
            let rest = items.filter { $0.kind != .live }
            try writeBlock(&w, live)
            try writeBlock(&w, rest)
            try Data(w.bytes).write(to: file, options: .atomic)
        } catch {
            // the next save tries again; a failed write leaves the previous file untouched (atomic)
        }
    }

    private func writeBlock(_ out: inout ByteWriter, _ items: [Item]) throws {
        var b = ByteWriter()
        b.i32(Int32(items.count))
        for it in items { Library.write(&b, it) }
        let packed = try (Data(b.bytes) as NSData).compressed(using: .lzfse) as Data
        out.i32(Int32(b.bytes.count))
        out.i32(Int32(packed.count))
        out.raw([UInt8](packed))
    }

    private static func write(_ o: inout ByteWriter, _ it: Item) {
        o.str(it.key); o.i32(Int32(it.src)); o.u8(UInt8(it.kind.rawValue))
        o.str(it.name); o.str(it.cat); o.str(it.logo); o.str(it.ub); o.str(it.us); o.str(it.ext)
        o.str(it.sid); o.str(it.epgId); o.i32(Int32(it.num)); o.str(it.extra)
        o.str(it.parent); o.i16(Int16(truncatingIfNeeded: it.season)); o.i16(Int16(truncatingIfNeeded: it.episode)); o.str(it.ua)
        o.long(it.eps)
        o.i32(Int32(truncatingIfNeeded: it.added))
    }

    private static func readBlock(_ r: inout ByteReader, _ pool: StrPool) throws -> [Item] {
        let rawLen = Int(try r.i32())
        let packedLen = Int(try r.i32())
        let packed = try r.bytes(packedLen)
        let data = try (Data(packed) as NSData).decompressed(using: .lzfse) as Data
        if data.count != rawLen { throw NetError.invalid("library block size") }
        var b = ByteReader([UInt8](data))
        let n = Int(try b.i32())
        var items: [Item] = []
        items.reserveCapacity(n)
        for _ in 0..<n {
            let it = Item()
            it.key = try b.str() ?? ""
            it.src = Int(try b.i32())
            it.kind = Kind(rawValue: Int(try b.u8())) ?? .live
            it.name = try b.str() ?? ""
            it.cat = pool.get(try b.str() ?? "")
            it.logo = try b.str()
            it.ub = pool.get(try b.str())
            it.us = try b.str()
            it.ext = pool.get(try b.str())
            it.sid = try b.str()
            it.epgId = try b.str()
            it.num = Int(try b.i32())
            it.extra = try b.str()
            it.parent = try b.str()
            it.season = Int(try b.i16())
            it.episode = Int(try b.i16())
            it.ua = try b.str()
            it.eps = try b.long()
            it.added = Int(try b.i32())
            items.append(it)
        }
        return items
    }

    /// Reads the library from disk. `onSources` runs as soon as the lists themselves are known, `onLive` as soon as the live channels
    /// are in the snapshot (films and series still missing): the first screens and the TV page do not need the 100,000 films.
    /// Each runs exactly once, also when there is no file or it cannot be read.
    public func load(onSources: (() -> Void)? = nil, onLive: (() -> Void)? = nil) {
        var told = [false, false]
        defer {
            if !told[0] { onSources?() }
            if !told[1] { onLive?() }
            lock.lock(); _loaded = true; lock.unlock()
        }
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count > 16 else { return }
        do {
            var r = ByteReader([UInt8](data))
            guard try r.bytes(4) == Library.magic, try r.i32() == Library.version else { return }
            let nid = Int(try r.i32())
            let srcJson = try r.long() ?? "[]"
            let ss = (try? JSONDecoder().decode([Source].self, from: Data(srcJson.utf8))) ?? []
            lock.lock(); nextId = max(nid, 1); _sources = ss; lock.unlock()
            told[0] = true
            onSources?()
            let pool = StrPool(30000)
            let live = try Library.readBlock(&r, pool)
            setSnap(Snap(live))
            told[1] = true
            onLive?()
            let rest = try Library.readBlock(&r, pool)
            setSnap(Snap(live + rest))
        } catch {
            // a damaged file: what could be read stays (the channels, usually) and one full refresh brings back the rest
        }
    }
}

// MARK: binary helpers

struct ByteWriter {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func i16(_ v: Int16) { var x = v.bigEndian; withUnsafeBytes(of: &x) { bytes.append(contentsOf: $0) } }
    mutating func i32(_ v: Int32) { var x = v.bigEndian; withUnsafeBytes(of: &x) { bytes.append(contentsOf: $0) } }
    mutating func i64(_ v: Int64) { var x = v.bigEndian; withUnsafeBytes(of: &x) { bytes.append(contentsOf: $0) } }
    mutating func raw(_ b: [UInt8]) { bytes.append(contentsOf: b) }

    /// Optional short string (capped, like the Android file format did).
    mutating func str(_ s: String?) {
        guard let s = s else { u8(0); return }
        u8(1)
        var u = Array(s.utf8)
        if u.count > 20000 { u = Array(String(s.prefix(5000)).utf8) }
        i32(Int32(u.count))
        raw(u)
    }

    /// Optional long string (episode lists), never capped.
    mutating func long(_ s: String?) {
        guard let s = s else { i32(-1); return }
        let u = Array(s.utf8)
        i32(Int32(u.count))
        raw(u)
    }
}

struct ByteReader {
    let b: [UInt8]
    var p = 0
    init(_ b: [UInt8]) { self.b = b }

    mutating func need(_ n: Int) throws {
        if n < 0 || p + n > b.count { throw NetError.invalid("library truncated") }
    }
    mutating func u8() throws -> UInt8 { try need(1); defer { p += 1 }; return b[p] }
    mutating func i16() throws -> Int16 { try need(2); defer { p += 2 }; return Int16(bigEndian: Int16(bitPattern: UInt16(b[p]) << 8 | UInt16(b[p + 1]))) }
    mutating func i32() throws -> Int32 {
        try need(4)
        defer { p += 4 }
        let v = UInt32(b[p]) << 24 | UInt32(b[p + 1]) << 16 | UInt32(b[p + 2]) << 8 | UInt32(b[p + 3])
        return Int32(bitPattern: v)
    }
    mutating func i64() throws -> Int64 {
        try need(8)
        defer { p += 8 }
        var v: UInt64 = 0
        for i in 0..<8 { v = v << 8 | UInt64(b[p + i]) }
        return Int64(bitPattern: v)
    }
    mutating func bytes(_ n: Int) throws -> [UInt8] { try need(n); defer { p += n }; return Array(b[p..<(p + n)]) }
    mutating func str() throws -> String? {
        if try u8() == 0 { return nil }
        let n = Int(try i32())
        try need(n)
        defer { p += n }
        return String(decoding: b[p..<(p + n)], as: UTF8.self)
    }
    mutating func long() throws -> String? {
        let n = Int(try i32())
        if n < 0 { return nil }
        try need(n)
        defer { p += n }
        return String(decoding: b[p..<(p + n)], as: UTF8.self)
    }
}
