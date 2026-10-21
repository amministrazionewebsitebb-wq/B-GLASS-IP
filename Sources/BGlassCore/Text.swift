import Foundation

/// Character classes the way the matching code needs them (letters and decimal digits, any script).
@inline(__always)
func isLetterOrDigit(_ u: Unicode.Scalar) -> Bool {
    let v = u.value
    if v < 128 { return (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) }
    switch u.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: return true
    default: return false
    }
}

@inline(__always)
func isDigitScalar(_ u: Unicode.Scalar) -> Bool {
    let v = u.value
    if v < 128 { return v >= 48 && v <= 57 }
    return u.properties.generalCategory == .decimalNumber
}

@inline(__always)
func lowerScalar(_ u: Unicode.Scalar) -> String {
    if u.value < 128 {
        let v = u.value
        return v >= 65 && v <= 90 ? String(Unicode.Scalar(v + 32)!) : String(u)
    }
    return u.properties.lowercaseMapping
}

extension String {
    /// True when the whole string is made of ASCII digits (and, optionally, '+').
    public func allDigits(allowPlus: Bool = false) -> Bool {
        if isEmpty { return false }
        for u in unicodeScalars {
            if u.value >= 48 && u.value <= 57 { continue }
            if allowPlus && u == "+" { continue }
            return false
        }
        return true
    }

    /// Java-style trim: anything up to and including the space character goes.
    public var trimmed: String {
        let s = unicodeScalars
        var a = s.startIndex, b = s.endIndex
        while a < b, s[a].value <= 32 { a = s.index(after: a) }
        while b > a, s[s.index(before: b)].value <= 32 { b = s.index(before: b) }
        return String(s[a..<b])
    }
}

/// Tiny helpers for stable keys and name matching.
public enum Hash {
    /// 64-bit FNV-1a over the UTF-16 units of the string, as lower-case hex (stable across runs and platforms).
    public static func fnv(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for c in s.utf16 {
            h ^= UInt64(c)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }

    private static let separatorChars: Set<UInt16> = Set("-=#*_~+|:.\u{2022}\u{2500}\u{2501}\u{25AC}".utf16)

    /// "----Italia----", "#### SPORT ####": decorative list headers that are not channels.
    public static func isSeparator(_ name: String?) -> Bool {
        guard let name = name else { return false }
        let t = Array(name.trimmed.utf16)
        let n = t.count
        if n < 5 { return false }
        var a = 0, b = 0
        while a < n && separatorChars.contains(t[a]) { a += 1 }
        while b < n && separatorChars.contains(t[n - 1 - b]) { b += 1 }
        return (a >= 3 && b >= 3) || a == n
    }

    private static let noiseWords: Set<String> = ["fhd", "uhd", "hd", "sd", "4k", "hevc", "h265", "h264", "1080", "1080p", "720", "720p", "50fps", "ita", "it"]

    /// Lowercase, drop [..] / (..) groups, quality tags and punctuation: "RAI 1 HD [IT]" -> "rai 1".
    public static func norm(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "" }
        var out = ""
        var w = ""
        var depth = 0
        func flush() {
            if !w.isEmpty {
                if !noiseWords.contains(w) {
                    if !out.isEmpty { out.append(" ") }
                    out.append(w)
                }
                w = ""
            }
        }
        for u in s.unicodeScalars {
            var c = u
            if c == "[" || c == "(" { depth += 1; c = " " }
            else if c == "]" || c == ")" { if depth > 0 { depth -= 1 }; c = " " }
            else if depth > 0 { c = " " }
            if isLetterOrDigit(c) { w.append(lowerScalar(c)); continue }
            flush()
        }
        flush()
        return out
    }

    /// Lower case without accents: "Caffè" and "caffe" find each other.
    public static func fold(_ s: String?) -> String {
        guard let s = s else { return "" }
        var ascii = true
        for b in s.utf8 where b > 127 { ascii = false; break }
        if ascii { return s.lowercased() }
        let d = s.decomposedStringWithCanonicalMapping
        var out = ""
        for u in d.unicodeScalars where u.properties.generalCategory != .nonspacingMark { out.append(lowerScalar(u)) }
        return out
    }
}

/// Bounded string interner: shares repeated values (categories, URL prefixes) without growing forever.
public final class StrPool {
    private var m: [String: String] = [:]
    private let cap: Int
    public init(_ cap: Int) { self.cap = cap }

    public func get(_ s: String?) -> String? {
        guard let s = s else { return nil }
        return get(s) as String
    }

    public func get(_ s: String) -> String {
        if let p = m[s] { return p }
        if m.count < cap { m[s] = s }
        return s
    }
}
