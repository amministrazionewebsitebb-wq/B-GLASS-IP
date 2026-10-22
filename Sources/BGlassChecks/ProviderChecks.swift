@testable import BGlassCore
import Foundation

// Providers that do things differently: the app has to work with all of them, not only with the one it was first tried on.

private func latin1(_ s: String) -> Data { s.data(using: .windowsCP1252)! }

private final class Box { var emptyLive = false }

func runProviderChecks(_ h: Harness) async {
    h.suite("lenient json and text") {
        let notice = "<br />\n<b>Notice</b>: Undefined index: x in /var/www/api.php on line 3<br />\n{\"user_info\":{\"auth\":1}}"
        h.check((Lenient.json(Data(notice.utf8)) as? [String: Any])?["user_info"] != nil, "PHP notice before the JSON")
        let l1 = Lenient.json(latin1("[{\"category_name\":\"Calcio è\"}]")) as? [[String: Any]]
        h.equal(l1?.first?["category_name"] as? String ?? "", "Calcio è", "Latin-1 JSON")
        h.check(Lenient.json(Data("<html><body>Forbidden</body></html>".utf8)) == nil)
        h.equal(Lenient.text(latin1("Città")), "Città")
        h.equal(Lenient.text(Data("Città".utf8)), "Città")
        h.check(Lenient.describe(Data("<html><head><title>Access denied</title></head></html>".utf8)).contains("Access denied"))
        h.check(Lenient.describe(Data("<html><body>cf-ray</body></html>".utf8)).contains("Cloudflare"))
        h.equal(Diag.mask("http://h/get.php?username=bob&password=secret&type=m3u"), "http://h/get.php?username=•••&password=•••&type=m3u")
    }

    h.suite("flat json from untidy panels") {
        var n = 0
        try FlatJSON.forEachObject(in: Data("<b>Warning</b>: x<br>\n[{\"a\":\"1\"},{\"a\":\"2\"}]".utf8)) { _ in n += 1 }
        h.equal(n, 2, "notice before the array")
        n = 0
        try FlatJSON.forEachObject(in: Data("null".utf8)) { _ in n += 1 }
        try FlatJSON.forEachObject(in: Data("".utf8)) { _ in n += 1 }
        try FlatJSON.forEachObject(in: Data(" false ".utf8)) { _ in n += 1 }
        h.equal(n, 0, "null, nothing and false are empty catalogues")
        var name = ""
        try FlatJSON.forEachObject(in: latin1("[{\"name\":\"Città TV\"}]")) { name = $0["name"] ?? "" }
        h.equal(name, "Città TV", "Latin-1 names")
    }

    await h.suite("m3u lists written in other ways") {
        let text = """
        #EXTM3U url-tvg="http://epg.example/a.xml,http://epg.example/b.xml"
        #EXTVLCOPT:http-user-agent=SpecialUA
        #EXTINF:-1 tvg-id='rai1' tvg-logo='http://logo/r1.png' group-title='Generali, Italia',Rai 1
        http://cdn.example/rai1.m3u8|User-Agent=KodiUA&Referer=http%3A%2F%2Fsite.example%2F
        #EXTINF:-1 group-title="Città",Canale Città
        #EXTVLCOPT:http-referrer=http://ref.example/
        http://cdn.example/citta.m3u8
        qualcosa che non è un indirizzo
        #EXTINF:-1 group-title="Film",Heat (1995)
        http://cdn.example/movie/heat.mkv|User-Agent=X
        """
        var items: [Item] = []
        let meta = try M3UParser.parse(data: latin1(text), srcId: 1) { items.append($0) }
        h.equal(meta.epgUrl ?? "", "http://epg.example/a.xml", "first of several guides")
        h.equal(items.count, 3, "the stray line is not a channel")
        let rai = items.first { $0.name == "Rai 1" }
        h.equal(rai?.cat ?? "", "Generali, Italia", "single quotes with a comma inside")
        h.equal(rai?.logo ?? "", "http://logo/r1.png")
        h.equal(rai?.epgId ?? "", "rai1")
        h.equal(rai?.kind, .live)
        let citta = items.first { $0.cat == "Città" }
        h.equal(citta?.name ?? "", "Canale Città", "Latin-1 list")
        h.equal(items.first { $0.kind == .movie }?.name ?? "", "Heat (1995)", "a film even with headers after the address")
        h.equal(M3UParser.address("http://a/b.m3u8|User-Agent=x"), "http://a/b.m3u8")
        h.equal(M3UParser.headers("http://a/b|user-agent=Foo%20Bar&referrer=http://r/&X-Other=1"), ["User-Agent": "Foo Bar", "Referer": "http://r/", "X-Other": "1"])

        let b = Backend(dir: tempDir("hdr"))
        b.loadAll()
        var s = Source(); s.type = .m3u; s.url = "http://x/list.m3u"; s.name = "L"
        s = b.lib.addSource(s)
        for it in items { it.src = s.id }
        b.lib.replaceSource(s.id, items)
        let pr = await b.resolve(b.lib.snap.items.first { $0.name == "Rai 1" }!)
        h.equal(pr?.url ?? "", "http://cdn.example/rai1.m3u8", "the address without the headers")
        h.equal(pr?.ua ?? "", "KodiUA")
        h.equal(pr?.headers["Referer"] ?? "", "http://site.example/")
        let pc = await b.resolve(b.lib.snap.items.first { $0.name == "Canale Città" }!)
        h.equal(pc?.url ?? "", "http://cdn.example/citta.m3u8")
        h.equal(pc?.headers["Referer"] ?? "", "http://ref.example/", "#EXTVLCOPT referrer")
        h.equal(XMLTV.parseTime("20260101190000+0100"), 1767290400, "offset without a space")
        h.equal(XMLTV.parseTime("20260101190000 +01:00"), 1767290400, "offset with a colon")
    }

    // a panel that only lets in the apps it knows, prints PHP notices and writes Latin-1
    let box = Box()
    guard let picky = try? TestServer(withHeaders: { path, q, hd in
        if hd["user-agent"] != "IPTVSmartersPlayer" {
            return TestServer.Response("<html><head><title>Access denied</title></head><body>no</body></html>", status: 403)
        }
        guard path == "/player_api.php" else { return TestServer.Response("x", status: 404) }
        if q["password"] != "p" { return TestServer.Response("{\"user_info\":{\"auth\":0}}") }
        switch q["action"] ?? "" {
        case "": return TestServer.Response("<br />\n<b>Notice</b>: Undefined index<br />\n{\"user_info\":{\"auth\":1,\"status\":\"Active\",\"exp_date\":null,\"allowed_output_formats\":[]},\"server_info\":{}}")
        case "get_live_categories": return TestServer.Response(latin1("[{\"category_id\":1,\"category_name\":\"Calcio è\"}]"))
        case "get_live_streams":
            if box.emptyLive { return TestServer.Response("[]") }
            return TestServer.Response(latin1("[{\"stream_id\":1,\"name\":\"Città TV\",\"category_id\":1},{\"stream_id\":2,\"name\":\"Rai 1\",\"category_id\":\"1\"}]"))
        case "get_vod_categories", "get_vod_streams": return TestServer.Response("null")
        default: return TestServer.Response("[]")
        }
    }) else { h.check(false, "could not start the picky panel"); return }
    defer { picky.stop() }

    await h.suite("panel that wants another User-Agent") {
        let b = Backend(dir: tempDir("picky"))
        b.loadAll()
        var s = Source(); s.type = .xtream; s.name = "Picky"; s.url = picky.base; s.user = "u"; s.pass = "p"
        let c = try await b.check(s)
        h.equal(c.source.ua, "IPTVSmartersPlayer", "found the User-Agent the panel accepts")
        h.check(c.summary.contains("IPTVSmartersPlayer"), c.summary)
        s = b.lib.addSource(s)
        try await b.refreshSource(s.id)
        let st = b.lib.source(s.id)!
        h.equal(st.ua, "IPTVSmartersPlayer", "remembered on the list")
        h.equal(st.nLive, 2)
        h.equal(st.nMovies, 0, "\"null\" is an empty catalogue, not an error")
        h.equal(st.status, "")
        let city = b.lib.snap.items.first { $0.sid == "1" }
        h.equal(city?.name ?? "", "Città TV")
        h.equal(city?.cat ?? "", "Calcio è")
        if let city = city {
            let play = await b.resolve(city)
            h.equal(play?.url ?? "", "\(picky.base)/live/u/p/1.ts", "no HLS declared: MPEG-TS first")
            h.equal(play?.alt ?? "", "\(picky.base)/live/u/p/1.m3u8", "and HLS as the second try")
            h.equal(play?.ua ?? "", "IPTVSmartersPlayer", "the player asks the same way")
        }

        // the panel has a bad moment and sends an empty channel list: the channels stay
        box.emptyLive = true
        var hiccup = ""
        do { try await b.refreshSource(s.id, liveOnly: true) } catch { hiccup = Net.explain(error) }
        h.equal(hiccup, "Il server ha mandato un elenco vuoto", "said, not hidden")
        h.equal(b.lib.source(s.id)?.nLive ?? 0, 2, "an empty answer does not wipe the channels")
        h.equal(b.lib.snap.items.filter { $0.kind == .live }.count, 2)
        box.emptyLive = false

        var wrong = s; wrong.pass = "nope"; wrong.ua = ""
        let before = picky.requestLog.count
        var msg = ""
        do { _ = try await b.check(wrong) } catch { msg = Net.explain(error) }
        h.equal(msg, "Utente o password non validi")
        h.check(picky.requestLog.count - before <= 2, "a clear no stops the search (\(picky.requestLog.count - before) requests)")
    }

    await h.suite("panel on another port than the one typed") {
        guard let closed = try? TestServer(handler: { _, _ in TestServer.Response("") }) else { return }
        let deadPort = closed.port
        closed.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)
        var s = Source(); s.type = .xtream; s.url = "http://127.0.0.1:\(deadPort)"; s.user = "u"; s.pass = "p"
        let f = try await XtreamClient.discover(s, ports: [Int(picky.port)])
        h.check(f.account.ok)
        h.equal(f.source.url, picky.base)
        h.check(f.note.contains("risponde su"), f.note)
    }

    guard let expired = try? TestServer(handler: { _, _ in
        TestServer.Response("{\"user_info\":{\"auth\":1,\"status\":\"Expired\",\"exp_date\":\"1600000000\"}}")
    }) else { return }
    defer { expired.stop() }
    await h.suite("expired account") {
        var s = Source(); s.type = .xtream; s.url = expired.base; s.user = "u"; s.pass = "p"
        var msg = ""
        do { _ = try await Backend(dir: tempDir("exp")).check(s) } catch { msg = Net.explain(error) }
        h.check(msg.hasPrefix("Abbonamento scaduto"), msg)
    }

    // list hosts: one that only serves browsers, one that answers with a web page, one link that is a single channel
    let m3u = "#EXTM3U\n#EXTINF:-1 group-title=\"News\",Tg 24\nhttp://cdn.example/tg24.m3u8\n"
    guard let host = try? TestServer(withHeaders: { path, _, hd in
        switch path {
        case "/browser.m3u":
            return (hd["user-agent"] ?? "").hasPrefix("Mozilla") ? TestServer.Response(m3u) : TestServer.Response("denied", status: 403)
        case "/page.m3u": return TestServer.Response("<!DOCTYPE html><html><head><title>Pagina scaduta</title></head><body></body></html>")
        case "/one.m3u8": return TestServer.Response("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nlow/index.m3u8\n")
        default: return TestServer.Response("no", status: 404)
        }
    }) else { return }
    defer { host.stop() }

    await h.suite("list hosts that are particular") {
        let b = Backend(dir: tempDir("hosts"))
        b.loadAll()
        var s = Source(); s.type = .m3u; s.name = "Browser"; s.url = host.base + "/browser.m3u"
        s = b.lib.addSource(s)
        try await b.refreshSource(s.id)
        h.equal(b.lib.source(s.id)?.nLive ?? 0, 1)
        h.check((b.lib.source(s.id)?.ua ?? "").hasPrefix("Mozilla"), "the User-Agent that worked is kept")

        var p = Source(); p.type = .m3u; p.name = "Pagina"; p.url = host.base + "/page.m3u"
        var msg = ""
        do { _ = try await b.check(p) } catch { msg = Net.explain(error) }
        h.check(msg.contains("pagina web") && msg.contains("Pagina scaduta"), msg)

        var one = Source(); one.type = .m3u; one.name = "Il mio canale"; one.url = host.base + "/one.m3u8"
        one = b.lib.addSource(one)
        try await b.refreshSource(one.id)
        let ch = b.lib.snap.items.filter { $0.src == one.id }
        h.equal(ch.map { $0.name }, ["Il mio canale"], "a single stream link becomes one channel")
        h.equal(ch.first?.url ?? "", host.base + "/one.m3u8")
    }
}
