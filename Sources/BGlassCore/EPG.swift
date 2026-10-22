import Foundation

/// One programme of the guide (times are unix seconds).
public struct Prog: Equatable, Sendable {
    public var s: Int64
    public var e: Int64
    public var t: String
    public var d: String
    public init(_ s: Int64, _ e: Int64, _ t: String, _ d: String) { self.s = s; self.e = e; self.t = t; self.d = d }
}

/// In-memory programme guide, persisted as one small compressed file. Keys are "srcId:xmltvChannelId" (lower-case).
public final class EPGStore {
    private var progs: [String: [Prog]] = [:]
    private var nameIndex: [String: String] = [:]          // "srcId:normName" -> channel key
    private var _updated: Int64 = 0
    private let file: URL
    private let lock = NSLock()

    public init(file: URL) { self.file = file }

    public var updated: Int64 { lock.lock(); defer { lock.unlock() }; return _updated }
    public var channels: Int { lock.lock(); defer { lock.unlock() }; return progs.count }

    public func clearSource(_ src: Int) {
        lock.lock(); defer { lock.unlock() }
        clearLocked(src)
    }

    private func clearLocked(_ src: Int) {
        let pre = "\(src):"
        for k in progs.keys where k.hasPrefix(pre) { progs[k] = nil }
        for k in nameIndex.keys where k.hasPrefix(pre) { nameIndex[k] = nil }
    }

    public func putSource(_ src: Int, _ data: [String: [Prog]], names: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        clearLocked(src)
        for (k, l) in data { progs["\(src):\(k)"] = l.sorted { $0.s < $1.s } }
        for (k, v) in names { nameIndex["\(src):\(k)"] = "\(src):\(v)" }
        _updated = Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Adds/replaces a single channel (used by the Xtream short-EPG fallback).
    public func putChannel(_ key: String, _ l: [Prog]) {
        if l.isEmpty { return }
        lock.lock(); defer { lock.unlock() }
        progs[key] = l.sorted { $0.s < $1.s }
    }

    public func has(_ key: String?) -> Bool {
        guard let key = key else { return false }
        lock.lock(); defer { lock.unlock() }
        return progs[key] != nil
    }

    /// Resolves an item to a channel key: direct id first, then by normalized name.
    public func resolve(epgKey: String?, src: Int, normName: String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let k = epgKey, progs[k] != nil { return k }
        if let n = normName, !n.isEmpty, let k = nameIndex["\(src):\(n)"], progs[k] != nil { return k }
        return nil
    }

    public func range(_ key: String?, from: Int64, to: Int64) -> [Prog] {
        lock.lock(); defer { lock.unlock() }
        guard let key = key, let all = progs[key] else { return [] }
        return all.filter { $0.e > from && $0.s < to }
    }

    /// (now, next); either may be nil.
    public func nowNext(_ key: String?, now: Int64) -> (now: Prog?, next: Prog?) {
        lock.lock(); defer { lock.unlock() }
        guard let key = key, let all = progs[key] else { return (nil, nil) }
        for (i, p) in all.enumerated() {
            if p.s <= now && p.e > now { return (p, i + 1 < all.count ? all[i + 1] : nil) }
            if p.s > now { return (nil, p) }
        }
        return (nil, nil)
    }

    // MARK: persistence

    public func save() {
        lock.lock()
        let snapshot = progs, names = nameIndex, upd = _updated
        lock.unlock()
        do {
            var w = ByteWriter()
            w.i32(1)
            w.i64(upd)
            w.i32(Int32(snapshot.count))
            for (k, a) in snapshot {
                w.str(k)
                w.i32(Int32(a.count))
                for p in a { w.i64(p.s); w.i64(p.e); w.str(p.t); w.str(p.d) }
            }
            w.i32(Int32(names.count))
            for (k, v) in names { w.str(k); w.str(v) }
            let packed = try (Data(w.bytes) as NSData).compressed(using: .lzfse) as Data
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try packed.write(to: file, options: .atomic)
        } catch { }
    }

    /// Reads the saved guide; unless a download already stored something newer.
    public func load() {
        guard let packed = try? Data(contentsOf: file, options: .mappedIfSafe), let raw = try? (packed as NSData).decompressed(using: .lzfse) as Data else { return }
        var r = ByteReader([UInt8](raw))
        var p: [String: [Prog]] = [:]
        var ni: [String: String] = [:]
        let upd: Int64
        do {
            guard try r.i32() == 1 else { return }
            upd = try r.i64()
            let n = Int(try r.i32())
            for _ in 0..<n {
                let k = try r.str() ?? ""
                let c = Int(try r.i32())
                var a: [Prog] = []
                a.reserveCapacity(c)
                for _ in 0..<c { a.append(Prog(try r.i64(), try r.i64(), try r.str() ?? "", try r.str() ?? "")) }
                p[k] = a
            }
            let m = Int(try r.i32())
            for _ in 0..<m { ni[try r.str() ?? ""] = try r.str() ?? "" }
        } catch { return }                                          // a damaged file gives nothing (the guide is downloaded again when it is due)
        lock.lock(); defer { lock.unlock() }
        if _updated > upd { return }                                 // a download finished meanwhile: that one is newer
        progs = p
        nameIndex = ni
        _updated = upd
    }
}

/// Streaming XMLTV reader that only keeps wanted channels inside a time window.
public enum XMLTV {
    public struct Result {
        public var progs: [String: [Prog]] = [:]
        /// normalized channel display-name -> xmltv channel id (only for channels we kept)
        public var nameToId: [String: String] = [:]
        public var total = 0
    }

    /// - wantedIds: lower-case xmltv channel ids to keep (direct tvg-id matches)
    /// - wantedNames: normalized channel names to match by display-name when the id is unknown
    public static func parse(file: URL, wantedIds: Set<String>?, wantedNames: Set<String>?, from: Int64, to: Int64) throws -> Result {
        guard let stream = InputStream(url: file) else { throw NetError.invalid("Guida non leggibile") }
        return try parse(stream: stream, wantedIds: wantedIds, wantedNames: wantedNames, from: from, to: to)
    }

    public static func parse(data: Data, wantedIds: Set<String>?, wantedNames: Set<String>?, from: Int64, to: Int64) throws -> Result {
        try parse(stream: InputStream(data: data), wantedIds: wantedIds, wantedNames: wantedNames, from: from, to: to)
    }

    private static func parse(stream: InputStream, wantedIds: Set<String>?, wantedNames: Set<String>?, from: Int64, to: Int64) throws -> Result {
        let h = Handler(wantedIds: wantedIds, wantedNames: wantedNames, from: from, to: to)
        let p = XMLParser(stream: stream)
        p.delegate = h
        p.shouldProcessNamespaces = false
        if !p.parse(), h.result.total == 0, h.result.progs.isEmpty, let e = p.parserError { throw e }
        return h.result
    }

    private final class Handler: NSObject, XMLParserDelegate {
        let wantedIds: Set<String>?, wantedNames: Set<String>?
        let from: Int64, to: Int64
        var result = Result()
        var chNames: [String: [String]] = [:]
        var decision: [String: Bool] = [:]
        var curChan: String?
        var inProg = false
        var pCh = "", pStart: Int64 = 0, pEnd: Int64 = 0, title = "", desc = ""
        enum Target { case none, displayName, title, desc }
        var target = Target.none
        var buf = ""

        init(wantedIds: Set<String>?, wantedNames: Set<String>?, from: Int64, to: Int64) {
            self.wantedIds = wantedIds; self.wantedNames = wantedNames; self.from = from; self.to = to
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
            switch name {
            case "channel":
                curChan = a["id"]
                if let c = curChan { chNames[c.lowercased()] = [] }
            case "display-name":
                if curChan != nil { target = .displayName; buf = "" }
            case "programme":
                inProg = true
                result.total += 1
                pCh = a["channel"] ?? ""
                pStart = XMLTV.parseTime(a["start"])
                pEnd = XMLTV.parseTime(a["stop"])
                title = ""; desc = ""
            case "title":
                if inProg && title.isEmpty { target = .title; buf = "" }
            case "desc":
                if inProg && desc.isEmpty { target = .desc; buf = "" }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if target != .none { buf += string } }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if target != .none { buf += String(decoding: CDATABlock, as: UTF8.self) } }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch name {
            case "display-name":
                if target == .displayName, let c = curChan { chNames[c.lowercased(), default: []].append(Hash.norm(buf.trimmed)) }
                target = .none
            case "title":
                if target == .title { title = buf.trimmed }
                target = .none
            case "desc":
                if target == .desc { desc = buf.trimmed }
                target = .none
            case "channel":
                curChan = nil
            case "programme":
                inProg = false
                finishProgramme()
            default: break
            }
        }

        func finishProgramme() {
            guard !pCh.isEmpty, pStart > 0, pEnd > pStart, pEnd >= from, pStart <= to else { return }
            let lc = pCh.lowercased()
            var keep: Bool
            if let d = decision[lc] { keep = d } else {
                keep = wantedIds?.contains(lc) ?? false
                if !keep, let wn = wantedNames, let names = chNames[lc] {
                    for n in names where !n.isEmpty && wn.contains(n) { keep = true; break }
                }
                decision[lc] = keep
                if keep, let names = chNames[lc] { for n in names where !n.isEmpty { result.nameToId[n] = lc } }
            }
            if keep {
                result.progs[lc, default: []].append(Prog(pStart, pEnd, title, desc.count > 500 ? String(desc.prefix(500)) : desc))
            }
        }
    }

    /// "20260101120000 +0100" (offset optional) -> epoch seconds, 0 when unparsable.
    public static func parseTime(_ v: String?) -> Int64 {
        guard let v = v?.trimmed, v.count >= 12 else { return 0 }
        let u = Array(v.unicodeScalars)
        func num(_ a: Int, _ b: Int) -> Int? { Int(String(String.UnicodeScalarView(u[a..<b]))) }
        guard let y = num(0, 4), let mo = num(4, 6), let d = num(6, 8), let h = num(8, 10), let mi = num(10, 12) else { return 0 }
        var se = 0
        if u.count >= 14, isDigitScalar(u[12]) { se = num(12, 14) ?? 0 }
        var t = daysFromCivil(y, mo, d) * 86400 + Int64(h) * 3600 + Int64(mi) * 60 + Int64(se)
        // the offset may follow a space ("… +0200") or come straight after the digits ("…+0200", "…Z" for UTC)
        if let sp = u.indices.first(where: { $0 >= 12 && (u[$0] == " " || u[$0] == "+" || u[$0] == "-") }) {
            let tz = String(String.UnicodeScalarView(u[(u[sp] == " " ? sp + 1 : sp)...])).trimmed.replacingOccurrences(of: ":", with: "")
            let t2 = Array(tz.unicodeScalars)
            if t2.count >= 5, t2[0] == "+" || t2[0] == "-",
               let oh = Int(String(String.UnicodeScalarView(t2[1..<3]))), let om = Int(String(String.UnicodeScalarView(t2[3..<5]))) {
                let off = Int64(oh * 3600 + om * 60)
                t += t2[0] == "+" ? -off : off
            }
        }
        return t
    }

    // Howard Hinnant's days_from_civil: days since 1970-01-01.
    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int64 {
        let y = Int64(m <= 2 ? y0 - 1 : y0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * Int64(m + (m > 2 ? -3 : 9)) + 2) / 5 + Int64(d) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
