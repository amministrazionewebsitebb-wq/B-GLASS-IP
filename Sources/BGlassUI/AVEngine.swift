import AVFoundation
import BGlassCore
import Foundation
#if canImport(UIKit)
import AVKit
import UIKit
#else
import AppKit
#endif

/// The view that shows the video of an AVPlayer.
#if canImport(UIKit)
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#else
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); playerLayer.frame = bounds }
}
#endif

@MainActor
public final class AVEngine: NSObject, PlayerEngine {
    public let identifier = "av"
    public var onState: ((EngineState) -> Void)?
    public var onTracks: (() -> Void)?
    public var onPiP: ((PiPEvent) -> Void)?

    let player = AVPlayer()
    private let view = PlayerLayerView(frame: .zero)
    private var item: AVPlayerItem?
    private var obs: [NSKeyValueObservation] = []
    private var notes: [NSObjectProtocol] = []
    private var state = EngineState.idle
    private var startAtMs: Int64 = 0
    private var userPaused = false
    private var ended = false
    private var audioGroup: AVMediaSelectionGroup?
    private var subGroup: AVMediaSelectionGroup?
    private var live = false
    private var fill = false
    #if os(iOS)
    private var pip: AVPictureInPictureController?
    private var wantAutoPiP = true
    #endif

    public override init() {
        super.init()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        player.allowsExternalPlayback = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)      // picture in picture needs it
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        configurePiP()
        notes.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            // Without picture in picture the picture stops when the app is left, but the sound goes on (background audio).
            Task { @MainActor [weak self] in
                guard let s = self, !(s.pip?.isPictureInPictureActive ?? false) else { return }
                s.view.playerLayer.player = nil
            }
        })
        notes.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let s = self else { return }
                s.view.playerLayer.player = s.player
            }
        })
        #endif
    }

    deinit {
        for n in notes { NotificationCenter.default.removeObserver(n) }
    }

    public func makeView() -> PlatformView { view }

    // MARK: loading

    public func load(_ r: EngineRequest) {
        teardownItem()
        startAtMs = r.startAtMs
        live = r.live
        userPaused = false
        ended = false
        audioGroup = nil
        subGroup = nil
        let asset = AVURLAsset(url: r.url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": r.userAgent]])
        let it = AVPlayerItem(asset: asset)
        it.preferredForwardBufferDuration = r.bufferSeconds
        it.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        item = it
        set(.loading)
        obs.append(it.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor [weak self] in self?.itemStatus(it) }
        })
        obs.append(it.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        obs.append(it.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        obs.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        notes.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: it, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ended = true
                self?.set(.ended)
            }
        })
        notes.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: it, queue: .main) { [weak self] n in
            let e = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "Riproduzione interrotta"
            Task { @MainActor [weak self] in self?.set(.failed(e)) }
        })
        notes.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: it, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.set(.buffering) }
        })
        player.replaceCurrentItem(with: it)
        player.play()
    }

    private func teardownItem() {
        obs.removeAll()
        // keep the observers of the app-level notifications (the first two); drop the per-item ones
        let keep = 2
        #if os(iOS)
        if notes.count > keep {
            for n in notes[keep...] { NotificationCenter.default.removeObserver(n) }
            notes.removeSubrange(keep...)
        }
        #else
        for n in notes { NotificationCenter.default.removeObserver(n) }
        notes.removeAll()
        #endif
        item = nil
    }

    private func itemStatus(_ it: AVPlayerItem) {
        guard it === item else { return }
        switch it.status {
        case .failed:
            set(.failed(it.error?.localizedDescription ?? "Impossibile aprire il flusso"))
        case .readyToPlay:
            if startAtMs > 0 {
                let t = CMTime(value: startAtMs, timescale: 1000)
                startAtMs = 0
                player.seek(to: t, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
            }
            loadTracks(it)
            refresh()
        default: break
        }
    }

    private func loadTracks(_ it: AVPlayerItem) {
        let asset = it.asset
        Task { @MainActor [weak self] in
            let a = try? await asset.loadMediaSelectionGroup(for: .audible)
            let s = try? await asset.loadMediaSelectionGroup(for: .legible)
            guard let self = self, it === self.item else { return }
            self.audioGroup = a
            self.subGroup = s
            self.onTracks?()
        }
    }

    private func refresh() {
        guard let it = item else { return }
        if it.status == .failed { set(.failed(it.error?.localizedDescription ?? "Impossibile aprire il flusso")); return }
        if ended { return }
        switch player.timeControlStatus {
        case .playing: set(.playing)
        case .waitingToPlayAtSpecifiedRate: set(it.status == .readyToPlay ? .buffering : .loading)
        case .paused: set(userPaused ? .paused : (it.status == .readyToPlay ? .paused : .loading))
        @unknown default: break
        }
    }

    private func set(_ s: EngineState) {
        if s == state { return }
        state = s
        onState?(s)
    }

    // MARK: control

    public func play() { userPaused = false; ended = false; player.play() }
    public func pause() { userPaused = true; player.pause(); set(.paused) }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        teardownItem()
        state = .idle
    }

    public func seek(toMs: Int64) {
        ended = false
        player.seek(to: CMTime(value: toMs, timescale: 1000), toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
    }

    public var positionMs: Int64 {
        let s = CMTimeGetSeconds(player.currentTime())
        return s.isFinite ? Int64(s * 1000) : 0
    }

    public var durationMs: Int64 {
        guard let d = item?.duration else { return 0 }
        let s = CMTimeGetSeconds(d)
        return s.isFinite && s > 0 ? Int64(s * 1000) : 0
    }

    public var videoSize: CGSize { item?.presentationSize ?? .zero }

    public func setFill(_ fill: Bool) {
        self.fill = fill
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    public func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.timeControlStatus != .paused { player.rate = rate }
    }

    public func setMuted(_ muted: Bool) { player.isMuted = muted }

    // MARK: tracks

    private func tracks(_ g: AVMediaSelectionGroup?, allowOff: Bool) -> [TrackInfo] {
        guard let g = g, let it = item else { return [] }
        let cur = it.currentMediaSelection.selectedMediaOption(in: g)
        return g.options.enumerated().map { TrackInfo(id: $0.offset, name: $0.element.displayName, selected: $0.element == cur) }
    }

    public func audioTracks() -> [TrackInfo] { tracks(audioGroup, allowOff: false) }
    public func subtitleTracks() -> [TrackInfo] { tracks(subGroup, allowOff: true) }

    public func selectAudio(_ id: Int) {
        guard let g = audioGroup, let it = item, g.options.indices.contains(id) else { return }
        it.select(g.options[id], in: g)
        onTracks?()
    }

    public func selectSubtitle(_ id: Int?) {
        guard let g = subGroup, let it = item else { return }
        if let id = id, g.options.indices.contains(id) { it.select(g.options[id], in: g) } else { it.select(nil, in: g) }
        onTracks?()
    }

    // MARK: picture in picture

    #if os(iOS)
    public var supportsPiP: Bool { pip != nil }
    public var pipActive: Bool { pip?.isPictureInPictureActive ?? false }
    public func startPiP() { if pip?.isPictureInPicturePossible ?? false { pip?.startPictureInPicture() } }
    public func stopPiP() { pip?.stopPictureInPicture() }

    public func setAutoPiP(_ on: Bool) {
        wantAutoPiP = on
        pip?.canStartPictureInPictureAutomaticallyFromInline = on
    }

    private func configurePiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let c = AVPictureInPictureController(playerLayer: view.playerLayer)
        c?.delegate = self
        c?.canStartPictureInPictureAutomaticallyFromInline = true
        pip = c
    }
    #else
    public var supportsPiP: Bool { false }
    public var pipActive: Bool { false }
    public func startPiP() {}
    public func stopPiP() {}
    public func setAutoPiP(_ on: Bool) {}
    #endif
}

#if os(iOS)
extension AVEngine: AVPictureInPictureControllerDelegate {
    nonisolated public func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.onPiP?(.started) }
    }

    nonisolated public func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.onPiP?(.stopped) }
    }

    nonisolated public func pictureInPictureController(_ c: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done: @escaping (Bool) -> Void) {
        Task { @MainActor in
            self.onPiP?(.restore)
            done(true)
        }
    }
}
#endif
