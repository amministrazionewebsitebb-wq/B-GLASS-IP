@testable import BGlassCore
import Foundation

func tempDir(_ name: String = "bg") -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("bglass-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func live(_ src: Int, _ sid: String, _ name: String, _ cat: String, epg: String? = "") -> Item {
    let it = Item(src: src, kind: .live, key: "\(src):l:\(sid)", name: name, cat: cat)
    it.sid = sid
    it.epgId = epg
    return it
}

/// A library with one Xtream source holding the given live channels (name, category).
func libraryWith(_ chans: [(String, String)]) -> (lib: Library, src: Int) {
    let lib = Library(dir: tempDir("lib"))
    var s = Source()
    s.name = "T"; s.type = .xtream; s.url = "http://x"; s.user = "u"; s.pass = "p"
    s = lib.addSource(s)
    let items = chans.enumerated().map { live(s.id, String($0.offset + 1), $0.element.0, $0.element.1) }
    lib.replaceSource(s.id, items)
    return (lib, s.id)
}

func parseM3U(_ text: String, src: Int = 1) throws -> (items: [Item], meta: M3UParser.Meta) {
    var items: [Item] = []
    let meta = try M3UParser.parse(data: Data(text.utf8), srcId: src) { items.append($0) }
    return (items, meta)
}
