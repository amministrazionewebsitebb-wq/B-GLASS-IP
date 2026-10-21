import BGlassCore
import Foundation
import SwiftUI

/// What a list is doing while it loads, as the screens show it.
public struct RefreshInfo: Equatable {
    public var text = "Avvio…"
    public var count = 0
    public var percent = -1
    public var running = true
    public var error: String?
    public var partial = false
    public var liveDone = false
    public var moviesDone = false
    public var seriesDone = false
}

public struct ToastMessage: Identifiable, Equatable {
    public enum Style { case info, warning, error }
    public let id = UUID()
    public let text: String
    public let style: Style
}

/// What the player was asked to play.
public enum PlayRequest: Identifiable {
    /// A live channel and the list of channel keys the viewer can zap through.
    case live(key: String, zap: [String])
    /// `resume`: where to start, in milliseconds (0 = from the beginning).
    case movie(key: String, resume: Int64)
    case episode(ep: EpisodeRow, seriesKey: String, all: [EpisodeRow], resume: Int64)

    public var id: String {
        switch self {
        case .live(let k, _): return "live-\(k)"
        case .movie(let k, _): return "movie-\(k)"
        case .episode(let e, _, _, _): return "ep-\(e.rk)"
        }
    }
}

@MainActor
public final class AppModel: ObservableObject {
    public enum Stage { case loading, welcome, profiles, main }

    public let backend: Backend

    @Published public private(set) var stage = Stage.loading
    @Published public private(set) var profile: Profile?
    @Published public private(set) var sources: [Source] = []
    /// Bumps whenever the library or a profile's selection changes: screens rebuild their rows.
    @Published public private(set) var contentRevision = 0
    @Published public private(set) var settingsRevision = 0
    @Published public private(set) var guideRevision = 0
    @Published public private(set) var liveReady = false
    @Published public private(set) var libraryReady = false
    @Published public var refreshes: [Int: RefreshInfo] = [:]
    @Published public var toast: ToastMessage?
    @Published public var playRequest: PlayRequest?
    @Published public var showSettings = false
    /// A profile whose content is being chosen (right after it is created, or from the settings).
    @Published public var setupProfile: Profile?
    @Published public var addingList = false
    @Published public private(set) var guideRefreshing = false

    private var booted = false
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var maintenanceTask: Task<Void, Never>?
    private var epgTask: Task<Void, Never>?
    private var genreFails = 0
    private var genrePauseUntil = Date.distantPast
    private var genreQueue: [String] = []
    private var genreRefillAt = Date.distantPast
    private var genreSavedAt = Date.distantPast
    private var accountAsked = Set<Int>()
    private var startupRefreshDone = false

    public init(dir: URL? = nil) {
        let base = dir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("B-Glass", isDirectory: true)
        backend = Backend(dir: base)
    }

    // MARK: start-up

    /// Reads everything saved on disk, in stages: the lists first (the profile chooser can show), the channels next (a profile can open),
    /// films and series last. Nothing waits for the 100,000 films.
    public func boot() {
        if booted { return }
        booted = true
        let b = backend
        Task.detached(priority: .userInitiated) { [model = self] in
            b.loadAll(onBasics: {
                Task { @MainActor in model.basicsLoaded() }
            }, onLive: {
                Task { @MainActor in model.liveLoaded() }
            })
            await model.fullyLoaded()
        }
    }

    private func basicsLoaded() {
        sources = backend.lib.sources
        decideStage()
    }

    private func liveLoaded() {
        liveReady = true
        contentRevision += 1
    }

    private func fullyLoaded() {
        sources = backend.lib.sources
        libraryReady = true
        liveReady = true
        contentRevision += 1
        if stage == .loading { decideStage() }
        resumeUnfinished()
        startMaintenance()
        maintain()
        if let p = profile { Task.detached { [backend] in _ = backend.syncPacks(p.id) } }
    }

    private func decideStage() {
        if sources.isEmpty { stage = .welcome; return }
        let ps = backend.profiles.all
        if ps.isEmpty { stage = .profiles; return }
        if ps.count == 1, ps[0].pin.isEmpty { chooseProfile(ps[0].id); return }
        if let a = backend.profiles.active, let p = backend.profiles.get(a), p.pin.isEmpty, ps.count == 1 { chooseProfile(p.id); return }
        stage = .profiles
    }

    /// Opens the app on a ready-made profile without reading anything from disk or the network (previews and demos).
    public func enterDemo(_ p: Profile) {
        booted = true
        sources = backend.lib.sources
        profile = backend.profiles.get(p.id)
        liveReady = true
        libraryReady = true
        stage = .main
        contentRevision += 1
    }

    /// Shows one of the entry screens in a preview.
    public func showStage(_ s: Stage) { booted = true; stage = s }

    // MARK: profiles

    public var profiles: [Profile] { backend.profiles.all }

    public func chooseProfile(_ id: String) {
        backend.profiles.setActive(id)
        profile = backend.profiles.get(id)
        stage = .main
        contentRevision += 1
        if let p = profile, p.live.isEmpty && p.movies.isEmpty && p.series.isEmpty { setupProfile = p }
        let pid = id
        Task.detached { [backend] in _ = backend.syncPacks(pid) }
        refreshGuideIfStale(maxAgeHours: 6)
    }

    public func leaveProfile() {
        profile = nil
        stage = sources.isEmpty ? .welcome : .profiles
    }

    @discardableResult
    public func createProfile(name: String, color: Int, pin: String, kids: Bool) -> Profile {
        let p = backend.profiles.create(name: name, color: color, pin: pin, kids: kids)
        objectWillChange.send()
        return p
    }

    public func editProfile(_ id: String, _ body: (inout Profile) -> Void) {
        let p = backend.profiles.update(id, body)
        if profile?.id == id { profile = p }
        objectWillChange.send()
        contentRevision += 1
    }

    public func deleteProfile(_ id: String) {
        backend.profiles.delete(id)
        if profile?.id == id { leaveProfile() }
        objectWillChange.send()
    }

    /// Changes the active profile in place. `light`: positions, favourites and recents only (cheap, no screen rebuilds).
    public func updateProfile(light: Bool = false, _ body: (inout Profile) -> Void) {
        guard let id = profile?.id else { return }
        profile = backend.profiles.update(id, light: light, body)
        if !light { contentRevision += 1 }
    }

    /// Re-reads the active profile after the backend changed it (selection, packs).
    public func reloadProfile() {
        guard let id = profile?.id else { return }
        profile = backend.profiles.get(id)
        contentRevision += 1
    }

    public func toggleFav(_ key: String) {
        guard let id = profile?.id else { return }
        let on = backend.toggleFav(id, key: key)
        profile = backend.profiles.get(id)
        Haptics.tap()
        show(on ? "Aggiunto ai preferiti" : "Tolto dai preferiti")
    }

    public func isFav(_ key: String) -> Bool { profile?.favs.contains(key) ?? false }

    /// Re-reads the active profile after something else changed it (a position saved by the player): no screen rebuilds.
    public func refreshProfileSnapshot() {
        guard let id = profile?.id else { return }
        profile = backend.profiles.get(id)
    }

    /// Writes everything that is still waiting to be written (the app is going to the background).
    public func flush() {
        backend.profiles.flush()
        backend.genres.save()
    }

    // MARK: lists

    public func source(_ id: Int) -> Source? { sources.first { $0.id == id } }

    public func reloadSources() { sources = backend.lib.sources }

    /// Stores a new list and starts loading it.
    @discardableResult
    public func addSource(_ s: Source) -> Source {
        let added = backend.lib.addSource(s)
        backend.lib.save()
        reloadSources()
        refresh(added.id)
        if stage == .welcome { stage = .profiles }
        return added
    }

    public func updateSource(_ s: Source) {
        backend.lib.updateSource(s)
        backend.lib.save()
        reloadSources()
        refresh(s.id)
    }

    public func removeSource(_ id: Int) {
        cancelRefresh(id)
        backend.deleteSource(id)
        backend.clearDetailCaches()
        refreshes[id] = nil
        reloadSources()
        reloadProfile()
        Task.detached { [backend] in _ = backend.syncAllPacks() }
        if sources.isEmpty { stage = .welcome }
    }

    public func cancelRefresh(_ id: Int) {
        backend.cancel(id)
        tasks[id]?.cancel()
    }

    private static func describe(_ phase: String, _ n: Int, _ total: Int) -> String {
        switch phase {
        case "auth": return "Controllo l'account…"
        case "live": return n > 0 ? "Scarico i canali… \(n)" : "Scarico i canali…"
        case "movies": return n > 0 ? "Scarico i film… \(n)" : "Scarico i film…"
        case "series": return n > 0 ? "Scarico le serie… \(n)" : "Scarico le serie…"
        case "m3u": return total > 0 ? "Scarico la lista… \(total)%" : (n > 0 ? "Leggo la lista… \(n) voci" : "Scarico la lista…")
        case "index": return "Indicizzo \(n) titoli…"
        case "save": return "Salvo…"
        default: return "Carico…"
        }
    }

    /// Loads (or reloads) a list in the background. `auto`: started by the app itself, so it stays quiet unless it fails.
    public func refresh(_ id: Int, liveOnly: Bool = false, auto: Bool = false) {
        if tasks[id] != nil { return }
        if !auto { refreshes[id] = RefreshInfo() }                 // a refresh the app starts by itself stays out of sight unless it fails
        let b = backend
        let t = Task { [weak self] in
            var result: Error?
            do {
                try await b.refreshSource(id, liveOnly: liveOnly) { phase, n, total in
                    Task { @MainActor in self?.progress(id, phase, n, total) }
                }
            } catch { result = error }
            self?.refreshFinished(id, error: result, auto: auto, liveOnly: liveOnly)
        }
        tasks[id] = t
    }

    private func progress(_ id: Int, _ phase: String, _ n: Int, _ total: Int) {
        if phase == "part" {
            if var r = refreshes[id] {
                switch Kind(rawValue: total) ?? .live {
                case .live: r.liveDone = true
                case .movie: r.moviesDone = true
                default: r.seriesDone = true
                }
                refreshes[id] = r
            }
            reloadSources()
            contentRevision += 1
            if total == Kind.live.rawValue {
                liveReady = true
                Task.detached { [backend] in _ = backend.syncAllPacks() }
            }
            return
        }
        guard var r = refreshes[id] else { return }
        r.text = AppModel.describe(phase, n, total)
        r.count = n
        if phase == "m3u" { r.percent = total }
        refreshes[id] = r
    }

    private func refreshFinished(_ id: Int, error: Error?, auto: Bool, liveOnly: Bool) {
        tasks[id] = nil
        reloadSources()
        if let e = error {
            var cancelled = false
            if e is CancellationError { cancelled = true }
            if case BackendError.cancelled = e { cancelled = true }
            if cancelled {
                if let s = backend.lib.source(id), s.updated == 0 { removeSource(id) } else { refreshes[id] = nil }
                return
            }
            let why = Net.explain(e)
            if auto && refreshes[id] == nil {
                show("Non riesco ad aggiornare «\(source(id)?.name ?? "la lista")»: \(why)", .warning)
                return
            }
            var r = refreshes[id] ?? RefreshInfo()
            r.running = false
            r.error = why
            refreshes[id] = r
            return
        }
        var r = refreshes[id] ?? RefreshInfo()
        r.running = false
        r.error = nil
        if let s = source(id), !s.status.isEmpty { r.partial = true }
        refreshes[id] = r
        backend.clearDetailCaches()
        liveReady = true
        libraryReady = true
        reloadProfile()
        // new channels in a pack need their guide; otherwise the guide is only downloaded when it is getting old
        let b = backend
        Task { [weak self] in
            let changed = await Task.detached { b.syncAllPacks() }.value
            self?.refreshGuideIfStale(maxAgeHours: changed.isEmpty && liveOnly ? 6 : 2, force: !changed.isEmpty)
        }
        if !auto { Haptics.success() }
        // a finished load does not need to stay on screen
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self?.refreshes[id]?.running == false, self?.refreshes[id]?.error == nil { self?.refreshes[id] = nil }
        }
    }

    /// Right after start-up: lists whose first load was interrupted are loaded again at once.
    private func resumeUnfinished() {
        for s in backend.lib.sources where s.updated == 0 && tasks[s.id] == nil { refresh(s.id, auto: true) }
    }

    // MARK: guide

    /// Downloads the guide only when what we have is older than `maxAgeHours` (it is a big file; mobile data matters).
    public func refreshGuideIfStale(maxAgeHours: Double, force: Bool = false) {
        let age = Double(Int64(Date().timeIntervalSince1970 * 1000) - backend.epg.updated) / 3_600_000
        if force || backend.epg.updated == 0 || age > maxAgeHours { refreshGuide(auto: true) }
    }

    public func refreshGuide(auto: Bool = false) {
        if auto && playRequest != nil { return }
        if epgTask != nil { return }
        guideRefreshing = true
        let b = backend
        epgTask = Task { [weak self] in
            await b.refreshEpg()
            self?.guideFinished()
        }
    }

    private func guideFinished() {
        epgTask = nil
        guideRefreshing = false
        guideRevision += 1
    }

    // MARK: settings

    public func setting(_ k: String, _ def: String = "") -> String { _ = settingsRevision; return backend.settings.get(k, def) }
    public func flag(_ k: String, _ def: Bool = false) -> Bool { _ = settingsRevision; return backend.settings.bool(k, def) }

    public func set(_ k: String, _ v: String) {
        backend.settings.put(k, v)
        settingsRevision += 1
        if k == "packs4k" || k == "showAdult" || k == "tmdbGenres" { contentRevision += 1 }
        if k == "packs4k" { Task.detached { [backend] in _ = backend.syncAllPacks() } }
    }

    public func set(_ k: String, flag v: Bool) { set(k, v ? "1" : "0") }

    // MARK: maintenance

    private func startMaintenance() {
        if maintenanceTask != nil { return }
        maintenanceTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }
                await self.genreStep()
                tick += 1
                if tick % 60 == 0 { await self.maintain() }
            }
        }
    }

    public func stopMaintenance() { maintenanceTask?.cancel(); maintenanceTask = nil }

    /// Called every minute and when the app comes back to the front: keeps the guide, the catalogues and the packs current without the
    /// viewer doing anything. The channel list is reloaded at every start and then every few hours (even while something plays);
    /// the heavy movie/series lists only daily and only when nothing is playing, so video never competes for bandwidth.
    public func maintain() {
        let first = !startupRefreshDone
        startupRefreshDone = true
        let playing = playRequest != nil
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let big = backend.lib.snap.items.count > 150_000
        let full: Int64 = (big ? 72 : 24) * 3600 * 1000
        for s in backend.lib.sources where tasks[s.id] == nil {
            if s.updated == 0 { refresh(s.id, auto: true); continue }
            let age = nowMs - s.updated
            if !playing && age > full { refresh(s.id, auto: true) }
            else if s.type == .xtream && s.wantLive && age > (first ? 10 * 60 * 1000 : 3 * 3600 * 1000) { refresh(s.id, liveOnly: true, auto: true) }
        }
        // M3U links made by an Xtream panel: learn the subscription expiry from the panel once
        for s in backend.lib.sources where s.type == .m3u && s.expTs == 0 && !accountAsked.contains(s.id) {
            guard let behind = Backend.xtreamBehind(s) else { continue }
            accountAsked.insert(s.id)
            Task { [backend, weak self] in
                _ = try? await backend.accountVia(s, api: behind)
                await self?.reloadSources()
            }
        }
        let hours = Int(backend.settings.get("epgEvery", "12")) ?? 12
        if hours > 0, profiles.contains(where: { !$0.live.isEmpty }), nowMs - backend.epg.updated > Int64(hours) * 3600 * 1000 { refreshGuide(auto: true) }
        Task.detached { [backend] in _ = backend.syncAllPacks() }
    }

    /// One film every second or so, never while a video plays or a list is downloading: TMDB genres come with the film details.
    private func genreStep() async {
        guard backend.settings.get("tmdbGenres", "1") == "1", libraryReady else { return }
        let now = Date()
        if now.timeIntervalSince(genreSavedAt) > 60 { genreSavedAt = now; backend.genres.save() }
        if playRequest != nil || !tasks.isEmpty || now < genrePauseUntil { return }
        var key: String?
        while key == nil {
            if genreQueue.isEmpty {
                if now < genreRefillAt { return }
                genreRefillAt = now.addingTimeInterval(20 * 60)
                if let p = profile ?? backend.profiles.all.first { genreQueue = backend.genreCandidates(profile: p) }
                if genreQueue.isEmpty { return }
            }
            let k = genreQueue.removeFirst()
            if backend.genres.get(k) == nil { key = k }
        }
        guard let k = key else { return }
        let ok = await backend.fetchGenres(for: k)
        if ok { genreFails = 0 } else {
            genreFails += 1
            genrePauseUntil = Date().addingTimeInterval(min(600, 30 * Double(genreFails)))      // the provider is slow or unhappy: back off
        }
        if genreQueue.isEmpty { contentRevision += 1 }
    }

    // MARK: playing

    public func play(_ request: PlayRequest) {
        if let p = profile {
            switch request {
            case .live(let k, _), .movie(let k, _): backend.touchRecent(p.id, key: k)
            case .episode(_, let sk, _, _): backend.touchRecent(p.id, key: sk)
            }
            profile = backend.profiles.get(p.id)
        }
        playRequest = request
    }

    /// Plays a "continue watching" card from where the viewer stopped (an episode when the card is a series).
    public func resume(_ card: Card) {
        guard let p = profile else { return }
        if card.kind == .series {
            let mine = p.resumeAt.filter { p.resumeParent[$0.key] == card.key }
            guard let rk = mine.max(by: { $0.value < $1.value })?.key else { return }
            Task { [weak self] in
                guard let self = self, let d = try? await self.backend.seriesDetails(card.key) else { return }
                let all = d.seasons.flatMap { $0.episodes }
                if let ep = all.first(where: { $0.rk == rk }) {
                    self.play(.episode(ep: ep, seriesKey: card.key, all: all, resume: p.resume[rk] ?? 0))
                }
            }
        } else {
            play(.movie(key: card.key, resume: p.resume[card.key] ?? 0))
        }
    }

    public func playLive(_ key: String, among keys: [String]? = nil) {
        play(.live(key: key, zap: keys ?? (profile?.live.array ?? [key])))
    }

    // MARK: messages

    public func show(_ text: String, _ style: ToastMessage.Style = .info) {
        let t = ToastMessage(text: text, style: style)
        toast = t
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}
