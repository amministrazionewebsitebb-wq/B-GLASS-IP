import Foundation

/// Flat string settings persisted as JSON.
public final class Settings {
    private let file: URL
    private var map: [String: String] = [:]
    private let lock = NSLock()

    public init(dir: URL) { file = dir.appendingPathComponent("settings.json") }

    public func load() {
        guard let d = try? Data(contentsOf: file), let m = try? JSONDecoder().decode([String: String].self, from: d) else { return }
        lock.lock(); map = m; lock.unlock()
    }

    public func get(_ k: String, _ def: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return map[k] ?? def
    }

    public func bool(_ k: String, _ def: Bool) -> Bool { get(k, def ? "1" : "0") == "1" }

    public var all: [String: String] { lock.lock(); defer { lock.unlock() }; return map }

    public func put(_ k: String, _ v: String) {
        lock.lock()
        map[k] = v
        let snapshot = map
        lock.unlock()
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: file, options: .atomic) }
    }
}

/// The genres of films as TMDB lists them (the provider's film details carry them), kept on disk so each film is asked for once.
/// key -> "Azione|Thriller"; an empty value means "asked, nothing usable".
public final class GenreCache {
    private static let cap = 40000
    private let file: URL
    private var map: [String: String] = [:]
    private var dirty = false
    private let lock = NSLock()

    public init(dir: URL) { file = dir.appendingPathComponent("genres.tsv") }

    public func load() {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        lock.lock(); defer { lock.unlock() }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if map.count >= GenreCache.cap { break }
            if let t = line.firstIndex(of: "\t"), t != line.startIndex {
                map[String(line[line.startIndex..<t])] = String(line[line.index(after: t)...])
            }
        }
    }

    /// nil = never asked.
    public func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return map[key] }

    public func put(_ key: String, _ genres: String?) {
        let v = genres ?? ""
        lock.lock(); defer { lock.unlock() }
        if map.count >= GenreCache.cap && map[key] == nil { return }
        if map.updateValue(v, forKey: key) != v { dirty = true }
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return map.count }

    public func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        var out = ""
        for (k, v) in map { out += k + "\t" + v + "\n" }
        dirty = false
        lock.unlock()
        try? out.write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Profiles on disk: the whole selection in `profiles.json`, and a small `state.json` with what changes while somebody watches
/// (positions, recents, favourites), so it can be saved at any moment without writing the whole selection.
public final class ProfileStore {
    private let file: URL, stateFile: URL
    private var profiles: [Profile] = []
    private var _active: String?
    private let lock = NSLock()
    private let ioLock = NSLock()
    private let ioQueue = DispatchQueue(label: "bglass.profiles.io", qos: .utility)
    private var heavyPending = false

    private struct Disk: Codable {
        var profiles: [Profile] = []
        var active: String?
    }

    private struct Light: Codable {
        var favs: [String]?, recent: [String]?
        var last: String?
        var resume: [String: Int64]?, done: [String: Int64]?, resumeAt: [String: Int64]?
        var resumeParent: [String: String]?, resumeLabel: [String: String]?
        var qpref: [QualityPref]?
    }

    public init(dir: URL) {
        file = dir.appendingPathComponent("profiles.json")
        stateFile = dir.appendingPathComponent("state.json")
    }

    public func load() {
        lock.lock(); defer { lock.unlock() }
        guard let d = try? Data(contentsOf: file), let disk = try? JSONDecoder().decode(Disk.self, from: d) else { return }
        profiles = disk.profiles
        _active = disk.active
        loadLight()
    }

    private func loadLight() {
        guard let d = try? Data(contentsOf: stateFile), let m = try? JSONDecoder().decode([String: Light].self, from: d) else { return }
        if let a = m["__active"]?.last { _active = a }
        for i in profiles.indices {
            guard let l = m[profiles[i].id] else { continue }
            if let v = l.favs { profiles[i].favs = v }
            if let v = l.recent { profiles[i].recent = v }
            profiles[i].last = l.last
            if let v = l.resume { profiles[i].resume = v }
            if let v = l.done { profiles[i].done = v }
            if let v = l.resumeAt { profiles[i].resumeAt = v }
            if let v = l.resumeParent { profiles[i].resumeParent = v }
            if let v = l.resumeLabel { profiles[i].resumeLabel = v }
            if let v = l.qpref { profiles[i].qpref = v }
        }
    }

    /// Saves only positions, recents and favourites (a few KB): safe to call every few seconds while a film plays.
    public func saveLight() {
        lock.lock(); defer { lock.unlock() }
        saveLightLocked()
    }

    private func saveLightLocked() {
        var m: [String: Light] = [:]
        for p in profiles {
            m[p.id] = Light(favs: p.favs, recent: p.recent, last: p.last, resume: p.resume, done: p.done, resumeAt: p.resumeAt,
                            resumeParent: p.resumeParent, resumeLabel: p.resumeLabel, qpref: p.qpref)
        }
        m["__active"] = Light(last: _active)
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: stateFile, options: .atomic) }
    }

    /// The whole selection can be 100,000 keys: it is written a moment after the last change, off the main thread, once for a burst
    /// of changes. `flush()` writes it at once (when the app goes to the background).
    private func markHeavyLocked() {
        if heavyPending { return }
        heavyPending = true
        ioQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    public func flush() {
        lock.lock()
        let snapshot = Disk(profiles: profiles, active: _active)
        heavyPending = false
        lock.unlock()
        ioLock.lock(); defer { ioLock.unlock() }
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: file, options: .atomic) }
    }

    public func save() {
        lock.lock()
        saveLightLocked()
        lock.unlock()
        flush()
    }

    public var all: [Profile] { lock.lock(); defer { lock.unlock() }; return profiles }

    public func get(_ id: String?) -> Profile? {
        guard let id = id else { return nil }
        lock.lock(); defer { lock.unlock() }
        return profiles.first { $0.id == id }
    }

    public var active: String? { lock.lock(); defer { lock.unlock() }; return _active }

    /// Choosing who watches happens at every start: only the small state file is written, not the whole selection.
    public func setActive(_ id: String?) {
        lock.lock(); defer { lock.unlock() }
        if id != nil && id == _active { return }
        _active = id
        saveLightLocked()
    }

    @discardableResult
    public func create(name: String, color: Int, pin: String = "", kids: Bool = false) -> Profile {
        lock.lock(); defer { lock.unlock() }
        var p = Profile()
        p.id = String(UUID().uuidString.prefix(8)).lowercased()
        p.name = name
        p.color = color
        p.pin = pin
        p.kids = kids
        p.created = Profile.nowMillis()
        profiles.append(p)
        markHeavyLocked()
        saveLightLocked()
        return p
    }

    /// Changes one profile in place and saves (`light`: only the small state file).
    @discardableResult
    public func update(_ id: String, light: Bool = false, _ body: (inout Profile) -> Void) -> Profile? {
        lock.lock(); defer { lock.unlock() }
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        body(&profiles[i])
        if !light { markHeavyLocked() }
        saveLightLocked()
        return profiles[i]
    }

    /// Changes every profile (list refreshes remap keys in all of them) and saves once.
    public func updateAll(_ body: (inout Profile) -> Void) {
        lock.lock(); defer { lock.unlock() }
        for i in profiles.indices { body(&profiles[i]) }
        markHeavyLocked()
        saveLightLocked()
    }

    public func delete(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        profiles.removeAll { $0.id == id }
        if _active == id { _active = nil }
        markHeavyLocked()
        saveLightLocked()
    }
}
