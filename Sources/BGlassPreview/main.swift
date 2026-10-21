// Renders the app's screens to PNG files on a Mac (no Xcode, no simulator), with made-up data.
// Usage: preview <output-dir> [scene ...]
@testable import BGlassCore
@testable import BGlassUI
import AppKit
import SwiftUI

struct Scene {
    let name: String
    var wait = 1.6
    let make: @MainActor (AppModel) -> AnyView
}

@MainActor
func nav<V: View>(_ v: V) -> AnyView { AnyView(NavigationStack { v.navigationDestination(for: Card.self) { DetailView(card: $0) } }) }

@MainActor
func scenes(_ app: AppModel) -> [Scene] {
    let snap = app.backend.lib.snap
    let movie = snap.items.first { $0.kind == .movie }!
    let series = snap.items.first { $0.kind == .series }!
    let mCard = app.backend.card(movie, app.profile)
    let sCard = app.backend.card(series, app.profile)
    let channel = snap.items.first { $0.kind == .live }!
    return [
        Scene(name: "welcome") { _ in AnyView(WelcomeView()) },
        Scene(name: "profiles") { a in a.showStage(.profiles); return AnyView(ProfilePickerView()) },
        Scene(name: "home", wait: 2.5) { _ in nav(HomeView(go: { _ in })) },
        Scene(name: "live", wait: 2.0) { _ in nav(LiveView()) },
        Scene(name: "guide", wait: 2.5) { _ in nav(LiveView(guide: true)) },
        Scene(name: "movies", wait: 2.5) { _ in nav(VODBrowserView(kind: .movie)) },
        Scene(name: "series", wait: 2.5) { _ in nav(VODBrowserView(kind: .series)) },
        Scene(name: "detail_movie", wait: 2.0) { _ in nav(DetailView(card: mCard)) },
        Scene(name: "detail_series", wait: 2.5) { _ in nav(DetailView(card: sCard)) },
        Scene(name: "search") { _ in nav(SearchView()) },
        Scene(name: "settings", wait: 2.0) { _ in AnyView(SettingsView()) },
        Scene(name: "setup", wait: 2.0) { a in AnyView(SetupFlowView(profileId: a.profile!.id)) },
        Scene(name: "packs", wait: 2.0) { a in nav(PacksView(profileId: a.profile!.id)) },
        Scene(name: "addlist") { _ in AnyView(AddListView()) },
        Scene(name: "pin") { _ in AnyView(PinEntry(title: "PIN di Ospiti", onDone: { _ in false }, onCancel: {})) },
        Scene(name: "network", wait: 2.0) { _ in nav(NetworkView()) },
        Scene(name: "player", wait: 3.0) { a in AnyView(PlayerView(app: a, request: .live(key: channel.key, zap: a.profile!.live.array))) },
        Scene(name: "episode_player", wait: 3.0) { a in
            let ep = EpisodeRow(rk: "r", xtreamId: nil, m3uIndex: 0, title: "Episodio 3", plot: "", image: nil, duration: "", ext: "", number: 3, season: 1, src: 1)
            return AnyView(PlayerView(app: a, request: .episode(ep: ep, seriesKey: series.key, all: [ep], resume: 600_000)))
        },
    ]
}

@MainActor
func snapshot(_ view: AnyView, app: AppModel, size: NSSize, wait: Double, to url: URL) async {
    let root = ZStack { GlassBackground(); view }
        .environmentObject(app)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
        .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(origin: .zero, size: size)
    let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: 60, y: 60), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("no bitmap for \(url.lastPathComponent)"); return }
    host.cacheDisplay(in: host.bounds, to: rep)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
        print("wrote \(url.lastPathComponent)")
    }
    win.orderOut(nil)
}

@main
struct Preview {
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        let args = Array(CommandLine.arguments.dropFirst())
        guard let out = args.first else { print("usage: preview <output-dir> [scene ...]"); return }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bglass-preview-\(UUID().uuidString)")
        let only = Set(args.dropFirst())
        for sc in scenes(DemoData.model(dir: tmp.appendingPathComponent("probe"))) where only.isEmpty || only.contains(sc.name) {
            // a fresh model per scene so that one screen's state never leaks into the next
            let app = DemoData.model(dir: tmp.appendingPathComponent(sc.name))
            let fresh = scenes(app).first { $0.name == sc.name }!
            await snapshot(fresh.make(app), app: app, size: NSSize(width: 390, height: 844), wait: sc.wait, to: dir.appendingPathComponent("\(sc.name).png"))
        }
        exit(0)
    }
}
