import AVFoundation
import BGlassCore
import Foundation
import SwiftUI
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if os(iOS)
import UIKit
#endif

/// Everything the player screen needs: it owns the engine, reconnects when a channel drops, remembers where a film stopped,
/// zaps between channels, plays the next episode, answers the lock screen controls.
@MainActor
public final class PlayerModel: ObservableObject {
    public enum Phase: Equatable { case loading, buffering, playing, paused, ended, failed(String) }

    public struct Banner: Equatable { var number: Int; var name: String; var logo: String? }

    unowned let app: AppModel
    let request: PlayRequest

    @Published public private(set) var phase = Phase.loading
    @Published public private(set) var title = ""
    @Published public private(set) var subtitle = ""
    @Published public private(set) var logo: String?
    @Published public private(set) var isLive = false
    @Published public private(set) var positionMs: Int64 = 0
    @Published public private(set) var durationMs: Int64 = 0
    @Published public private(set) var now: Prog?
    @Published public private(set) var next: Prog?
    @Published public private(set) var currentKey = ""
    @Published public private(set) var zapBanner: Banner?
    @Published public var controlsVisible = true
    @Published public private(set) var fill = false
    @Published public private(set) var rate: Float = 1
    @Published public private(set) var audio: [TrackInfo] = []
    @Published public private(set) var subs: [TrackInfo] = []
    @Published public private(set) var qualities: [QualityOption] = []
    @Published public private(set) var qualityCurrent = ""
    @Published public private(set) var notice: String?
    @Published public private(set) var pipActive = false
    @Published public private(set) var engineEpoch = 0
    @Published public private(set) var sleepLeft: TimeInterval?
    @Published public private(set) var upNext: EpisodeRow?
    @Published public private(set) var upNextIn: Int = 0
    @Published public private(set) var resolution = ""
    @Published public var scrubbing = false
    /// The channels the viewer can move between (the list the channel was chosen from).
    @Published public private(set) var channels: [LiveChannel] = []
    @Published public private(set) var isFav = false
    @Published public private(set) var episode: EpisodeRow?

    public private(set) var engine: PlayerEngine
    private var engineId = "av"
    private var zapKeys: [String] = []
    private var play: Play?
    private var usedAlt = false
    private var attempts = 0
    private var generation = 0
    private var playingSince: Date?
    private var stallSince: Date?
    private var forceVLC = false
    private var tickTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var zapTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var upNextTask: Task<Void, Never>?
    private var guideTask: Task<Void, Never>?
    private var startAt: Int64 = 0
    private var resumeFloor: Int64 = 0
    private var lastSave = Date.distantPast
    public private(set) var episodes: [EpisodeRow] = []
    private var seriesKey: String?
    private var vodKey: String?
    private var closed = false
    private var interruption: NSObjectProtocol?
    /// The channel as the viewer chose it (the one in their list); the entry that actually plays can be another quality of it.
    private var baseKey = ""
    private var playingKey = ""
    private var langApplied = false
    private var lastTickPos: Int64 = -1
    private var frozenSince: Date?

    public init(app: AppModel, request: PlayRequest) {
        self.app = app
        self.request = request
        engine = AVEngine()
        attach(engine)
        fill = app.setting("aspect", "fit") == "fill"
    }

    // MARK: start / stop

    public func start() {
        configureSession()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        engine.setFill(fill)
        engine.setAutoPiP(app.flag("autoPiP", true))
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.tick()
            }
        }
        configureRemote()
        OrientationLock.allowRotation(true)
        switch request {
        case .live(let key, let zap):
            zapKeys = zap.isEmpty ? [key] : zap
            if !zapKeys.contains(key) { zapKeys.insert(key, at: 0) }
            channels = app.backend.channelRows(zapKeys, profile: app.profile ?? Profile())
            startLive(key)
        case .movie(let key, let resume):
            OrientationLock.request(landscape: true)              // films start full screen, like on a TV
            startMovie(key, resume: resume)
        case .episode(let ep, let sk, let all, let resume):
            OrientationLock.request(landscape: true)
            seriesKey = sk
            episodes = all
            startEpisode(ep, resume: resume)
        }
        scheduleHide()
    }

    public func close() {
        if closed { return }
        closed = true
        saveResume(force: true)
        for t in [tickTask, hideTask, retryTask, zapTask, sleepTask, upNextTask, guideTask] { t?.cancel() }
        engine.stop()
        OrientationLock.allowRotation(false)
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        removeRemote()
        if let i = interruption { NotificationCenter.default.removeObserver(i) }
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
        app.playRequest = nil
    }

    private func attach(_ e: PlayerEngine) {
        e.onState = { [weak self] s in self?.engineState(s) }
        e.onTracks = { [weak self] in self?.refreshTracks() }
        e.onPiP = { [weak self] ev in self?.pipEvent(ev) }
    }

    private func configureSession() {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback)
        try? s.setActive(true)
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            Task { @MainActor [weak self] in
                if type == .began { self?.engine.pause() }
                else if type == .ended, opts?.contains(.shouldResume) ?? false { self?.engine.play() }
            }
        }
        #endif
    }

    // MARK: engines

    private func chooseEngine(for url: URL, live: Bool) {
        let pref = app.setting("engine", "auto")
        var vlc = false
        if Engines.vlcAvailable {
            if pref == "vlc" || forceVLC { vlc = true }
            else if pref == "auto" && Engines.needsVLC(url, live: live) { vlc = true }
        }
        let want = vlc ? "vlc" : "av"
        if want == engineId { return }
        engine.stop()
        engine = vlc ? (Engines.makeVLC?() ?? AVEngine()) : AVEngine()
        engineId = engine.identifier
        attach(engine)
        engine.setFill(fill)
        engine.setAutoPiP(app.flag("autoPiP", true))
        engineEpoch += 1
    }

    public var engineName: String { engineId == "vlc" ? "VLC" : "AVPlayer" }
    public var canSwitchEngine: Bool { Engines.vlcAvailable }

    public func switchEngine() {
        guard Engines.vlcAvailable, let p = play else { return }
        forceVLC = engineId == "av"
        if engineId == "vlc" { forceVLC = false }
        attempts = 0
        load(p, at: isLive ? 0 : positionMs)
    }

    private func load(_ p: Play, url override: String? = nil, at startMs: Int64) {
        guard let url = URL(string: override ?? p.url) ?? URL(string: (override ?? p.url).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            phase = .failed("Indirizzo non valido")
            return
        }
        chooseEngine(for: url, live: isLive)
        let buf = app.setting("buffer", "normal")
        let seconds: Double
        switch (isLive, buf) {
        case (true, "min"): seconds = 3
        case (true, "high"): seconds = 30
        case (true, _): seconds = 10
        case (false, "min"): seconds = 15
        case (false, "high"): seconds = 90
        default: seconds = 40
        }
        phase = .loading
        stallSince = nil
        frozenSince = nil
        lastTickPos = -1
        langApplied = false
        engine.load(EngineRequest(url: url, userAgent: p.ua.isEmpty ? Net.defaultUA : p.ua, live: isLive, startAtMs: startMs, bufferSeconds: seconds))
        refreshTracks()
    }

    // MARK: live

    private func startLive(_ key: String, exact: Bool = false, base: String? = nil) {
        guard let it = app.backend.item(key) else { phase = .failed("Canale non trovato"); return }
        isLive = true
        baseKey = base ?? key
        currentKey = baseKey
        if base == nil { forceVLC = false }                       // a new channel gets the preferred engine again
        generation += 1
        let gen = generation
        retryTask?.cancel()
        attempts = 0
        usedAlt = false
        notice = nil
        let shown = app.backend.item(baseKey) ?? it
        title = app.backend.channelName(baseKey)
        isFav = app.isFav(baseKey)
        let idx = (zapKeys.firstIndex(of: baseKey) ?? 0) + 1
        subtitle = "Canale \(idx)"
        logo = shown.logo
        now = nil
        next = nil
        positionMs = 0
        durationMs = 0
        phase = .loading
        Task { [weak self] in
            guard let self = self else { return }
            let chosen = exact ? it : self.app.backend.withPreferredQuality(it, profile: self.app.profile)
            guard let p = await self.app.backend.resolve(chosen) else {
                if gen == self.generation { self.phase = .failed("Impossibile ricavare l'indirizzo del canale") }
                return
            }
            if gen != self.generation { return }
            self.play = p
            self.playingKey = chosen.key
            self.load(p, at: 0)
            self.updateQualities(chosen)
            self.refreshGuide()
            self.updateNowPlaying()
            Task.detached { [backend = self.app.backend] in backend.warmVariants() }
        }
    }

    private func updateQualities(_ it: Item) {
        let q = app.backend.qualityOptions(for: it.key)
        qualities = q.options
        qualityCurrent = q.options.isEmpty ? "" : Variants.label(q.current)
    }

    public func chooseQuality(_ option: QualityOption) {
        guard isLive, let pid = app.profile?.id else { return }
        app.backend.setQuality(pid, key: option.key, code: option.code)
        startLive(option.key, exact: true, base: baseKey)
        notice = "Qualità: \(option.label)"
        clearNoticeSoon()
    }

    /// Moves to the next / previous channel. The name changes at once; fast repeated presses only start the last channel.
    public func zap(_ dir: Int) {
        guard isLive, zapKeys.count > 1 else { return }
        let i = zapKeys.firstIndex(of: pendingZapKey ?? baseKey) ?? zapKeys.firstIndex(of: baseKey) ?? 0
        let n = ((i + dir) % zapKeys.count + zapKeys.count) % zapKeys.count
        pendingZapKey = zapKeys[n]
        showBanner(for: zapKeys[n], number: n + 1)
        zapTask?.cancel()
        zapTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self = self, let k = self.pendingZapKey else { return }
            self.pendingZapKey = nil
            self.startLive(k)
        }
        Haptics.tap()
    }

    private var pendingZapKey: String?

    public func playChannel(_ key: String) {
        pendingZapKey = nil
        zapTask?.cancel()
        if key == baseKey { return }
        showBanner(for: key, number: (zapKeys.firstIndex(of: key) ?? 0) + 1)
        startLive(key)
    }

    private func showBanner(for key: String, number: Int) {
        guard let it = app.backend.item(key) else { return }
        let nm = app.backend.channelName(key)
        zapBanner = Banner(number: number, name: nm, logo: it.logo)
        title = nm
        subtitle = "Canale \(number)"
        logo = it.logo
        let b = zapBanner
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self?.zapBanner == b { self?.zapBanner = nil }
        }
    }

    public func toggleFav() {
        guard isLive else { return }
        app.toggleFav(baseKey)
        isFav = app.isFav(baseKey)
        channels = app.backend.channelRows(zapKeys, profile: app.profile ?? Profile())
    }

    private func refreshGuide() {
        guideTask?.cancel()
        let key = currentKey
        guideTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                let nn = self.app.backend.nowNext(keys: [key])[key]
                self.now = nn?.now
                self.next = nn?.next
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    // MARK: films and episodes

    private func startMovie(_ key: String, resume: Int64) {
        guard let it = app.backend.item(key) else { phase = .failed("Titolo non trovato"); return }
        isLive = false
        forceVLC = false
        vodKey = key
        currentKey = key
        title = Backend.cleanTitle(it.name)
        subtitle = it.extra ?? ""
        logo = it.logo
        startAt = resume
        resumeFloor = resume
        generation += 1
        let gen = generation
        Task { [weak self] in
            guard let self = self else { return }
            guard let p = await self.app.backend.resolve(it) else { self.phase = .failed("Impossibile ricavare l'indirizzo del film"); return }
            if gen != self.generation { return }
            self.play = p
            self.load(p, at: resume)
            self.updateNowPlaying()
        }
    }

    private func startEpisode(_ ep: EpisodeRow, resume: Int64) {
        guard let sk = seriesKey else { return }
        isLive = false
        forceVLC = false
        episode = ep
        vodKey = ep.rk
        currentKey = ep.rk
        let show = app.backend.item(sk)
        title = Backend.cleanTitle(show?.name ?? "")
        subtitle = "S\(ep.season) E\(ep.number) · \(ep.title)"
        logo = ep.image ?? show?.logo
        startAt = resume
        resumeFloor = resume
        upNext = nil
        upNextTask?.cancel()
        generation += 1
        let gen = generation
        Task { [weak self] in
            guard let self = self else { return }
            guard let p = self.app.backend.resolveEpisode(ep, seriesKey: sk) else { self.phase = .failed("Episodio non trovato"); return }
            if gen != self.generation { return }
            self.play = p
            self.load(p, at: resume)
            self.updateNowPlaying()
        }
    }

    private var nextEpisodeRow: EpisodeRow? {
        guard let e = episode, let i = episodes.firstIndex(where: { $0.rk == e.rk }), i + 1 < episodes.count else { return nil }
        return episodes[i + 1]
    }

    public var hasNextEpisode: Bool { nextEpisodeRow != nil }

    /// The episodes of the season being watched, for the list under the picture.
    public var seasonEpisodes: [EpisodeRow] {
        guard let e = episode else { return [] }
        return episodes.filter { $0.season == e.season }
    }

    public func playEpisode(_ ep: EpisodeRow) {
        guard ep.rk != episode?.rk else { return }
        saveResume(force: true)
        upNextTask?.cancel()
        upNext = nil
        startEpisode(ep, resume: app.profile?.resume[ep.rk] ?? 0)
    }

    public func playNextEpisode() {
        guard let n = nextEpisodeRow else { return }
        saveResume(force: true)
        if let pid = app.profile?.id, let done = episode { app.backend.clearResume(pid, key: done.rk) }
        upNextTask?.cancel()
        startEpisode(n, resume: app.profile?.resume[n.rk] ?? 0)
    }

    public func cancelUpNext() { upNextTask?.cancel(); upNext = nil }

    private func saveResume(force: Bool) {
        guard !isLive, let pid = app.profile?.id, let key = vodKey else { return }
        if !force && Date().timeIntervalSince(lastSave) < 10 { return }
        let pos = engine.positionMs, dur = engine.durationMs
        if pos <= 0 { return }
        if resumeFloor > 0 && pos <= resumeFloor + 1500 { return }               // not past where this viewing began: keep the older, further position
        lastSave = Date()
        let label = episode.map { "S\($0.season) E\($0.number) · \($0.title)" }
        app.backend.saveResume(pid, key: key, pos: pos, dur: dur, parent: seriesKey, label: label)
        app.refreshProfileSnapshot()
    }

    // MARK: engine events

    private func engineState(_ s: EngineState) {
        switch s {
        case .idle: break
        case .loading: phase = .loading
        case .buffering:
            phase = .buffering
            if stallSince == nil { stallSince = Date() }
        case .playing:
            phase = .playing
            stallSince = nil
            if playingSince == nil { playingSince = Date() }
            notice = nil
            refreshTracks()
            updateNowPlaying()
            let vs = engine.videoSize
            if vs.height > 0 { resolution = "\(Int(vs.width))×\(Int(vs.height))" }
        case .paused:
            phase = .paused
            playingSince = nil
            showControls()
        case .ended: playbackEnded()
        case .failed(let msg): failed(msg)
        }
    }

    private func playbackEnded() {
        if isLive { failed("Il flusso è terminato"); return }
        saveResume(force: true)
        if let n = nextEpisodeRow {
            phase = .ended
            upNext = n
            upNextIn = 8
            upNextTask?.cancel()
            upNextTask = Task { [weak self] in
                while let s = self, s.upNextIn > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                    s.upNextIn -= 1
                }
                self?.playNextEpisode()
            }
        } else {
            if let pid = app.profile?.id, let k = vodKey { app.backend.clearResume(pid, key: k); app.refreshProfileSnapshot() }
            close()
        }
    }

    private func failed(_ msg: String) {
        guard let p = play else { phase = .failed(msg); return }
        attempts += 1
        playingSince = nil
        if isLive {
            // the same entry again, sooner at first; after repeated failures the other live format; VLC for what AVPlayer cannot read
            if engineId == "av" && Engines.vlcAvailable && (attempts == 1 || Engines.needsVLC(URL(string: p.url) ?? URL(fileURLWithPath: "/"), live: true)) { forceVLC = true }
            if attempts > 6 { phase = .failed(msg); notice = nil; return }
            let url = URL(string: p.url)
            let cannotPlay = !Engines.vlcAvailable && (url.map { Engines.needsVLC($0, live: true) } ?? false)          // AVPlayer cannot read this stream at all
            if (attempts >= 3 || cannotPlay), !usedAlt, let alt = p.alt {
                usedAlt = true
                notice = "Provo l'altro formato del canale…"
                reload(after: 0.8, url: alt)
                return
            }
            notice = "Riconnessione… (\(attempts))"
            reload(after: min(6, Double(attempts) * 1.5), url: nil)
        } else {
            if attempts > 3 { phase = .failed(msg); notice = nil; return }
            if engineId == "av" && Engines.vlcAvailable { forceVLC = true }
            notice = "Riprovo da dove eri arrivato…"
            reload(after: Double(attempts), url: nil)
        }
    }

    private func reload(after seconds: Double, url: String?) {
        retryTask?.cancel()
        let resume = isLive ? 0 : max(positionMs, startAt)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self = self, let p = self.play else { return }
            self.load(p, url: url, at: resume)
        }
    }

    public func retry() {
        attempts = 0
        usedAlt = false
        guard let p = play else { return }
        notice = nil
        load(p, at: isLive ? 0 : max(positionMs, startAt))
    }

    private func tick() {
        guard !closed else { return }
        let pos = engine.positionMs
        if !scrubbing && pos != positionMs { positionMs = pos }
        // The clock of the picture is the truth: some engines (VLC above all) keep saying "buffering" while the video runs.
        let moving = lastTickPos >= 0 && pos > lastTickPos && pos - lastTickPos < 3000
        if moving {
            frozenSince = nil
            if phase == .buffering || phase == .loading {
                phase = .playing
                stallSince = nil
                if playingSince == nil { playingSince = Date() }
                notice = nil
            }
        } else if isLive, phase == .playing, pos > 0, pos == lastTickPos {
            // a live picture whose clock stopped without the engine noticing: the stream dropped
            if frozenSince == nil { frozenSince = Date() }
            if let f = frozenSince, Date().timeIntervalSince(f) > 20 { frozenSince = nil; failed("Il flusso si è fermato") }
        }
        lastTickPos = pos
        let dur = engine.durationMs
        if dur != durationMs { durationMs = dur }
        if phase == .playing { saveResume(force: false); updateNowPlayingTime() }
        // a stream that stays on "buffering" is as good as dead: start the reconnect path
        if let s = stallSince, phase == .buffering {
            let limit: TimeInterval = isLive ? 15 : 45
            if Date().timeIntervalSince(s) > limit {
                stallSince = nil
                failed("Il flusso non risponde")
            }
        }
        // a connection that held for a while earns a fresh start for the retry counter
        if let ps = playingSince, Date().timeIntervalSince(ps) > 12 { attempts = 0; usedAlt = false }
    }

    // MARK: controls

    public func showControls() {
        controlsVisible = true
        scheduleHide()
    }

    public func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self = self, self.phase == .playing, !self.scrubbing else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.controlsVisible = false }
        }
    }

    public func togglePlay() {
        if phase == .playing || phase == .buffering { engine.pause() } else { engine.play() }
        showControls()
    }

    public func seek(by seconds: Double) {
        guard !isLive else { return }
        let target = max(0, min(positionMs + Int64(seconds * 1000), durationMs > 0 ? durationMs - 500 : Int64.max))
        engine.seek(toMs: target)
        positionMs = target
        resumeFloor = 0
        showControls()
    }

    public func seek(toMs: Int64) {
        guard !isLive else { return }
        engine.seek(toMs: toMs)
        positionMs = toMs
        resumeFloor = 0
        scrubbing = false
        showControls()
    }

    public func toggleFill() {
        fill.toggle()
        engine.setFill(fill)
        notice = fill ? "Schermo intero" : "Adatta allo schermo"
        clearNoticeSoon()
    }

    public func setRate(_ r: Float) { rate = r; engine.setRate(r) }
    public func selectAudio(_ id: Int) { engine.selectAudio(id) }
    public func selectSubtitle(_ id: Int?) { engine.selectSubtitle(id) }

    private func refreshTracks() {
        audio = engine.audioTracks()
        subs = engine.subtitleTracks()
        applyLanguagePreference()
    }

    /// Picks the audio and subtitle language the viewer asked for in the preferences, once per stream, when the stream offers it.
    private func applyLanguagePreference() {
        if langApplied || (audio.isEmpty && subs.isEmpty) { return }
        langApplied = true
        func match(_ tracks: [TrackInfo], _ lang: String) -> TrackInfo? {
            let names: [String: [String]] = ["ita": ["ital"], "eng": ["engl", "ingl"], "spa": ["spa", "espa"], "fra": ["fran"], "deu": ["deut", "germ", "tedesc"]]
            let keys = names[lang] ?? [lang]
            return tracks.first { t in keys.contains { t.name.lowercased().contains($0) } }
        }
        let al = app.setting("audioLang", "ita")
        if al != "auto", let t = match(audio, al), !t.selected { engine.selectAudio(t.id) }
        let sl = app.setting("subLang", "off")
        if sl != "off", let t = match(subs, sl) { engine.selectSubtitle(t.id) }
    }

    // MARK: picture in picture

    public var supportsPiP: Bool { engine.supportsPiP }

    public func togglePiP() {
        if engine.pipActive { engine.stopPiP() } else { engine.startPiP() }
    }

    private func pipEvent(_ e: PiPEvent) {
        switch e {
        case .started: pipActive = true
        case .stopped: pipActive = false
        case .restore: pipActive = false
        }
    }

    // MARK: sleep timer

    public func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepLeft = nil
        guard let m = minutes else { return }
        let end = Date().addingTimeInterval(Double(m) * 60)
        sleepLeft = Double(m) * 60
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }
                let left = end.timeIntervalSinceNow
                if left <= 0 { self.close(); return }
                self.sleepLeft = left
            }
        }
    }

    private func clearNoticeSoon() {
        let n = notice
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self?.notice == n { self?.notice = nil }
        }
    }

    // MARK: lock screen

    private func updateNowPlaying() {
        #if canImport(MediaPlayer)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: isLive ? (now?.t ?? "In diretta") : subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: phase == .playing ? Double(rate) : 0.0,
        ]
        if !isLive {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let l = logo, !l.isEmpty {
            Task {
                guard let img = await ImageLoader.shared.image(for: l, maxPixel: 600) else { return }
                #if os(iOS)
                let art = MPMediaItemArtwork(boundsSize: CGSize(width: img.width, height: img.height)) { _ in UIImage(cgImage: img) }
                var cur = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                cur[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = cur
                #endif
            }
        }
        #endif
    }

    private func updateNowPlayingTime() {
        #if canImport(MediaPlayer)
        guard !isLive, var cur = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        cur[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000
        cur[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000
        MPNowPlayingInfoCenter.default().nowPlayingInfo = cur
        #endif
    }

    private var remoteTokens: [(MPRemoteCommand, Any)] = []

    private func configureRemote() {
        #if canImport(MediaPlayer) && os(iOS)
        let c = MPRemoteCommandCenter.shared()
        func add(_ cmd: MPRemoteCommand, _ h: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            cmd.isEnabled = true
            remoteTokens.append((cmd, cmd.addTarget(handler: h)))
        }
        add(c.playCommand) { [weak self] _ in Task { @MainActor in self?.engine.play() }; return .success }
        add(c.pauseCommand) { [weak self] _ in Task { @MainActor in self?.engine.pause() }; return .success }
        add(c.togglePlayPauseCommand) { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        add(c.nextTrackCommand) { [weak self] _ in Task { @MainActor in self?.zap(1) }; return .success }
        add(c.previousTrackCommand) { [weak self] _ in Task { @MainActor in self?.zap(-1) }; return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        add(c.skipForwardCommand) { [weak self] _ in Task { @MainActor in self?.seek(by: 10) }; return .success }
        add(c.skipBackwardCommand) { [weak self] _ in Task { @MainActor in self?.seek(by: -10) }; return .success }
        add(c.changePlaybackPositionCommand) { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.seek(toMs: Int64(e.positionTime * 1000)) } }
            return .success
        }
        #endif
    }

    private func removeRemote() {
        #if canImport(MediaPlayer) && os(iOS)
        for (cmd, token) in remoteTokens { cmd.removeTarget(token) }
        remoteTokens.removeAll()
        #endif
    }
}
