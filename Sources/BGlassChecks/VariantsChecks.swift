@testable import BGlassCore
import Foundation

private var counter = 0

private func vlive(_ src: Int, _ name: String, _ epg: String?, _ cat: String) -> Item {
    counter += 1
    let sid = String(1000 + counter)
    let it = Item(src: src, kind: .live, key: "\(src):l:\(sid)", name: name, cat: cat)
    it.sid = sid
    it.epgId = epg
    return it
}

private func vlive(_ name: String) -> Item { vlive(1, name, nil, "Qualsiasi") }

/// Deterministic pseudo random numbers (the original test used a seeded java.util.Random).
private struct Lcg {
    var s: UInt64
    mutating func next(_ n: Int) -> Int {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Int((s >> 33) % UInt64(n))
    }
}

func runVariantsChecks(_ h: Harness) {
    h.suite("variants: quality tags in many written forms") {
        let cases: [(String, Int)] = [
            ("IT: RAI 1 FHD", Variants.fhd), ("|IT| Rai 1 HD", Variants.hd), ("Rai 1 SD [IT]", Variants.sd), ("RAI 1 4K", Variants.uhd),
            ("Rai 1 UHD", Variants.uhd), ("Rai 1 Full HD", Variants.fhd), ("Rai 1 FullHD", Variants.fhd), ("Rai 1 1080p", Variants.fhd),
            ("Rai 1 1080i", Variants.fhd), ("Rai 1 720p", Variants.hd), ("Rai 1 (HD)", Variants.hd), ("Rai 1 [FHD]", Variants.fhd),
            ("Rai 1 HD 1080p", Variants.fhd), ("Rai 1 HDTV", Variants.hd), ("Rai 1 HD Ready", Variants.hd), ("Rai 1 Ultra HD", Variants.uhd),
            ("Rai 1 2160p", Variants.uhd), ("Rai 1 576p", Variants.sd), ("Rai 1", Variants.undeclared), ("Rai 1 ᴴᴰ", Variants.hd),
            ("Rai 1 FHD HEVC", Variants.fhd), ("Rai 1 FHD H.265", Variants.fhd), ("Rai 1 FHD 50fps", Variants.fhd), ("Rai 1 4K HDR", Variants.uhd),
        ]
        for (name, q) in cases { h.equal(Variants.parse(name).quality, q, name) }
        h.equal(Variants.parse("Rai 1 SD HD").quality, Variants.conflict)
        h.equal(Variants.parse("Rai 1 FHD 720p").quality, Variants.conflict)
        h.equal(Variants.parse("Rai 1 HD 4K FHD").quality, Variants.conflict)
    }

    h.suite("variants: identifying words are kept, tags are not") {
        h.equal(Variants.parse("IT: RAI 1 FHD").core, "rai 1")
        h.equal(Variants.parse("|IT| Rai 1 [HD]").core, "rai 1")
        h.equal(Variants.parse("Rai 1 FHD HEVC 50fps").core, "rai 1")
        h.equal(Variants.parse("Rai Più HD").core, "rai piu")
        h.equal(Variants.parse("Rai Più HD").core, Variants.parse("RAI PIU SD").core)
        h.check(Variants.parse("Sky Sport 1 HD").core != Variants.parse("Sky Sport 2 HD").core)
        h.check(Variants.parse("Sky Sport 1 HD").core != Variants.parse("Sky Sport +1 HD").core)
        h.check(Variants.parse("Sky Uno HD").core != Variants.parse("Sky Uno Plus HD").core)
        h.check(Variants.parse("Rai 3 Lombardia HD").core != Variants.parse("Rai 3 Lazio HD").core)
        h.check(Variants.parse("UK: Eurosport 1 HD").core != Variants.parse("Eurosport 1 SD").core)
        h.equal(Variants.parse("Canale 720").quality, Variants.undeclared)
        h.equal(Variants.parse("Canale 720").core, "canale 720")
        h.equal(Variants.build([vlive("Canale 720"), vlive("Canale SD")]).groups, 0)
        h.equal(Variants.parse("FHD").core, "")
        h.equal(Variants.parse(nil).core, "")
    }

    h.suite("variants: grouping") {
        let a = vlive(1, "IT: SKY SPORT UNO FHD", "SkySportUno.it", "Sport"), b = vlive(1, "IT: SKY SPORT UNO HD", "SkySportUno.it", "Sport HD")
        let c = vlive(1, "IT: SKY SPORT UNO SD", "SkySportUno.it", "Sport SD"), d = vlive(1, "IT: SKY SPORT UNO 4K", "SkySportUno.it", "4K")
        let idx = Variants.build([c, a, d, b])
        let g = idx.group(of: b.key)
        h.check(g != nil)
        if let g = g {
            h.equal(g.keys.count, 4)
            h.equal(g.keys, [d.key, a.key, b.key, c.key], "best first")
            h.equal(g.q[0], Variants.uhd)
            h.equal(g.q[3], Variants.sd)
            h.check(g.strong, "same guide id: sure")
            for it in [a, b, c, d] { h.check(idx.group(of: it.key) === g) }
        }
        h.equal(idx.groups, 1)
    }

    h.suite("variants: m3u entries without guide ids match by name only") {
        let a = vlive("Canale 5 FHD"), b = vlive("Canale 5 HD"), x = vlive("Italia 1 HD")
        let idx = Variants.build([a, x, b])
        let g = idx.group(of: a.key)
        h.check(g != nil)
        h.equal(g?.keys.count ?? 0, 2)
        h.check(g?.strong == false, "name only: not proven")
        h.check(idx.group(of: x.key) == nil, "a channel with one quality has no choice")
    }

    h.suite("variants: similar but different channels are never mixed") {
        let l = [vlive("Sky Sport 1 HD"), vlive("Sky Sport 2 FHD"), vlive("Sky Sport +1 SD"), vlive("Sky Sport Arena 4K"),
                 vlive("Rai 3 Lombardia HD"), vlive("Rai 3 Lazio SD"), vlive("UK: Eurosport 1 HD"), vlive("Eurosport 1 SD"),
                 vlive("Sky Uno HD"), vlive("Sky Uno Plus SD")]
        let idx = Variants.build(l)
        h.equal(idx.groups, 0)
        for it in l { h.check(idx.group(of: it.key) == nil, it.name) }
    }

    h.suite("variants: guide ids") {
        let a = vlive(1, "Rai 2 FHD", "Rai2.it", "x"), b = vlive(1, "Rai 2 HD", "Rai2.it", "x")
        let c = vlive(1, "Rai 2 SD", "RaiDue.alt", "x"), d = vlive(1, "Rai 2 4K", "RaiDue.alt", "x")
        let e = vlive(1, "Rai 2 UHD", nil, "x")
        let idx = Variants.build([a, b, c, d, e])
        h.equal(idx.groups, 2)
        h.equal(Set(idx.group(of: a.key)?.keys ?? []), [a.key, b.key])
        h.equal(Set(idx.group(of: c.key)?.keys ?? []), [c.key, d.key])
        h.check(idx.group(of: e.key) == nil, "could belong to either: left alone")
        let f = vlive(1, "Real Time FHD", "rt.it", "x"), g = vlive(1, "Real Time HD", "realtime2.it", "x")
        h.equal(Variants.build([f, g]).groups, 0)
        let x = vlive(1, "Rai 1 FHD", "Rai1.it", "x"), y = vlive(2, "Rai 1 HD", "Rai1.it", "x")
        h.equal(Variants.build([x, y]).groups, 0, "separate lists are never mixed")
    }

    h.suite("variants: duplicates and unmarked entries") {
        let a = vlive(1, "Rai 1 FHD", "Rai1.it", "x"), a2 = vlive(1, "Rai 1 FHD HEVC", "Rai1.it", "y"), b = vlive(1, "Rai 1 HD", "Rai1.it", "x")
        let idx = Variants.build([a, a2, b])
        let g = idx.group(of: b.key)
        h.equal(g?.keys.count ?? 0, 2, "two qualities, not three")
        h.equal(g?.keys.first ?? "", a.key, "the first entry of that quality represents it")
        h.check(idx.group(of: a2.key) === g, "the duplicate can still open the menu")
        h.equal(Variants.build([vlive("Rete 4 HD"), vlive("Rete 4 HD")]).groups, 0)
        h.equal(Variants.build([vlive("Rete 4"), vlive("Rete 4")]).groups, 0)

        let l1 = vlive(1, "La7", "la7.it", "x"), l2 = vlive(1, "La7 HD", "la7.it", "x"), l3 = vlive(1, "La7 SD HD", "la7.it", "x")
        let i2 = Variants.build([l1, l2, l3])
        let g2 = i2.group(of: l1.key)
        h.equal(g2?.keys.count ?? 0, 2)
        h.equal(g2?.q[1] ?? -9, Variants.undeclared)
        h.check(i2.group(of: l3.key) == nil, "tags that disagree are not guessed")

        let m1 = vlive("Film 4K"), m2 = vlive("Film HD")
        m1.kind = .movie; m2.kind = .movie
        h.equal(Variants.build([m1, m2]).groups, 0, "only live channels are indexed")
    }

    h.suite("variants: categories and playlist order do not matter") {
        var r = Lcg(s: 7)
        var l: [Item] = []
        for i in 0..<40 {
            let base = "Canale Prova \(i)"
            l.append(vlive(1, base + " FHD", "cp\(i)", "A\(r.next(5))"))
            l.append(vlive(1, base + " HD", "cp\(i)", "B\(r.next(5))"))
            l.append(vlive(1, base + " SD", "cp\(i)", "C\(r.next(5))"))
        }
        var want: Set<String>?
        for _ in 0..<5 {
            for i in stride(from: l.count - 1, to: 0, by: -1) { l.swapAt(i, r.next(i + 1)) }
            for it in l { it.cat = "Rinominata \(r.next(1000))" }                    // the provider renamed every group overnight
            let idx = Variants.build(l)
            h.equal(idx.groups, 40)
            var sig = Set<String>()
            for it in l {
                guard let g = idx.group(of: it.key) else { h.check(false, "no group for \(it.name)"); continue }
                h.equal(g.keys.count, 3)
                sig.insert(g.keys.sorted().joined(separator: ","))
            }
            if let w = want { h.check(w == sig) } else { want = sig }
        }
    }

    h.suite("variants: many naming styles group without mixing") {
        let styles: [[String]] = [
            ["IT: %@ FHD", "IT: %@ HD", "IT: %@ SD", "IT: %@ 4K"], ["|IT| %@ FHD", "|IT| %@ HD", "|IT| %@ SD", "|IT| %@ UHD"],
            ["%@ [FHD]", "%@ [HD]", "%@ [SD]", "%@ [4K]"], ["%@ (FHD)", "%@ (HD)", "%@ (SD)", "%@ (UHD)"],
            ["%@ Full HD", "%@ HD", "%@ SD", "%@ Ultra HD"], ["%@ 1080p", "%@ 720p", "%@ 576p", "%@ 2160p"],
            ["%@ FHD HEVC", "%@ HD H.264", "%@ SD", "%@ 4K HDR"], ["ITALIA | %@ FHD", "ITALIA | %@ HD", "ITALIA | %@ SD", "ITALIA | %@ 4K"],
            ["%@ ᶠᴴᴰ", "%@ ᴴᴰ", "%@ ˢᴰ", "%@ 4K"], ["★ %@ ★ FHD", "★ %@ ★ HD", "★ %@ ★ SD", "★ %@ ★ 4K"],
            ["%@ - FHD", "%@ - HD", "%@ - SD", "%@ - 4K"], ["%@.FHD", "%@.HD", "%@.SD", "%@.4K"],
        ]
        let channels = ["Alfa Uno", "Alfa Due", "Alfa Tre", "Beta Sport 1", "Beta Sport 2", "Beta Sport +1", "Gamma Kids", "Gamma News 24", "Delta Cinema Action", "Delta Cinema Comedy"]
        var src = 0
        for st in styles {
            src += 1
            var l: [Item] = []
            var per: [[Item]] = []
            for ch in channels {
                let mine = st.map { vlive(src, $0.replacingOccurrences(of: "%@", with: ch), nil, "g") }
                per.append(mine)
                l.append(contentsOf: mine)
            }
            let idx = Variants.build(l)
            h.equal(idx.groups, channels.count, "style \(st[0])")
            for mine in per {
                let g = idx.group(of: mine[0].key)
                h.equal(g?.keys.count ?? 0, 4, st[0])
                h.equal(Set(g?.keys ?? []), Set(mine.map { $0.key }), "no foreign entry in \(st[0])")
            }
        }
    }

    h.suite("variants: large lists are indexed quickly") {
        var l: [Item] = []
        for i in 0..<20000 {
            let base = "Canale z\(String(i, radix: 36)) \(i)"
            if i % 4 == 0 { l.append(vlive(1, base + " FHD", "e\(i)", "g")); l.append(vlive(1, base + " HD", "e\(i)", "g")) }
            else { l.append(vlive(1, base + " HD", "e\(i)", "g")) }
        }
        let t0 = Date()
        let idx = Variants.build(l)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        h.equal(idx.groups, 5000)
        h.equal(idx.members, 10000, "only entries that have a choice are stored")
        h.equal(idx.live, 25000)
        print("    (Variants.build: \(idx.live) channels, \(ms) ms)")
        h.check(ms < 2500, "25,000 channels in \(ms) ms")
    }

    h.suite("variants: cache builds once per snapshot") {
        let lib = Library(dir: tempDir("vc"))
        let a = vlive(1, "Rai 1 FHD", "r", "x"), b = vlive(1, "Rai 1 HD", "r", "x")
        lib.replaceSource(1, [a, b])
        let c = Variants.Cache()
        let s1 = lib.snap
        h.check(c.peek(s1) == nil, "not built until asked")
        let i1 = c.index(s1)
        h.check(i1 === c.index(s1), "the second ask reuses it")
        h.check(i1 === c.peek(s1))
        lib.replaceSource(1, [a, b, vlive(1, "Rai 1 SD", "r", "x")])
        let i2 = c.index(lib.snap)
        h.check(i1 !== i2, "a refresh publishes a new snapshot: a new index")
        h.equal(i2.group(of: a.key)?.keys.count ?? 0, 3)
    }

    h.suite("variants: m3u text -> parser -> index") {
        let m3u = "#EXTM3U\n"
            + "#EXTINF:-1 tvg-id=\"rai1.it\" tvg-logo=\"http://l/1.png\" group-title=\"ITALIA FHD\",IT: Rai 1 FHD\nhttp://host:8080/live/u/p/101.ts\n"
            + "#EXTINF:-1 tvg-id=\"rai1.it\" group-title=\"ITALIA HD\",IT: Rai 1 HD\nhttp://host:8080/live/u/p/102.ts\n"
            + "#EXTINF:-1 tvg-id=\"Rai1.IT\" group-title=\"Backup\",IT: Rai 1 SD\nhttp://host:8080/live/u/p/103.ts\n"
            + "#EXTINF:-1 group-title=\"Altro\",Canale Solo HD\nhttp://host:8080/live/u/p/201.ts\n"
            + "#EXTINF:-1 tvg-id=\"s1\" group-title=\"Sport\",Sky Sport 1 HD\nhttp://host:8080/live/u/p/301.ts\n"
            + "#EXTINF:-1 tvg-id=\"s2\" group-title=\"Sport\",Sky Sport 2 FHD\nhttp://host:8080/live/u/p/302.ts\n"
            + "#EXTINF:-1 group-title=\"Film\",Matrix 4K (1999)\nhttp://host:8080/movie/u/p/555.mkv\n"
            + "#EXTINF:-1 group-title=\"Film\",Matrix HD (1999)\nhttp://host:8080/movie/u/p/556.mkv\n"
        let items = try parseM3U(m3u, src: 5).items
        let idx = Variants.build(items)
        h.equal(idx.groups, 1, "one channel with variants; the decoys and the films are left alone")
        if let rai = items.first(where: { $0.name.contains("Rai 1 HD") }), let g = idx.group(of: rai.key) {
            h.equal(g.keys.count, 3)
            h.check(g.strong, "the guide ids agree (case does not matter)")
        } else { h.check(false, "Rai 1 not grouped") }
        for it in items where it.name.hasPrefix("Sky") || it.name.hasPrefix("Canale") || it.name.hasPrefix("Matrix") {
            h.check(idx.group(of: it.key) == nil, it.name)
        }
    }

    h.suite("variants: codes round trip, preference anchors") {
        for q in [Variants.sd, Variants.hd, Variants.fhd, Variants.uhd, Variants.undeclared] { h.equal(Variants.fromCode(Variants.code(q)), q) }
        h.equal(Variants.fromCode("8K"), Variants.conflict)
        h.equal(Variants.fromCode(nil), Variants.conflict)
        let a = vlive(1, "IT: Rai 1 FHD", "r", "x"), b = vlive(1, "|IT| RAI 1 HD", "r", "y"), other = vlive(2, "Rai 1 FHD", "r", "x")
        h.equal(Variants.anchor(a), Variants.anchor(b), "members of a channel share the anchor whatever their qualities")
        h.check(Variants.anchor(a) != Variants.anchor(other), "another list is another anchor")
    }
}
