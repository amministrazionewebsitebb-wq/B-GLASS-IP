@testable import BGlassCore
import Foundation

func runBasicChecks(_ h: Harness) {
    h.suite("hash") {
        h.check(Hash.isSeparator("---- Vetrina ULTIMI INSERITI recenti: 2025-2026 ----"))
        h.check(Hash.isSeparator("##### SPORT #####"))
        h.check(!Hash.isSeparator("Tenet"))
        h.check(!Hash.isSeparator("Wait Until Dark..."))
        h.check(!Hash.isSeparator("Mr. Robot"))
        h.check(!Hash.isSeparator("9-1-1: Lone Star"))
        h.equal(Hash.norm("RAI 1 HD [IT]"), "rai 1")
        h.equal(Hash.fnv(""), "cbf29ce484222325")
        h.equal(Hash.fold("Caffè"), "caffe")
    }
    h.suite("ordered set") {
        var s = OrderedKeySet(["a", "b", "c"])
        s.insert("b")
        h.equal(s.array, ["a", "b", "c"])
        s.remove("a")
        h.equal(s.array, ["b", "c"])
        h.check(!s.contains("a"))
    }

    h.suite("speed test verdict") {
        var r = SpeedResult()
        r.downMbps = 50
        h.equal(r.grade, .excellent)
        h.equal(r.formats, ["SD", "HD", "Full HD", "4K"])
        r.downMbps = 60
        r.streamMbps = 5                                    // the provider is the bottleneck
        h.equal(r.grade, .poor)
        h.equal(r.formats, ["SD"])
        h.check(r.advice.contains { $0.contains("fornitore") })
        r.streamMbps = nil
        r.downMbps = 2
        h.equal(r.grade, .bad)
        h.check(r.formats.isEmpty)
    }

    h.suite("profile store: a burst of changes is written once and survives a restart") {
        let dir = tempDir("pstore")
        let store = ProfileStore(dir: dir)
        let p = store.create(name: "Prova", color: 1)
        for i in 0..<2000 { store.update(p.id) { $0.movies.insert("1:m:\(i)") } }
        store.update(p.id, light: true) { $0.favs = ["1:l:1"]; $0.saveResume("1:m:5", pos: 70_000, dur: 600_000) }
        store.setActive(p.id)
        store.flush()
        let again = ProfileStore(dir: dir)
        again.load()
        let q = again.get(p.id)
        h.equal(q?.movies.count ?? 0, 2000)
        h.equal(q?.movies.array.first ?? "", "1:m:0")
        h.equal(q?.favs ?? [], ["1:l:1"])
        h.equal(q?.resume["1:m:5"] ?? 0, 70_000)
        h.equal(again.active ?? "", p.id)
        h.equal(q?.name ?? "", "Prova")
    }
}
