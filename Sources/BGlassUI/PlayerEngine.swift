import BGlassCore
import Foundation

public enum EngineState: Equatable {
    case idle, loading, buffering, playing, paused, ended
    case failed(String)
}

public struct TrackInfo: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let selected: Bool
    public init(id: Int, name: String, selected: Bool) { self.id = id; self.name = name; self.selected = selected }
}

public struct EngineRequest {
    public var url: URL
    public var userAgent: String
    /// Other request headers the list asks for (Referer, Origin, Cookie).
    public var headers: [String: String]
    public var live: Bool
    public var startAtMs: Int64
    /// How much to read ahead, in seconds (live streams want little, films a lot).
    public var bufferSeconds: Double
    public init(url: URL, userAgent: String, headers: [String: String] = [:], live: Bool, startAtMs: Int64, bufferSeconds: Double) {
        self.url = url; self.userAgent = userAgent; self.headers = headers; self.live = live; self.startAtMs = startAtMs; self.bufferSeconds = bufferSeconds
    }
}

public enum PiPEvent { case started, stopped, restore }

/// A video engine. AVPlayer is built in (HLS and MP4); the app adds VLC when it is linked in, for the containers Apple's player
/// does not read (MKV, AVI, raw MPEG-TS and so on).
@MainActor
public protocol PlayerEngine: AnyObject {
    var identifier: String { get }
    var onState: ((EngineState) -> Void)? { get set }
    var onTracks: (() -> Void)? { get set }
    var onPiP: ((PiPEvent) -> Void)? { get set }

    func makeView() -> PlatformView
    func load(_ r: EngineRequest)
    func play()
    func pause()
    func stop()
    func seek(toMs: Int64)
    var positionMs: Int64 { get }
    var durationMs: Int64 { get }
    var videoSize: CGSize { get }
    func audioTracks() -> [TrackInfo]
    func subtitleTracks() -> [TrackInfo]
    func selectAudio(_ id: Int)
    func selectSubtitle(_ id: Int?)
    func setFill(_ fill: Bool)
    func setRate(_ rate: Float)
    func setMuted(_ muted: Bool)

    var supportsPiP: Bool { get }
    var pipActive: Bool { get }
    func startPiP()
    func stopPiP()
    /// Lets the system keep the picture going when the app is left (when picture in picture is allowed).
    func setAutoPiP(_ on: Bool)
}

/// Where the app registers engines it adds on top of AVPlayer.
@MainActor
public enum Engines {
    /// Creates a VLC engine; set by the app target when VLCKit is linked in.
    public static var makeVLC: (() -> PlayerEngine)?
    public static var vlcAvailable: Bool { makeVLC != nil }

    /// Containers and streams AVPlayer cannot play.
    public static func needsVLC(_ url: URL, live: Bool) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "rmvb", "divx", "vob"].contains(ext) { return true }
        if ["ts", "mts", "m2ts", "flv"].contains(ext) { return true }
        let s = url.absoluteString.lowercased()
        if s.hasPrefix("rtmp") || s.hasPrefix("rtsp") || s.hasPrefix("udp") || s.hasPrefix("rtp") || s.hasPrefix("mms") { return true }
        if live && ext.isEmpty && !s.contains(".m3u8") && !s.contains("m3u8") { return true }
        return false
    }
}
