@testable import BGlassCore
import Foundation

private func group(_ h: Harness, _ id: String) -> Packs.Group {
    guard let g = Packs.group(id) else { h.check(false, "group \(id) missing"); return Packs.groups[0] }
    return g
}

private func find(_ h: Harness, _ g: Packs.Group, _ entry: String, _ idx: Packs.Index, _ k4: Bool) -> Packs.Result {
    for e in g.entries where e.name == entry { return Packs.resolve(g, e, idx, allow4k: k4) }
    h.check(false, "no entry \(entry) in \(g.id)")
    return Packs.resolve(g, g.entries[0], idx, allow4k: k4)
}

func runPacksChecks(_ h: Harness) {
    h.suite("packs: definition file") {
        let gs = Packs.groups
        h.equal(gs.count, 10)
        h.equal(gs.first?.id ?? "", "intrattenimento")
        var total = 0
        for g in gs { h.check(!g.entries.isEmpty, g.id); total += g.entries.count }
        h.check(total > 300, "about 330 entries, got \(total)")
        h.equal(group(h, "cinema").entries.filter { $0.name.hasPrefix("Primafila ") }.count, 15)
        h.check(group(h, "radio").entries.count > 50)
    }

    h.suite("packs: common provider spellings") {
        let ch: [(String, String)] = [
            ("IT: RAI 1 FHD", "IT | GENERALI"), ("|IT| Rai 2 HD", "IT | GENERALI"), ("RAI 3 HD [IT]", "ITALIA"), ("Rai Uno", "x"),
            ("ITALIA | CANALE 5 HD", "x"), ("Italia 1 ᴴᴰ", "x"), ("LA7 FHD", "x"), ("La 7", "x"),
            ("IT| SKY SPORT UNO FHD", "IT SPORT"), ("SKY SPORT CALCIO (IT) HD", "IT SPORT"), ("Sky Sport 24", "x"),
            ("Sky TG24 HD", "x"), ("SKY CINEMA UNO +24 FHD", "x"), ("SKY CINEMA DUE HD", "x"), ("TV 8", "x"), ("Tv2000", "x"),
            ("DAZN 1 HD", "x"), ("ZONA DAZN 2", "x"), ("Canale5 HD", "x"), ("Cine 34", "x"), ("Real Time", "x"),
        ]
        let (lib, _) = libraryWith(ch)
        let idx = Packs.index(lib.snap)
        let ent = group(h, "intrattenimento"), sport = group(h, "sport"), cin = group(h, "cinema")
        func name(_ g: Packs.Group, _ e: String) -> String { find(h, g, e, idx, false).item?.name ?? "<none>" }
        h.equal(name(ent, "Rai 1 HD"), "IT: RAI 1 FHD")
        h.equal(name(ent, "Rai 2 HD"), "|IT| Rai 2 HD")
        h.equal(name(ent, "Rai 3 HD"), "RAI 3 HD [IT]")
        h.equal(name(ent, "Canale 5 HD"), "ITALIA | CANALE 5 HD")
        h.equal(name(ent, "Italia 1 HD"), "Italia 1 ᴴᴰ")
        h.check(find(h, ent, "La7 HD", idx, false).item != nil)
        h.equal(name(sport, "Sky Sport Uno HD"), "IT| SKY SPORT UNO FHD")
        h.equal(name(sport, "Sky Sport Calcio HD"), "SKY SPORT CALCIO (IT) HD")
        h.equal(name(sport, "Sky Sport 24 HD"), "Sky Sport 24")
        h.equal(name(cin, "Sky Cinema Uno +24 HD"), "SKY CINEMA UNO +24 FHD")
        h.equal(name(cin, "Sky Cinema Due HD"), "SKY CINEMA DUE HD")
        h.equal(name(ent, "TV8 HD"), "TV 8")
        h.equal(name(ent, "TV 2000 HD"), "Tv2000")
        h.equal(name(sport, "ZONA DAZN 1"), "DAZN 1 HD")
        h.equal(name(sport, "ZONA DAZN 2"), "ZONA DAZN 2")
        h.equal(name(cin, "Cine34 HD"), "Cine 34")
        h.equal(name(ent, "Real Time HD"), "Real Time")
        h.check(find(h, ent, "Sky Atlantic HD", idx, false).item == nil)
        h.equal(find(h, ent, "Sky Atlantic HD", idx, false).why, "non trovato")
    }

    h.suite("packs: +1 and similar names are not mixed up") {
        let (lib, _) = libraryWith([("Sky Uno HD", "x"), ("Sky Uno +1 HD", "x"), ("Sky Sport Arena HD", "x"), ("Sky Sport HD", "x"), ("Sky Sport Uno", "x")])
        let idx = Packs.index(lib.snap)
        let ent = group(h, "intrattenimento"), sport = group(h, "sport")
        h.equal(find(h, ent, "Sky Uno HD", idx, false).item?.name ?? "", "Sky Uno HD")
        h.equal(find(h, ent, "Sky Uno +1 HD", idx, false).item?.name ?? "", "Sky Uno +1 HD")
        h.equal(find(h, sport, "Sky Sport HD", idx, false).item?.name ?? "", "Sky Sport HD")
        h.equal(find(h, sport, "Sky Sport Uno HD", idx, false).item?.name ?? "", "Sky Sport Uno")
        h.check(find(h, sport, "Sky Sport Calcio HD", idx, false).item == nil, "Sky Sport Calcio must not match Arena")
    }

    h.suite("packs: HD beats SD, 4K stays out unless asked") {
        let (lib, _) = libraryWith([("IT: Rai 1 SD", "IT"), ("IT: Rai 1 HD", "IT"), ("IT: Rai 1 4K", "IT 4K UHD"), ("IT: Rai 1 HEVC", "IT"),
                                    ("Sky Cinema 4K", "IT 4K"), ("Sky Sport Calcio UHD", "IT 4K")])
        let idx = Packs.index(lib.snap)
        let ent = group(h, "intrattenimento"), cin = group(h, "cinema"), sport = group(h, "sport")
        h.equal(find(h, ent, "Rai 1 HD", idx, false).item?.name ?? "", "IT: Rai 1 HD")
        h.equal(find(h, ent, "Rai 1 HD", idx, false).quality, "HD")
        h.check(find(h, cin, "Sky Cinema 4K", idx, false).item == nil)
        h.equal(find(h, cin, "Sky Cinema 4K", idx, false).why, "solo 4K (escluso)")
        h.check(find(h, sport, "Sky Sport Calcio HD", idx, false).item == nil)
        h.equal(find(h, cin, "Sky Cinema 4K", idx, true).item?.name ?? "", "Sky Cinema 4K")
        h.equal(find(h, sport, "Sky Sport Calcio HD", idx, true).item?.name ?? "", "Sky Sport Calcio UHD")
        h.equal(find(h, ent, "Rai 1 HD", idx, true).item?.name ?? "", "IT: Rai 1 HD")
    }

    h.suite("packs: foreign copies are ignored for Italian channels") {
        let (lib, _) = libraryWith([("UK | Eurosport 1 HD", "UK SPORT"), ("IT | Eurosport 1 HD", "IT SPORT"), ("DE: Eurosport 2", "DE")])
        let idx = Packs.index(lib.snap)
        let sport = group(h, "sport")
        h.equal(find(h, sport, "Eurosport HD", idx, false).item?.name ?? "", "IT | Eurosport 1 HD")
        h.check(find(h, sport, "Eurosport 2 HD", idx, false).item == nil, "a German copy is not an Italian channel")
    }

    h.suite("packs: radio group prefers radio categories") {
        let (lib, _) = libraryWith([("Radio Zeta HD", "IT | Musica TV"), ("Radio Zeta", "IT | Radio")])
        let idx = Packs.index(lib.snap)
        h.equal(find(h, group(h, "radio"), "Radio Zeta", idx, false).item?.name ?? "", "Radio Zeta")
        h.equal(find(h, group(h, "musica"), "Radio Zeta HD", idx, false).item?.name ?? "", "Radio Zeta HD")
    }

    h.suite("packs: clean names") {
        h.equal(Packs.cleanName("IT: SKY TG24 HD"), "SKY TG24 HD")
        h.equal(Packs.cleanName("|IT| Rai 1 HD"), "Rai 1 HD")
        h.equal(Packs.cleanName("ITALIA - La7"), "La7")
        h.equal(Packs.cleanName("Italia 1 HD"), "Italia 1 HD")
        h.equal(Packs.cleanName("IT: Italia 1"), "Italia 1")
        h.equal(Packs.cleanName("UK: Sky Sports"), "UK: Sky Sports")
        h.equal(Packs.cleanName("Rai Italia"), "Rai Italia")
        h.equal(Packs.entryName("cinema/sky cinema 1") ?? "", "Sky Cinema Uno HD")
    }

    h.suite("packs: branded names and mixed quality categories") {
        let (lib, _) = libraryWith([
            ("Discovery Nove HD", "Italia"), ("Discovery Nove SD", "SD (Connessioni Lente)"), ("Sky MTV Italia FHD", "Intrattenimento 4K - FHD"),
            ("Mediaset Canale 20 HD", "Intrattenimento"), ("Samsung+ Fashion TV", "Doc e lifestyle"), ("Discovery Motortrend HD", "Doc e lifestyle"),
            ("Sky Aci Sport TV", "Sport"), ("Sky Uno FHD", "Intrattenimento 4K - FHD"), ("Sky Atlantic", "Intrattenimento 4K - FHD"),
            ("Sky Sport 24 HD", "Sport"), ("Sky Sport Uno HD", "Sport"), ("Sky Cinema Uno \u{2074}\u{1D37}", "Cinema"), ("Sky Cinema Uno \u{1DA0}\u{1D34}\u{1D30}", "Cinema"),
            ("*xxx: Rai 1 HD", "XXX Live"), ("Boing", "Ragazzi"), ("Boing Plus", "Ragazzi"),
        ])
        let idx = Packs.index(lib.snap)
        let ent = group(h, "intrattenimento"), sport = group(h, "sport"), doc = group(h, "documentari"), cin = group(h, "cinema")
        h.equal(find(h, ent, "NOVE HD", idx, false).item?.name ?? "", "Discovery Nove HD")                // HD copy beats the SD one
        h.equal(find(h, ent, "MTV HD", idx, false).item?.name ?? "", "Sky MTV Italia FHD")                // brand words around the name
        h.equal(find(h, ent, "20 Mediaset HD", idx, false).item?.name ?? "", "Mediaset Canale 20 HD")
        h.equal(find(h, doc, "Fashion TV", idx, false).item?.name ?? "", "Samsung+ Fashion TV")
        h.equal(find(h, doc, "Motor Trend HD", idx, false).item?.name ?? "", "Discovery Motortrend HD")   // "motor trend" = "motortrend"
        h.equal(find(h, sport, "ACI Sport TV", idx, false).item?.name ?? "", "Sky Aci Sport TV")
        // a "4K - FHD" category does not turn an FHD channel into a 4K one; an untagged name in it is treated as 4K
        h.equal(find(h, ent, "Sky Uno HD", idx, false).item?.name ?? "", "Sky Uno FHD")
        h.check(find(h, ent, "Sky Atlantic HD", idx, false).item == nil)
        h.equal(find(h, ent, "Sky Atlantic HD", idx, true).item?.name ?? "", "Sky Atlantic")
        // extra words that are not brands make it a different channel
        h.check(find(h, sport, "Sky Sport HD", idx, false).item == nil)
        // superscript quality tags: 4K stays out, FHD is accepted
        h.equal(find(h, cin, "Sky Cinema Uno HD", idx, false).item?.name ?? "", "Sky Cinema Uno \u{1DA0}\u{1D34}\u{1D30}")
        // adult channels are never offered, even when the name would match
        h.check(find(h, ent, "Rai 1 HD", idx, false).item == nil)
    }

    // International lists: the same channel exists for several countries and the Italian one is recognised by an "IT" marker
    // (in the name or in the category). Whatever the style, the Italian copy must win and a foreign copy must never be picked.
    let foreign = ["UK", "DE", "FR", "ES", "PT", "NL", "TR"]
    func international(_ label: String, markItalian: Bool, name: @escaping (String, String) -> String, cat: @escaping (String) -> String) {
        h.suite("packs: international list \(label)") {
            let lib = Library(dir: tempDir("intl"))
            var s = Source()
            s.name = "I"; s.type = .xtream; s.url = "http://x"; s.user = "u"; s.pass = "p"
            s = lib.addSource(s)
            var items: [Item] = []
            var italianKey: [String: String] = [:]
            var seen = Set<String>()
            var i = 0
            func mk(_ n: String, _ c: String) -> Item { i += 1; return live(s.id, String(i), n, c) }
            for g in Packs.groups where g.id != "news_int" {
                for e in g.entries {
                    if e.name.contains("4K") || !seen.insert(e.name).inserted { continue }
                    for cc in foreign { items.append(mk(name(e.name, cc), cat(cc))) }
                    let it = mk(markItalian ? name(e.name, "IT") : e.name, markItalian ? cat("IT") : "Channels")
                    items.append(it)
                    italianKey[e.name] = it.key
                }
            }
            lib.replaceSource(s.id, items)
            let idx = Packs.index(lib.snap)
            var ok = 0, total = 0
            var bad: [String] = []
            let foreignRe = try NSRegularExpression(pattern: "-> (UK|DE|FR|ES|PT|NL|TR)\\b|\\[(UK|DE|FR|ES|PT|NL|TR)\\b")
            for g in Packs.groups where g.id != "news_int" {
                for e in g.entries {
                    if e.name.contains("4K") || e.name == "Sky Sport HD" { continue }
                    let r = Packs.resolve(g, e, idx, allow4k: false)
                    total += 1
                    guard let it = r.item else { bad.append("MISS " + e.name); continue }
                    if it.key == italianKey[e.name] { ok += 1 }
                    else if Packs.sameChannel(it.name, e.name) || Packs.variantFlats(it.name).isSuperset(of: Packs.variantFlats(e.name)) { ok += 1 }   // another Italian spelling of the same entry
                    else { bad.append("WRONG \(e.name) -> \(it.name) [\(it.cat)]") }
                }
            }
            for x in bad where x.hasPrefix("WRONG") && foreignRe.firstMatch(in: x, range: NSRange(location: 0, length: (x as NSString).length)) != nil {
                h.check(false, "\(label): picked a foreign copy: \(x)")
            }
            print("    (\(label): \(ok)/\(total) matched, \(items.count) channels in the list)")
            h.check(total > 250, "\(label): only \(total) entries tried")
            h.check(Double(ok) >= Double(total) * 0.97, "\(label): \(ok)/\(total)\n" + bad.prefix(15).joined(separator: "\n"))
        }
    }
    international("IT: name", markItalian: true, name: { n, cc in cc + ": " + n }, cat: { _ in "Channels" })
    international("IT| NAME", markItalian: true, name: { n, cc in cc + "| " + n.uppercased() }, cat: { _ in "Mixed" })
    international("IT name", markItalian: true, name: { n, cc in cc + " " + n }, cat: { _ in "World" })
    international("name (IT)", markItalian: true, name: { n, cc in n + " (" + cc + ")" }, cat: { _ in "World" })
    international("category IT", markItalian: true, name: { n, _ in n }, cat: { cc in cc + " | SPORT" })
    international("category Italia/Germany", markItalian: true, name: { n, _ in n }, cat: { cc in
        switch cc {
        case "IT": return "Italia - Canali"
        case "UK": return "United Kingdom"
        case "DE": return "Germany Sport"
        case "FR": return "France"
        case "ES": return "Spain"
        case "PT": return "Portugal"
        default: return "Turkey"
        }
    })
    international("foreign marked", markItalian: false, name: { n, cc in cc + ": " + n }, cat: { _ in "All" })
    international("101| IT: name", markItalian: true, name: { n, cc in "101| " + cc + ": " + n + " HD" }, cat: { _ in "Live" })
}

func runCatalogChecks(_ h: Harness) {
    h.suite("catalog: main channels, filters, my list") {
        let (lib, src) = libraryWith([
            ("IT: RAI 1 FHD", "IT | Generali"), ("IT: RAI 1 HD", "IT | Generali"), ("Canale5 HD", "IT | Generali"), ("UK | Sky Sports Main Event", "UK"),
            ("IT| SKY SPORT UNO FHD", "IT | Sport"), ("Sky Cinema Uno HD", "IT | Cinema"), ("Radio Zeta", "IT | Radio"), ("*xxx: Rai 1 HD", "XXX Live"),
            ("Canale Locale", "IT | Locali"),
        ])
        let b = Backend(dir: tempDir("catalog"))
        b.lib.replaceSource(src, [])                       // (unused source id 1 in this backend)
        var s = Source(); s.name = "T"; s.type = .xtream; s.url = "http://x"; s.user = "u"; s.pass = "p"
        s = b.lib.addSource(s)
        b.lib.replaceSource(s.id, lib.snap.items.map { it in
            let c = Item(src: s.id, kind: .live, key: it.key.replacingOccurrences(of: "\(src):", with: "\(s.id):"), name: it.name, cat: it.cat)
            c.sid = it.sid; c.epgId = ""; return c
        })
        let main = b.mainChannels()
        h.equal(main.map { $0.name }, ["Rai 1", "Canale 5", "Sky Cinema Uno", "Sky Sport Uno"], "clean names in pack order, no radios")
        h.equal(main.first?.key ?? "", "\(s.id):l:2", "the HD copy is the main Rai 1")
        var p = b.profiles.create(name: "Io", color: 0)
        let m = b.channels(.main, profile: p)
        h.equal(m.map { $0.num }, [1, 2, 3, 4])
        h.equal(b.channels(.all, profile: p).count, 8, "adult channels are hidden")
        let cats = b.liveCategories(profile: p)
        h.check(!cats.contains { $0.name == "XXX Live" })
        h.equal(b.channels(.category(src: s.id, name: "IT | Generali"), profile: p).count, 3)
        _ = b.toggleFav(p.id, key: "\(s.id):l:9")
        p = b.profiles.get(p.id)!
        h.equal(b.channels(.favorites, profile: p).map { $0.name }, ["Canale Locale"])
        h.check(b.channels(.all, profile: p).first { $0.key == "\(s.id):l:9" }?.fav ?? false)
        h.equal(b.channelRows(["\(s.id):l:5", "\(s.id):l:2"], profile: p).map { $0.name }, ["Sky Sport Uno", "Rai 1"])
        h.check(b.guideKeys().starts(with: main.map { $0.key }))
        h.check(!b.guideKeys().contains("\(s.id):l:8"), "no guide for adult channels")
        // my list: films and series only
        let film = Item(src: s.id, kind: .movie, key: "\(s.id):m:1", name: "Film", cat: "Azione")
        b.lib.replaceKinds(s.id, kinds: [.movie], [film], wanted: nil)
        h.check(b.toggleMyList(p.id, key: film.key))
        h.equal(b.myList(profile: b.profiles.get(p.id)!).map { $0.key }, [film.key])
        h.check(!b.toggleMyList(p.id, key: film.key))
        h.check(b.myList(profile: b.profiles.get(p.id)!).isEmpty)
        h.check(!b.toggleMyList(p.id, key: "\(s.id):l:2"), "channels are not for my list")
        // the whole catalogue feeds the rows, whatever the profile picked
        let rows = b.vodRows(profile: b.profiles.get(p.id)!, kind: .movie, all: true)
        h.equal(rows.rows.first?.items.first?.key ?? "", film.key)
        h.equal(b.vodItems(profile: b.profiles.get(p.id)!, kind: .movie, cats: ["Azione"], all: true).total, 1)
    }
}
