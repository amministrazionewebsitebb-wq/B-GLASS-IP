#if canImport(MobileVLCKit)
import BGlassUI
import MobileVLCKit
import UIKit

/// VLC as a second video engine, for the containers and streams AVPlayer does not play.
@MainActor
final class VLCEngine: NSObject, PlayerEngine, VLCMediaPlayerDelegate {
    let identifier = "vlc"
    var onState: ((EngineState) -> Void)?
    var onTracks: (() -> Void)?
    var onPiP: ((PiPEvent) -> Void)?

    private let player = VLCMediaPlayer()
    private let surface = UIView()
    private var startAtMs: Int64 = 0
    private var pendingSeek = false
    private var last = EngineState.idle
    private var fill = false

    override init() {
        super.init()
        surface.backgroundColor = .black
        player.delegate = self
        player.drawable = surface
    }

    deinit { player.delegate = nil }

    func makeView() -> PlatformView { surface }

    func load(_ r: EngineRequest) {
        startAtMs = r.startAtMs
        pendingSeek = r.startAtMs > 0
        let media = VLCMedia(url: r.url)
        media.addOptions([
            "http-user-agent": r.userAgent,
            "network-caching": Int(r.bufferSeconds * 1000),
            "http-reconnect": "1",
        ])
        player.media = media
        set(.loading)
        player.play()
    }

    private func set(_ s: EngineState) {
        if s == last { return }
        last = s
        onState?(s)
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification!) {
        Task { @MainActor in self.stateChanged() }
    }

    private func stateChanged() {
        switch player.state {
        case .opening: set(.loading)
        case .buffering: set(player.isPlaying ? .playing : .buffering)
        case .playing:
            set(.playing)
            if pendingSeek {
                pendingSeek = false
                player.time = VLCTime(int: Int32(truncatingIfNeeded: startAtMs))
            }
            applyFill()
            onTracks?()
        case .paused: set(.paused)
        case .ended: set(.ended)
        case .error: set(.failed("VLC non riesce a riprodurre questo flusso"))
        case .stopped, .esAdded: break
        @unknown default: break
        }
    }

    func play() { player.play() }
    func pause() { player.pause(); set(.paused) }
    func stop() { player.stop(); last = .idle }
    func seek(toMs ms: Int64) { player.time = VLCTime(int: Int32(truncatingIfNeeded: ms)) }

    var positionMs: Int64 { Int64(player.time.intValue) }
    var durationMs: Int64 { Int64(max(0, player.media?.length.intValue ?? 0)) }
    var videoSize: CGSize { player.videoSize }

    private func tracks(_ names: [Any]?, _ indexes: [Any]?, current: Int32) -> [TrackInfo] {
        guard let names = names as? [String], let idx = indexes as? [NSNumber] else { return [] }
        var out: [TrackInfo] = []
        for (n, i) in zip(names, idx) where i.int32Value >= 0 { out.append(TrackInfo(id: Int(i.int32Value), name: n, selected: i.int32Value == current)) }
        return out
    }

    func audioTracks() -> [TrackInfo] { tracks(player.audioTrackNames, player.audioTrackIndexes, current: player.currentAudioTrackIndex) }
    func subtitleTracks() -> [TrackInfo] { tracks(player.videoSubTitlesNames, player.videoSubTitlesIndexes, current: player.currentVideoSubTitleIndex) }
    func selectAudio(_ id: Int) { player.currentAudioTrackIndex = Int32(id); onTracks?() }
    func selectSubtitle(_ id: Int?) { player.currentVideoSubTitleIndex = Int32(id ?? -1); onTracks?() }

    func setFill(_ fill: Bool) { self.fill = fill; applyFill() }

    private func applyFill() {
        let vs = player.videoSize
        guard fill, vs.width > 0, vs.height > 0, surface.bounds.width > 0 else { player.scaleFactor = 0; return }
        player.scaleFactor = Float(max(surface.bounds.width / vs.width, surface.bounds.height / vs.height))
    }

    func setRate(_ rate: Float) { player.rate = rate }
    func setMuted(_ muted: Bool) { player.audio?.isMuted = muted }

    var supportsPiP: Bool { false }
    var pipActive: Bool { false }
    func startPiP() {}
    func stopPiP() {}
    func setAutoPiP(_ on: Bool) {}
}
#endif
