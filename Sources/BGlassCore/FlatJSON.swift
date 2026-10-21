import Foundation

/// Streams the objects of a big JSON array without building a tree (provider catalogues can be tens of MB).
/// Each object is handed over as a flat string map: strings, numbers and booleans are kept as text, null and
/// nested values are skipped. Some panels wrap the array in an object ({"0":{..},"1":{..}}); that works too.
public enum FlatJSON {
    public struct Malformed: Error, LocalizedError {
        public var errorDescription: String? { "Risposta non valida dal server" }
    }

    /// `keys`: when given, only these keys are materialised (the rest of each object is skipped cheaply).
    public static func forEachObject(in data: Data, keys: Set<String>? = nil, _ body: ([String: String]) throws -> Void) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var p = Parser(buf: raw.bindMemory(to: UInt8.self), keys: keys)
            try p.run(body)
        }
    }

    private struct Parser {
        let buf: UnsafeBufferPointer<UInt8>
        let keys: Set<String>?
        var i = 0
        var n: Int { buf.count }

        init(buf: UnsafeBufferPointer<UInt8>, keys: Set<String>?) { self.buf = buf; self.keys = keys }

        mutating func ws() { while i < n, buf[i] == 32 || buf[i] == 10 || buf[i] == 13 || buf[i] == 9 { i += 1 } }

        mutating func run(_ body: ([String: String]) throws -> Void) throws {
            if n >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF { i = 3 }
            ws()
            guard i < n else { throw Malformed() }
            if buf[i] == 91 {                                              // '['
                i += 1
                ws()
                if i < n, buf[i] == 93 { return }
                while true {
                    ws()
                    guard i < n else { throw Malformed() }
                    if buf[i] == 123 { try body(try object()) } else { try skipValue() }
                    ws()
                    guard i < n else { throw Malformed() }
                    if buf[i] == 44 { i += 1; continue }
                    if buf[i] == 93 { return }
                    throw Malformed()
                }
            } else if buf[i] == 123 {                                      // '{' wrapper
                i += 1
                ws()
                if i < n, buf[i] == 125 { return }
                while true {
                    ws()
                    _ = try string()
                    ws()
                    guard i < n, buf[i] == 58 else { throw Malformed() }
                    i += 1
                    ws()
                    guard i < n else { throw Malformed() }
                    if buf[i] == 123 { try body(try object()) } else { try skipValue() }
                    ws()
                    guard i < n else { throw Malformed() }
                    if buf[i] == 44 { i += 1; continue }
                    if buf[i] == 125 { return }
                    throw Malformed()
                }
            }
            // anything else (for instance an error page): nothing to stream
            throw Malformed()
        }

        mutating func object() throws -> [String: String] {
            var f: [String: String] = Dictionary(minimumCapacity: 16)
            i += 1                                                         // '{'
            ws()
            if i < n, buf[i] == 125 { i += 1; return f }
            while true {
                ws()
                let k = try string()
                ws()
                guard i < n, buf[i] == 58 else { throw Malformed() }
                i += 1
                ws()
                guard i < n else { throw Malformed() }
                let want = keys == nil || keys!.contains(k)
                let c = buf[i]
                if c == 34 {
                    if want { f[k] = try string() } else { try skipString() }
                } else if c == 123 || c == 91 {
                    try skipValue()
                } else {
                    let s = i
                    while i < n, buf[i] != 44, buf[i] != 125, buf[i] != 93, buf[i] > 32 { i += 1 }
                    if want {
                        let tok = String(decoding: UnsafeBufferPointer(rebasing: buf[s..<i]), as: UTF8.self)
                        if tok != "null" { f[k] = tok }
                    }
                }
                ws()
                guard i < n else { throw Malformed() }
                if buf[i] == 44 { i += 1; continue }
                if buf[i] == 125 { i += 1; return f }
                throw Malformed()
            }
        }

        mutating func skipString() throws {
            guard i < n, buf[i] == 34 else { throw Malformed() }
            i += 1
            while i < n {
                let c = buf[i]
                if c == 92 { i += 2; continue }
                if c == 34 { i += 1; return }
                i += 1
            }
            throw Malformed()
        }

        mutating func skipValue() throws {
            guard i < n else { throw Malformed() }
            let c = buf[i]
            if c == 34 { try skipString(); return }
            if c == 123 || c == 91 {
                var depth = 0
                while i < n {
                    let d = buf[i]
                    if d == 34 { try skipString(); continue }
                    if d == 123 || d == 91 { depth += 1 }
                    else if d == 125 || d == 93 { depth -= 1; if depth == 0 { i += 1; return } }
                    i += 1
                }
                throw Malformed()
            }
            while i < n, buf[i] != 44, buf[i] != 125, buf[i] != 93, buf[i] > 32 { i += 1 }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= n else { throw Malformed() }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = buf[i]
                i += 1
                v <<= 4
                switch c {
                case 48...57: v |= UInt32(c - 48)
                case 97...102: v |= UInt32(c - 87)
                case 65...70: v |= UInt32(c - 55)
                default: throw Malformed()
                }
            }
            return v
        }

        mutating func string() throws -> String {
            guard i < n, buf[i] == 34 else { throw Malformed() }
            i += 1
            let s = i
            var escaped = false
            while i < n {
                let c = buf[i]
                if c == 92 { escaped = true; i += 2; continue }
                if c == 34 { break }
                i += 1
            }
            guard i < n else { throw Malformed() }
            if !escaped {
                let str = String(decoding: UnsafeBufferPointer(rebasing: buf[s..<i]), as: UTF8.self)
                i += 1
                return str
            }
            // slow path: unescape
            var out = [UInt8]()
            out.reserveCapacity(i - s)
            var j = s
            let end = i
            i = s
            while i < end {
                let c = buf[i]
                if c != 92 { out.append(c); i += 1; continue }
                i += 1
                guard i < end else { throw Malformed() }
                let e = buf[i]
                i += 1
                switch e {
                case 110: out.append(10)
                case 116: out.append(9)
                case 114: out.append(13)
                case 98: out.append(8)
                case 102: out.append(12)
                case 117:
                    var cp = try hex4()
                    if cp >= 0xD800 && cp < 0xDC00, i + 6 <= end, buf[i] == 92, buf[i + 1] == 117 {
                        let save = i
                        i += 2
                        let lo = try hex4()
                        if lo >= 0xDC00 && lo < 0xE000 { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00) } else { i = save }
                    }
                    let sc = Unicode.Scalar(cp) ?? "\u{FFFD}"
                    out.append(contentsOf: Array(String(sc).utf8))
                default: out.append(e)
                }
            }
            j = end
            i = j + 1
            return String(decoding: out, as: UTF8.self)
        }
    }
}
