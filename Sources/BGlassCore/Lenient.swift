import Foundation

/// Providers are not all alike. Some panels print PHP notices before their JSON, some write names in Latin-1 instead of UTF-8,
/// some answer "null" for an empty catalogue, some hide behind a web page. These helpers read what they send anyway.
public enum Lenient {
    /// True when the bytes are valid UTF-8 (plain ASCII is).
    public static func isUTF8<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
        var it = bytes.makeIterator()
        while let b = it.next() {
            if b < 0x80 { continue }
            let extra: Int
            if b & 0xE0 == 0xC0 { if b < 0xC2 { return false }; extra = 1 }
            else if b & 0xF0 == 0xE0 { extra = 2 }
            else if b & 0xF8 == 0xF0 { if b > 0xF4 { return false }; extra = 3 }
            else { return false }
            for _ in 0..<extra {
                guard let c = it.next(), c & 0xC0 == 0x80 else { return false }
            }
        }
        return true
    }

    /// UTF-8 when it is, otherwise Windows-1252 (the "Latin-1" of old panels and lists): "Caffè" either way.
    public static func text<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        let s = String(decoding: bytes, as: UTF8.self)
        if s.utf8.count == bytes.count { return s }                     // nothing was replaced: it was valid UTF-8
        return String(bytes: Array(bytes), encoding: .windowsCP1252) ?? s
    }

    /// The JSON value of a panel answer, tolerating junk before and after it and Latin-1 text. nil when it is not JSON at all.
    public static func json(_ d: Data) -> Any? {
        if let v = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) { return v }
        guard let start = d.firstIndex(where: { $0 == 0x7B || $0 == 0x5B }),
              let end = d.lastIndex(where: { $0 == 0x7D || $0 == 0x5D }), end > start else { return nil }
        var body = Data(d[start...end])
        if let v = try? JSONSerialization.jsonObject(with: body) { return v }
        if !isUTF8(body), let s = String(data: body, encoding: .windowsCP1252) {
            body = Data(s.utf8)
            if let v = try? JSONSerialization.jsonObject(with: body) { return v }
        }
        return nil
    }

    /// What a server sent instead of the expected data, in words: "una pagina web («Access denied»)".
    public static func describe(_ d: Data) -> String {
        let head = text(d.prefix(4096)).trimmed
        if head.isEmpty { return "una risposta vuota" }
        let low = head.lowercased()
        if low.hasPrefix("<!doctype html") || low.hasPrefix("<html") || low.contains("<body") || low.contains("<head") {
            if low.contains("cloudflare") || low.contains("cf-ray") { return "una pagina di protezione (Cloudflare)" }
            var title = ""
            if let a = low.range(of: "<title>"), let b = low.range(of: "</title>", range: a.upperBound..<low.endIndex) {
                title = String(head[a.upperBound..<b.lowerBound]).trimmed
            }
            return title.isEmpty ? "una pagina web" : "una pagina web («\(title.prefix(80))»)"
        }
        let line = head.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? head
        return "«\(line.prefix(100))»"
    }

    /// True when the payload is clearly a web page, not data.
    public static func isHTML(_ d: Data) -> Bool {
        let low = text(d.prefix(1024)).trimmed.lowercased()
        return low.hasPrefix("<!doctype html") || low.hasPrefix("<html") || (low.hasPrefix("<") && low.contains("<body"))
    }
}

/// A short technical log of what the app asked the servers and what they answered, with passwords masked. People can copy it from
/// the settings and send it when a list or a channel does not work.
public enum Diag {
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static var secrets = Set<String>()
    private static let max = 300
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Values never to show (usernames and passwords of the lists).
    public static func secret(_ values: String...) {
        lock.lock()
        for v in values where v.count >= 3 { secrets.insert(v); secrets.insert(XtreamClient.enc(v)) }
        lock.unlock()
    }

    public static func log(_ text: String) {
        lock.lock()
        var t = text
        for s in secrets { t = t.replacingOccurrences(of: s, with: "•••") }
        t = mask(t)
        lines.append(clock.string(from: Date()) + "  " + t)
        if lines.count > max { lines.removeFirst(lines.count - max) }
        lock.unlock()
    }

    public static var text: String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }

    public static func clear() { lock.lock(); lines.removeAll(); lock.unlock() }

    private static let credParams = try! NSRegularExpression(pattern: "((?:username|password|user|pass|token)=)[^&\\s|]*", options: [.caseInsensitive])

    /// Hides credentials in the query of a URL.
    public static func mask(_ s: String) -> String {
        let ns = s as NSString
        return credParams.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "$1•••")
    }
}
