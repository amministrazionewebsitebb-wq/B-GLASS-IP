@testable import BGlassCore
import Foundation

// MARK: a pretend Xtream panel

private struct Panel {
    var authOK = true
    var live: [(id: Int, name: String, cat: Int, epg: String)] = [
        (101, "IT: RAI 1 FHD", 1, "rai1.it"), (102, "IT: RAI 1 HD", 1, "rai1.it"), (103, "IT: RAI 2 HD", 1, "rai2.it"),
        (104, "IT: CANALE 5 HD", 1, "canale5.it"), (105, "IT: SKY SPORT UNO HD", 2, "skysportuno.it"), (106, "UK | Eurosport 1", 3, "eurosport.uk"),
        (107, "---- Italia ----", 1, ""), (108, "Escort Channel", 4, ""),
    ]
}

private func json(_ s: String) -> TestServer.Response { TestServer.Response(s, headers: ["Content-Type": "application/json"]) }

private func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

private func xmltvTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMddHHmmss"
    return f.string(from: d) + " +0000"
}

private func makeXMLTV() -> String {
    let now = Date()
    func prog(_ ch: String, _ a: Double, _ b: Double, _ title: String, _ desc: String) -> String {
        "<programme start=\"\(xmltvTime(now.addingTimeInterval(a)))\" stop=\"\(xmltvTime(now.addingTimeInterval(b)))\" channel=\"\(ch)\"><title lang=\"it\">\(title)</title><desc>\(desc)</desc></programme>"
    }
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><tv>"
        + "<channel id=\"Rai1.IT\"><display-name>Rai 1 HD</display-name></channel>"
        + "<channel id=\"x.5\"><display-name>Canale 5 HD</display-name><display-name>Canale5</display-name></channel>"
        + "<channel id=\"other\"><display-name>Altro</display-name></channel>"
        + prog("Rai1.IT", -1800, 1800, "Telegiornale", "Notizie &amp; co")
        + prog("Rai1.IT", 1800, 5400, "Film della sera", "Un film")
        + prog("x.5", -600, 3000, "Tg5", "")
        + prog("other", -600, 3000, "Non voluto", "")
        + "</tv>"
}

private func startPanel(_ p: @escaping () -> Panel) throws -> TestServer {
    let xml = Data(makeXMLTV().utf8)
    let xmlGz = gzipped(xml)
    var vod = "["
    for i in 1...40 {
        let cat = i % 4 == 0 ? 12 : (i % 2 == 0 ? 10 : 11)
        vod += (i > 1 ? "," : "") + "{\"num\":\(i),\"name\":\"Film \(i) (\(1990 + i))\",\"stream_type\":\"movie\",\"stream_id\":\(500 + i),\"stream_icon\":\"http://img/p\(i).jpg\","
            + "\"rating\":\"\(Double(i % 10) + 0.5)\",\"rating_5based\":3.5,\"added\":\"\(1_700_000_000 + i * 100_000)\",\"category_id\":\"\(cat)\",\"container_extension\":\"mkv\","
            + "\"custom_sid\":null,\"direct_source\":\"\",\"tags\":{\"a\":[1,2,{\"b\":\"}\"}]},\"plot\":\"Caff\\u00e8 \\ud83d\\ude00 \\\"q\\\"\"}"
    }
    vod += "]"
    return try TestServer { path, q in
        let p = p()
        if path == "/player_api.php" {
            switch q["action"] ?? "" {
            case "":
                if !p.authOK || q["password"] != "p" { return json("{\"user_info\":{\"auth\":0,\"status\":\"Disabled\"}}") }
                return json("{\"user_info\":{\"auth\":1,\"status\":\"Active\",\"exp_date\":\"1893456000\",\"max_connections\":\"2\",\"active_cons\":\"0\",\"allowed_output_formats\":[\"m3u8\",\"ts\"]},\"server_info\":{}}")
            case "get_live_categories": return json("[{\"category_id\":\"1\",\"category_name\":\"IT | Generali\"},{\"category_id\":\"2\",\"category_name\":\"IT | Sport\"},{\"category_id\":\"3\",\"category_name\":\"UK | Sport\"},{\"category_id\":\"4\",\"category_name\":\"XXX Live\"}]")
            case "get_live_streams":
                return json("[" + p.live.map { "{\"num\":\($0.id - 100),\"name\":\"\(esc($0.name))\",\"stream_id\":\($0.id),\"category_id\":\"\($0.cat)\",\"stream_icon\":\"http://img/\($0.id).png\",\"epg_channel_id\":\"\($0.epg)\",\"direct_source\":\"\($0.id == 103 ? "http://origin.example/rai2.m3u8" : "")\"}" }.joined(separator: ",") + "]")
            case "get_vod_categories": return json("[{\"category_id\":\"10\",\"category_name\":\"Azione\"},{\"category_id\":\"11\",\"category_name\":\"Commedia\"},{\"category_id\":\"12\",\"category_name\":\"Film più visti\"}]")
            case "get_vod_streams": return json(vod)
            case "get_series_categories": return json("[{\"category_id\":\"20\",\"category_name\":\"Serie TV\"}]")
            case "get_series":
                return json("{\"0\":{\"series_id\":7,\"name\":\"Dark\",\"category_id\":\"20\",\"cover\":\"http://img/dark.jpg\",\"rating\":\"8.7\",\"releaseDate\":\"2017-12-01\",\"last_modified\":\"1700000000\"},\"1\":{\"series_id\":8,\"name\":\"Lupin\",\"category_id\":\"20\",\"cover\":\"\",\"rating\":\"0\"}}")
            case "get_series_info":
                return json("{\"info\":{\"name\":\"Dark\",\"plot\":\"Tempo\",\"genre\":\"Drammatico\",\"releaseDate\":\"2017-12-01\",\"backdrop_path\":[\"http://img/b1.jpg\",\"x\"]},\"episodes\":{\"1\":[{\"id\":\"9002\",\"title\":\"Segreti\",\"container_extension\":\"mp4\",\"season\":1,\"episode_num\":2,\"info\":{\"duration\":\"00:50:00\"}},{\"id\":\"9001\",\"title\":\"Passato\",\"container_extension\":\"mp4\",\"season\":1,\"episode_num\":1}],\"2\":[{\"id\":\"9010\",\"title\":\"Nuovo\",\"container_extension\":\"mkv\",\"season\":2,\"episode_num\":1}]}}")
            case "get_vod_info": return json("{\"info\":{\"plot\":\"Trama\",\"genre\":\"Azione, Avventura\",\"releasedate\":\"2020-05-05\",\"movie_image\":\"http://img/m.jpg\",\"backdrop_path\":\"http://img/bd.jpg\",\"duration\":\"01:40:00\"}}")
            case "get_short_epg": return json("{\"epg_listings\":[]}")
            default: return TestServer.Response("[]")
            }
        }
        if path == "/xmltv.php" { return TestServer.Response(xmlGz, headers: ["Content-Type": "application/gzip"]) }
        if path == "/list.m3u" || path == "/list404.m3u" {
            if path == "/list404.m3u" { return TestServer.Response("nope", status: 404) }
            return TestServer.Response("#EXTM3U\n#EXTINF:-1 tvg-id=\"rai1.it\" group-title=\"Italia\",IT: Rai 1 HD\nhttp://h/live/u/p/1.ts\n#EXTINF:-1 group-title=\"Film\",Heat (1995)\nhttp://h/movie/u/p/9.mp4\n")
        }
        if path == "/list.m3u.gz" { return TestServer.Response(gzipped(Data("#EXTM3U\n#EXTINF:-1 group-title=\"Italia\",Rai 3 HD\nhttp://h/live/u/p/3.ts\n".utf8))) }
        return TestServer.Response("not found", status: 404)
    }
}

private func newBackend(_ dir: URL = tempDir("backend")) -> Backend {
    let b = Backend(dir: dir)
    b.loadAll()
    return b
}

private func xtreamSource(_ base: String, pass: String = "p") -> Source {
    var s = Source()
    s.name = "Pannello"; s.type = .xtream; s.url = base; s.user = "u"; s.pass = pass
    return s
}

func runNetworkChecks(_ h: Harness) async {
    await h.suite("flat json streaming") {
        let text = "\u{FEFF} [ {\"a\":\"x\\u00e8\\ud83d\\ude00y\",\"n\":12,\"f\":1.5,\"t\":true,\"z\":null,\"o\":{\"k\":[1,{\"q\":\"}\"}]},\"s\":\"q\\\"uote\\\\\"}, 7, {\"a\":\"second\"} ]"
        var got: [[String: String]] = []
        try FlatJSON.forEachObject(in: Data(text.utf8)) { got.append($0) }
        h.equal(got.count, 2)
        if got.count == 2 {
            h.equal(got[0]["a"] ?? "", "xè😀y")
            h.equal(got[0]["n"] ?? "", "12")
            h.equal(got[0]["f"] ?? "", "1.5")
            h.equal(got[0]["t"] ?? "", "true")
            h.check(got[0]["z"] == nil && got[0]["o"] == nil)
            h.equal(got[0]["s"] ?? "", "q\"uote\\")
            h.equal(got[1]["a"] ?? "", "second")
        }
        var wrapped = 0
        try FlatJSON.forEachObject(in: Data("{\"0\":{\"id\":1},\"1\":{\"id\":2},\"err\":\"x\"}".utf8)) { _ in wrapped += 1 }
        h.equal(wrapped, 2)
        var only: [String: String] = [:]
        try FlatJSON.forEachObject(in: Data("[{\"keep\":\"1\",\"drop\":\"2\"}]".utf8), keys: ["keep"]) { only = $0 }
        h.equal(only, ["keep": "1"])
        var threw = false
        do { try FlatJSON.forEachObject(in: Data("[{\"a\":\"1\"},{\"a\":".utf8)) { _ in } } catch { threw = true }
        h.check(threw, "a truncated download must not pass for a complete one")
        threw = false
        do { try FlatJSON.forEachObject(in: Data("<html>error</html>".utf8)) { _ in } } catch { threw = true }
        h.check(threw)
    }

    await h.suite("gzip") {
        var text = ""
        for i in 0..<200_000 { text += "line \(i) \(i * 7 % 13) lorem ipsum dolor sit amet\n" }
        let plain = Data(text.utf8)
        let gz = gzipped(plain)
        h.check(gz.count < plain.count / 3 && Gzip.isGzip(gz))
        let inflated = try Gzip.inflate(gz)
        h.check(inflated == plain, "in-memory inflate")
        let a = tempDir("gz").appendingPathComponent("a.gz"), b = tempDir("gz").appendingPathComponent("a.txt")
        try gz.write(to: a)
        try Gzip.inflateFile(from: a, to: b)
        let streamed = try Data(contentsOf: b)
        h.check(streamed == plain, "streamed inflate of \(plain.count / 1_000_000) MB")
        h.check(Gzip.fileIsGzip(a) && !Gzip.fileIsGzip(b))
    }

    await h.suite("xmltv") {
        let xml = makeXMLTV()
        let now = Int64(Date().timeIntervalSince1970)
        let r = try XMLTV.parse(data: Data(xml.utf8), wantedIds: ["rai1.it"], wantedNames: [Hash.norm("Canale 5 HD")], from: now - 3 * 3600, to: now + 36 * 3600)
        h.equal(r.progs.count, 2)
        h.equal(r.progs["rai1.it"]?.count ?? 0, 2)
        h.equal(r.progs["rai1.it"]?.first?.t ?? "", "Telegiornale")
        h.equal(r.progs["rai1.it"]?.first?.d ?? "", "Notizie & co")
        h.equal(r.nameToId["canale 5"] ?? "", "x.5")
        h.check(r.progs["other"] == nil)
        h.equal(XMLTV.parseTime("20260101190000 +0100"), 1767290400)
        h.equal(XMLTV.parseTime("20260101190000"), 1767294000)
        h.equal(XMLTV.parseTime("garbage"), 0)
    }

    guard let server = try? startPanelServer() else { h.check(false, "could not start the test server"); return }
    defer { server.stop() }

    await h.suite("xtream account and errors") {
        let b = newBackend()
        let a = try await XtreamClient(xtreamSource(server.base)).auth()
        h.check(a.ok && a.hls)
        h.equal(a.maxConn, "2")
        h.check(a.expTs == 1893456000 && a.expires.hasSuffix("/2030"))
        let bad = try await XtreamClient(xtreamSource(server.base, pass: "wrong")).auth()
        h.check(!bad.ok)
        h.equal(bad.message, "Account disattivato dal fornitore")
        let msg = try await b.test(xtreamSource(server.base))
        h.check(msg.contains("Account active") || msg.contains("attivo") || msg.contains("active"), msg)
        var thrown = ""
        do { _ = try await b.test(xtreamSource(server.base, pass: "wrong")) } catch { thrown = Net.explain(error) }
        h.equal(thrown, "Account disattivato dal fornitore")
    }

    await h.suite("xtream refresh, library, profile, rows, search") {
        let dir = tempDir("e2e")
        let b = newBackend(dir)
        let s = b.lib.addSource(xtreamSource(server.base))
        var phases: [String] = []
        let plock = NSLock()
        try await b.refreshSource(s.id) { phase, _, _ in plock.lock(); phases.append(phase); plock.unlock() }
        let st = b.lib.source(s.id)!
        h.equal(st.nLive, 7, "8 entries minus the list header")
        h.equal(st.nMovies, 40)
        h.equal(st.nSeries, 2)
        h.check(st.hls && st.fmtChecked)
        h.check(st.updated > 0 && st.status.isEmpty)
        h.check(phases.contains("auth") && phases.contains("part") && phases.contains("save"), "progress phases: \(phases)")
        let sn = b.lib.snap
        h.equal(sn.items.count, 49)
        h.check(sn.byKey["\(s.id):l:101"] != nil && sn.byKey["\(s.id):m:501"] != nil && sn.byKey["\(s.id):s:7"] != nil)
        h.equal(sn.byKey["\(s.id):m:501"]?.ext ?? "", "mkv")
        h.equal(sn.byKey["\(s.id):s:8"]?.logo == nil, true, "an empty cover is no cover")

        // a profile that picks the Italian channels and every film and series
        let prof = b.profiles.create(name: "Bruno", color: 2)
        b.selectCategory(prof.id, kind: .live, src: s.id, cat: "IT | Generali", on: true)
        h.equal(b.profiles.get(prof.id)?.live.count ?? 0, 4)
        b.selectCategory(prof.id, kind: .live, src: s.id, cat: "XXX Live", on: true)
        let cats = b.libCategories(profile: b.profiles.get(prof.id), kind: .live)
        h.check(!cats.contains { $0.name == "XXX Live" }, "adult categories are hidden by default")
        for c in b.libCategories(profile: nil, kind: .movie) { b.selectCategory(prof.id, kind: .movie, src: c.src, cat: c.name, on: true) }
        b.selectQuery(prof.id, kind: .series, src: -1, cat: nil, query: "dar", on: true)
        h.equal(b.profiles.get(prof.id)?.movies.count ?? 0, 40)
        h.equal(b.profiles.get(prof.id)?.series.count ?? 0, 1)

        // pack: "intrattenimento" finds Rai 1 (FHD wins over HD? HD is preferred), Rai 2, Canale 5
        b.setPack(prof.id, group: "intrattenimento", on: true)
        let p1 = b.profiles.get(prof.id)!
        h.check(p1.packMap.count >= 3, "pack found \(p1.packMap.count) channels")
        let live = b.liveList(profile: p1)
        h.check(live.contains { $0.name == "Rai 1 HD" || $0.name == "RAI 1 HD" }, "curated names: \(live.map { $0.name })")

        // Netflix style rows
        let rows = b.vodRows(profile: p1, kind: .movie, per: 10)
        let titles = rows.rows.map { $0.title }
        h.check(titles.first == "Di tendenza", "trending category first: \(titles)")
        h.check(titles.contains("Film aggiunti di recente") && titles.contains("I più votati"), "\(titles)")
        h.check(titles.contains("Azione") && titles.contains("Commedia"), "genre rows: \(titles)")
        h.check(rows.rows.allSatisfy { $0.items.count <= 10 })
        let azione = rows.rows.first { $0.title == "Azione" }
        h.equal(azione?.total ?? 0, 10)
        let page = b.vodItems(profile: p1, kind: .movie, cats: azione?.cats, genre: azione?.genre, offset: 5, limit: 3)
        h.equal(page.total, 10)
        h.equal(page.items.count, 3)

        // search
        let r = b.search("rai", profile: p1)
        h.check(r.live.count >= 2, "search live: \(r.live.map { $0.name })")
        h.equal(b.search("ra", profile: p1).isEmpty, true, "two letters are not searched")
        let all = b.search("eurosport", profile: p1, everything: true)
        h.equal(all.liveTotal, 1, "whole list search finds what the profile does not have")
        h.equal(b.search("eurosport", profile: p1).liveTotal, 0)

        // playback addresses
        let rai = sn.byKey["\(s.id):l:101"]!
        let play = await b.resolve(rai)
        h.equal(play?.url ?? "", "\(server.base)/live/u/p/101.m3u8")
        h.equal(play?.alt ?? "", "\(server.base)/live/u/p/101.ts")
        let rai2 = await b.resolve(sn.byKey["\(s.id):l:103"]!)
        h.equal(rai2?.url ?? "", "\(server.base)/live/u/p/103.m3u8", "the panel address stays the first choice")
        h.equal(rai2?.alts.last ?? "", "http://origin.example/rai2.m3u8", "the direct source is one more way")
        let movie = await b.resolve(sn.byKey["\(s.id):m:501"]!)
        h.equal(movie?.url ?? "", "\(server.base)/movie/u/p/501.mkv")

        // other qualities of Rai 1
        let q = b.qualityOptions(for: rai.key)
        h.equal(q.options.map { $0.code }, ["FHD", "HD"])
        h.check(q.sure, "same guide id")
        b.setQuality(prof.id, key: rai.key, code: "HD")
        let preferred = b.withPreferredQuality(rai, profile: b.profiles.get(prof.id))
        h.equal(preferred.key, "\(s.id):l:102")

        // details and TMDB genres
        let d = await b.vodDetails("\(s.id):m:502")
        h.equal(d?.plot ?? "", "Trama")
        h.equal(b.genres.get("\(s.id):m:502") ?? "", "Azione|Avventura")
        let sd = try await b.seriesDetails("\(s.id):s:7")
        h.equal(sd.seasons.map { $0.number }, [1, 2])
        h.equal(sd.seasons.first?.episodes.map { $0.title } ?? [], ["Passato", "Segreti"])
        if let ep = sd.seasons.first?.episodes.first {
            h.equal(b.resolveEpisode(ep, seriesKey: "\(s.id):s:7")?.url ?? "", "\(server.base)/series/u/p/9001.mp4")
        }

        // the guide (gzip XMLTV, matched by id and by name)
        await b.refreshEpg()
        let nn = b.nowNext(keys: ["\(s.id):l:101", "\(s.id):l:104"])
        h.equal(nn["\(s.id):l:101"]?.now?.t ?? "", "Telegiornale")
        h.equal(nn["\(s.id):l:101"]?.next?.t ?? "", "Film della sera")
        h.equal(nn["\(s.id):l:104"]?.now?.t ?? "", "Tg5", "matched by display name")
        h.check(b.liveList(profile: b.profiles.get(prof.id)!).first { $0.key == "\(s.id):l:101" }?.hasEpg ?? false)

        // resume / continue watching
        b.saveResume(prof.id, key: "\(s.id):m:503", pos: 600_000, dur: 6_000_000, parent: nil, label: nil)
        let cw = b.continueWatching(profile: b.profiles.get(prof.id)!)
        h.equal(cw.first?.key ?? "", "\(s.id):m:503")
        h.equal(cw.first.map { Int(($0.fraction ?? 0) * 100) } ?? -1, 10)

        // everything survives a restart
        b.epg.save(); b.genres.save(); b.profiles.flush()
        let b2 = newBackend(dir)
        h.equal(b2.lib.snap.items.count, 49)
        h.equal(b2.lib.sources.count, 1)
        h.equal(b2.profiles.all.count, 1)
        h.equal(b2.profiles.active ?? "", "")
        let p2 = b2.profiles.get(prof.id)!
        h.equal(p2.movies.count, 40)
        h.equal(p2.resume["\(s.id):m:503"] ?? 0, 600_000)
        h.check(b2.epg.channels >= 2, "guide persisted")
        h.equal(b2.genres.get("\(s.id):m:502") ?? "", "Azione|Avventura")

        // deleting the list removes it from the profiles too
        b2.deleteSource(s.id)
        h.equal(b2.lib.snap.items.count, 0)
        h.equal(b2.profiles.get(prof.id)?.live.count ?? -1, 0)
    }

    await h.suite("refresh failures") {
        let b = newBackend()
        let s = b.lib.addSource(xtreamSource(server.base, pass: "wrong"))
        var msg = ""
        do { try await b.refreshSource(s.id) } catch { msg = Net.explain(error) }
        h.equal(msg, "Account disattivato dal fornitore")
        var s2 = Source()
        s2.name = "Rotta"; s2.type = .m3u; s2.url = server.base + "/list404.m3u"
        let bad = b.lib.addSource(s2)
        var err: Error?
        do { try await b.refreshSource(bad.id) } catch { err = error }
        if case NetError.http(let c)? = err { h.equal(c, 404) } else { h.check(false, "expected HTTP 404, got \(String(describing: err))") }
        h.equal(Net.explain(err ?? NetError.http(0)), "Indirizzo non trovato (404). Controlla il link o il server.")
        let missing = server.requestLog.filter { $0.hasPrefix("/list404.m3u") }.count
        h.equal(missing, 1, "a 404 is not retried")
        var s3 = Source()
        s3.name = "Giù"; s3.type = .m3u; s3.url = "http://127.0.0.1:9/none.m3u"
        let down = b.lib.addSource(s3)
        var msg3 = ""
        do { try await b.refreshSource(down.id) } catch { msg3 = Net.explain(error) }
        h.check(msg3.contains("Impossibile connettersi") || msg3.contains("Server non trovato"), msg3)
    }

    await h.suite("m3u over http, plain and gzip") {
        let b = newBackend()
        var s = Source()
        s.name = "M3U"; s.type = .m3u; s.url = server.base + "/list.m3u"
        s = b.lib.addSource(s)
        try await b.refreshSource(s.id)
        h.equal(b.lib.snap.items.count, 2)
        h.equal(b.lib.source(s.id)?.nLive ?? 0, 1)
        let it = b.lib.snap.items.first { $0.kind == .live }!
        let play = await b.resolve(it)
        h.equal(play?.url ?? "", "http://h/live/u/p/1.ts")
        var g = Source()
        g.name = "GZ"; g.type = .m3u; g.url = server.base + "/list.m3u.gz"
        g = b.lib.addSource(g)
        try await b.refreshSource(g.id)
        h.equal(b.lib.snap.items.filter { $0.src == g.id }.map { $0.name }, ["Rai 3 HD"])
        let t = try await b.test(g)
        h.check(t.contains("raggiungibile"), t)
    }
}

private func startPanelServer() throws -> TestServer { try startPanel { Panel() } }
