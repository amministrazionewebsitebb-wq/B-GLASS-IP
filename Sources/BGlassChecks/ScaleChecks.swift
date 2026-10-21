@testable import BGlassCore
import Foundation

/// A catalogue the size of a big provider's: 2,000 channels, 98,000 films, 6,000 series.
func runScaleChecks(_ h: Harness) {
    h.suite("scale: 106,000 titles") {
        let dir = tempDir("scale")
        let b = Backend(dir: dir)
        var s = Source()
        s.name = "Grande"; s.type = .xtream; s.url = "http://x"; s.user = "u"; s.pass = "p"
        s = b.lib.addSource(s)
        var items: [Item] = []
        items.reserveCapacity(106_000)
        let cats = (0..<120).map { "Categoria \($0)" } + ["Azione", "Commedia", "Thriller", "Horror", "Film più visti", "Animazione"]
        for i in 0..<2000 { let it = Item(src: s.id, kind: .live, key: "\(s.id):l:\(i)", name: "IT: Canale \(i) HD", cat: "Canali \(i % 40)"); it.sid = "\(i)"; it.epgId = "c\(i).it"; items.append(it) }
        for i in 0..<98_000 {
            let it = Item(src: s.id, kind: .movie, key: "\(s.id):m:\(i)", name: "Film numero \(i) (\(1990 + i % 35))", cat: cats[i % cats.count])
            it.sid = "\(i)"; it.ext = "mkv"; it.extra = String(format: "%.1f", Double(i % 90) / 10); it.added = 1_700_000_000 + i * 60
            it.logo = "http://img.example/poster/\(i).jpg"
            items.append(it)
        }
        for i in 0..<6000 { let it = Item(src: s.id, kind: .series, key: "\(s.id):s:\(i)", name: "Serie \(i)", cat: "Serie \(i % 30)"); it.sid = "\(i)"; items.append(it) }

        var t = Date()
        func lap(_ what: String) -> Double { let d = Date().timeIntervalSince(t); t = Date(); print("    \(what): \(Int(d * 1000)) ms"); return d }

        b.lib.replaceSource(s.id, items)
        _ = lap("publish snapshot (106k)")
        b.lib.save()
        _ = lap("save to disk")
        let size = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("library.bgl").path)[.size] as? Int) ?? 0
        print("    library file: \(size / 1_000_000) MB")

        let b2 = Backend(dir: dir)
        var liveAt = 0.0, basicsAt = 0.0
        let t0 = Date()
        b2.lib.load(onSources: { basicsAt = Date().timeIntervalSince(t0) }, onLive: { liveAt = Date().timeIntervalSince(t0) })
        let total = Date().timeIntervalSince(t0)
        print("    load: sources at \(Int(basicsAt * 1000)) ms, channels at \(Int(liveAt * 1000)) ms, everything at \(Int(total * 1000)) ms")
        h.equal(b2.lib.snap.items.count, 106_000)
        h.check(liveAt < 1.0, "channels must be usable quickly (\(liveAt) s)")
        h.check(total < 10, "full load took \(total) s")

        // a profile with the whole catalogue selected
        let p = b2.profiles.create(name: "Tutto", color: 0)
        b2.profiles.update(p.id) { prof in
            for it in items { prof.update(it.kind) { $0.insert(it.key) } }
        }
        _ = lap("select everything")
        let prof = b2.profiles.get(p.id)!
        for i in stride(from: 0, to: 98_000, by: 7) { b2.genres.put("\(s.id):m:\(i)", ["Azione", "Thriller", "Commedia", "Horror"][i % 4]) }
        _ = lap("(genre cache filled)")

        let rows = b2.vodRows(profile: prof, kind: .movie, per: 24, limit: 8)
        let dRows = lap("vodRows (first 8 rows of 98k films)")
        h.check(!rows.rows.isEmpty && dRows < 2.5, "rows took \(dRows) s")
        h.check(rows.rows.allSatisfy { $0.items.count <= 24 })
        let more = b2.vodRows(profile: prof, kind: .movie, per: 24, offset: 8, limit: 6)
        h.check(!more.rows.isEmpty)
        _ = lap("vodRows (next page)")

        let r = b2.search("film numero 4567", profile: prof)
        let dSearch = lap("search (first, folds 106k names)")
        h.check(r.moviesTotal >= 1)
        _ = b2.search("film numero 9", profile: prof)
        let dSearch2 = lap("search (warm)")
        h.check(dSearch < 4 && dSearch2 < 1.0, "search \(dSearch) / \(dSearch2) s")

        let grid = b2.vodItems(profile: prof, kind: .movie, cats: ["Azione"], offset: 0, limit: 60)
        _ = lap("vodItems page")
        h.equal(grid.items.count, 60)
        h.check(grid.total > 500)

        let live = b2.liveList(profile: prof)
        _ = lap("liveList (2,000 channels)")
        h.equal(live.count, 2000)

        let idx = Variants.build(b2.lib.snap.items)
        _ = lap("variants index")
        h.equal(idx.live, 2000)

        // the guide of 2,000 channels
        var guide: [String: [Prog]] = [:]
        let now = Int64(Date().timeIntervalSince1970)
        for i in 0..<2000 { guide["c\(i).it"] = (0..<14).map { Prog(now - 3600 + Int64($0) * 3600, now + Int64($0 + 1) * 3600 - 3600, "Programma \($0)", "Descrizione") } }
        b2.epg.putSource(s.id, guide, names: [:])
        _ = lap("guide put (28k programmes)")
        _ = b2.liveList(profile: prof)
        let nn = b2.nowNext(keys: live.map { $0.key })
        _ = lap("liveList + nowNext")
        h.equal(nn.count, 2000)
        b2.epg.save()
        _ = lap("guide save")
        let e2 = EPGStore(file: dir.appendingPathComponent("epg.bgl"))
        e2.load()
        _ = lap("guide load")
        h.equal(e2.channels, 2000)
    }
}
