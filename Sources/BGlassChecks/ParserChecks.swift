@testable import BGlassCore
import Foundation

func runParserChecks(_ h: Harness) {
    h.suite("m3u: list banners are not content") {
        let m3u = "#EXTM3U\n#EXTINF:-1 group-title=\"Film\",---- Vetrina NOVITA ----\nhttp://h/movie/u/p/1.mp4\n"
            + "#EXTINF:-1 group-title=\"Film\",Matrix (1999)\nhttp://h/movie/u/p/2.mp4\n"
        let r = try parseM3U(m3u)
        h.equal(r.items.count, 1)
        h.equal(r.items.first?.name ?? "", "Matrix (1999)")
    }

    h.suite("m3u: basics") {
        let m3u = "\u{FEFF}#EXTM3U url-tvg=\"http://epg.example/guide.xml.gz\"\n"
            + "#EXTINF:-1 tvg-id=\"rai1.it\" tvg-name=\"Rai 1 HD\" tvg-logo=\"http://l/rai1.png\" group-title=\"Italia, Generali\",Rai 1 HD\n"
            + "http://host:8080/live/u/p/101.ts\n"
            + "#EXTINF:-1 tvg-id=\"\" group-title=\"Film\",Matrix (1999)\n"
            + "http://host:8080/movie/u/p/555.mkv\n"
            + "#EXTINF:-1 group-title=\"Serie\",Breaking Bad S01E02\n"
            + "http://host:8080/series/u/p/900.mp4\n"
            + "#EXTINF:-1 group-title=\"Serie\",Breaking Bad S01E01\n"
            + "http://host:8080/series/u/p/899.mp4\n"
            + "#EXTINF:-1,Senza gruppo\n"
            + "#EXTVLCOPT:http-user-agent=MyUA\n"
            + "http://host/x.m3u8\n"
        let r = try parseM3U(m3u, src: 7)
        h.equal(r.meta.epgUrl ?? "", "http://epg.example/guide.xml.gz")
        h.equal(r.meta.count, 5)
        h.equal(r.items.count, 4)                                        // 2 live + 1 movie + 1 folded series
        guard r.items.count == 4 else { return }
        let a = r.items[0]
        h.equal(a.name, "Rai 1 HD")
        h.equal(a.cat, "Italia, Generali")                              // comma inside quotes
        h.equal(a.epgId ?? "", "rai1.it")
        h.equal(a.logo ?? "", "http://l/rai1.png")
        h.check(a.kind == .live)
        h.equal(a.url ?? "", "http://host:8080/live/u/p/101.ts")          // prefix + tail round-trips
        h.check(a.key.hasPrefix("7:l:"))
        h.check(r.items[1].kind == .movie)
        h.equal(r.items[2].cat, "Altro")
        h.equal(r.items[2].ua ?? "", "MyUA")
        let show = r.items[3]
        h.check(show.kind == .series)
        h.equal(show.name, "Breaking Bad")
        h.equal(show.extra ?? "", "2 episodi")
        let eps = M3UParser.episodes(of: show)
        h.equal(eps.count, 2)
        if eps.count == 2 {
            h.equal(eps[0].season, 1)
            h.equal(eps[0].number, 2)                                    // playlist order is kept
            h.equal(eps[0].url, "http://host:8080/series/u/p/900.mp4")
            h.equal(eps[1].url, "http://host:8080/series/u/p/899.mp4")
        }
    }

    h.suite("m3u: scales and skips unwanted kinds") {
        var sb = "#EXTM3U\n"
        for i in 0..<60000 {
            sb += "#EXTINF:-1 group-title=\"Serie \((i / 12) % 50)\",Show \(i / 12) S01E\(i % 12 + 1)\nhttp://h:80/series/u/p/\(i).mkv\n"
        }
        for i in 0..<30000 { sb += "#EXTINF:-1 group-title=\"Film\",Film \(i)\nhttp://h:80/movie/u/p/\(i).mp4\n" }
        for i in 0..<500 { sb += "#EXTINF:-1 group-title=\"Live\",Canale \(i)\nhttp://h:80/u/p/\(i)\n" }
        let data = Data(sb.utf8)
        var counts = [0, 0, 0, 0]
        let t0 = Date()
        let meta = try M3UParser.parse(data: data, srcId: 1, wantLive: true, wantMovies: false, wantSeries: true) { counts[$0.kind.rawValue] += 1 }
        let dt = Date().timeIntervalSince(t0)
        h.equal(meta.count, 90500)
        h.equal(counts[Kind.movie.rawValue], 0)
        h.equal(counts[Kind.live.rawValue], 500)
        h.equal(counts[Kind.series.rawValue], 5000)                       // 60000 episodes fold into 5000 shows
        print("    (90,500 entries parsed in \(String(format: "%.2f", dt)) s)")
        h.check(dt < 20, "parsing 90k entries took \(dt) s")
    }

    h.suite("m3u: entries without address hints use safe hints") {
        let m3u = "#EXTM3U\n"
            + "#EXTINF:-1 group-title=\"Italia\",Rai 1 HD\nhttp://h:80/u/p/101\n"
            + "#EXTINF:-1 group-title=\"News\",News 24x7\nhttp://h:80/u/p/102\n"
            + "#EXTINF:-1 group-title=\"Serie TV\",Dark S01E01\nhttp://h:80/u/p/201\n"
            + "#EXTINF:-1 group-title=\"Serie TV\",Dark S01E02\nhttp://h:80/u/p/202\n"
            + "#EXTINF:-1 group-title=\"VOD | Azione\",Il Film\nhttp://h:80/u/p/301\n"
            + "#EXTINF:-1 group-title=\"Film 24\",Film Channel\nhttp://h:80/u/p/103\n"
            + "#EXTINF:-1 group-title=\"VOD | Azione\",Canale che sembra film\nhttp://h:80/live/u/p/104.m3u8\n"
        let r = try parseM3U(m3u)
        let live = r.items.filter { $0.kind == .live }.count
        let movies = r.items.filter { $0.kind == .movie }.count
        let series = r.items.filter { $0.kind == .series }.count
        h.equal(live, 4, "Rai 1, News 24x7, Film Channel and the /live/ address stay channels")
        h.equal(movies, 1)
        h.equal(series, 1, "two S01Exx lines fold into one series")
    }

    h.suite("library: round trip, search, key remap") {
        let dir = tempDir("libsave")
        let lib = Library(dir: dir)
        var s = Source()
        s.name = "T"; s.url = "http://x"; s.type = .m3u
        s = lib.addSource(s)
        var items: [Item] = []
        for (n, c) in [("Sky Sport 1", "Sport"), ("Sky Sport 2", "Sport"), ("Rai 1", "Italia"), ("Canale 5", "Italia")] {
            items.append(Item(src: s.id, kind: .live, key: "\(s.id):l:\(Hash.fnv(n))", name: n, cat: c))
        }
        lib.replaceSource(s.id, items)
        h.equal(lib.snap.categories(src: s.id, kind: .live).count, 2)
        h.equal(lib.snap.search(kind: .live, query: "sky sport", limit: 50).total, 2)
        h.equal(lib.snap.search(src: s.id, kind: .live, cat: "Italia", query: "rai", limit: 50).items.count, 1)

        let withEps = Item(src: s.id, kind: .series, key: "\(s.id):s:x", name: "Show", cat: "Serie")
        withEps.ub = "http://h/series/"
        withEps.eps = "1\t1\tPilot\t1.mp4\n1\t2\tSecond\t\u{1}http://other/2.mp4\n"
        lib.replaceSource(s.id, lib.snap.items + [withEps])
        lib.save()

        let lib2 = Library(dir: dir)
        var sourcesTold = 0, liveTold = 0
        lib2.load(onSources: { sourcesTold += 1 }, onLive: { liveTold += 1 })
        h.equal(sourcesTold, 1)
        h.equal(liveTold, 1)
        h.equal(lib2.snap.items.count, 5)
        if let back = lib2.snap.byKey[withEps.key] {
            let eps = M3UParser.episodes(of: back)
            h.equal(eps.count, 2)
            if eps.count == 2 {
                h.equal(eps[0].url, "http://h/series/1.mp4")
                h.equal(eps[1].url, "http://other/2.mp4")
            }
        } else { h.check(false, "series lost in the round trip") }
        h.equal(lib2.sources.count, 1)

        // key remap on refresh: the key changes, the name stays
        let fresh = Item(src: s.id, kind: .live, key: "\(s.id):l:new", name: "Rai 1 HD", cat: "Italia")
        let oldKey = "\(s.id):l:\(Hash.fnv("Rai 1"))"
        let remap = lib2.replaceSource(s.id, [fresh], wanted: [oldKey])
        h.equal(remap[oldKey] ?? "", "\(s.id):l:new")
        var pr = Profile()
        pr.live.insert(oldKey)
        pr.remapKeys(remap)
        h.check(pr.live.contains("\(s.id):l:new"))
    }

    h.suite("profile: resume, recents, pack forgetting") {
        var p = Profile()
        p.saveResume("m1", pos: 1000, dur: 100000)                          // too early: ignored
        h.check(p.resume["m1"] == nil)
        p.saveResume("m1", pos: 20000, dur: 100000)
        h.equal(p.resume["m1"] ?? 0, 20000)
        p.saveResume("m1", pos: 99000, dur: 100000)                         // finished: cleared
        h.check(p.resume["m1"] == nil)
        for i in 0..<70 { p.saveResume("k\(i)", pos: 5000, dur: 100000, now: Int64(1000 + i)) }
        h.equal(p.resume.count, 60)
        h.check(p.resume["k0"] == nil && p.resume["k69"] != nil, "the oldest positions go first")
        for i in 0..<45 { p.touchRecent("r\(i)") }
        h.equal(p.recent.count, 40)
        h.equal(p.recent.first ?? "", "r44")
        p.packMap = ["a/x": "1:l:1", "a/y": "1:l:2"]
        p.packForget(["1:l:2"])
        h.equal(p.packMap.count, 1)
        h.check(p.packOff.contains("a/y"))
    }

    h.suite("xtream addresses") {
        h.equal(XtreamClient.normalizeBase("host:8080"), "http://host:8080")
        h.equal(XtreamClient.normalizeBase("http://host/get.php?username=a&password=b"), "http://host")
        h.equal(XtreamClient.normalizeBase("http://host:80/c/"), "http://host:80")
        h.equal(XtreamClient.normalizeBase("HTTPS://Example.com/panel/c/"), "https://example.com/panel")
        h.equal(XtreamClient.normalizeBase("https://example.com:443"), "https://example.com:443")
        h.equal(XtreamClient.normalizeBase("example.com"), "http://example.com")
        let g = XtreamClient.fromGetPhp("http://host:8080/get.php?username=us&password=pw&type=m3u_plus")
        h.equal(g?.base ?? "", "http://host:8080")
        h.equal(g?.user ?? "", "us")
        h.equal(g?.pass ?? "", "pw")
        h.check(XtreamClient.fromGetPhp("http://host/other?username=a&password=b") == nil)
        h.equal(XtreamClient.enc("a b&c"), "a+b%26c")
        h.equal(XtreamClient.b64("VGcxIGRlbGxhIHNlcmE="), "Tg1 della sera")
        h.equal(XtreamClient.b64("Notizie"), "Notizie")
    }
}
