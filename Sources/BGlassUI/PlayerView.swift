import BGlassCore
import SwiftUI
#if os(iOS)
import AVKit
import UIKit
#endif

/// Hosts the video of whichever engine is playing.
struct VideoSurface: PlatformViewRepresentable {
    let engine: PlayerEngine

    #if canImport(UIKit)
    func makeUIView(context: Context) -> UIView { engine.makeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
    #else
    func makeNSView(context: Context) -> NSView { engine.makeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    #endif
}

/// The system AirPlay picker.
struct AirPlayButton: View {
    var body: some View {
        #if os(iOS)
        RoutePicker().frame(width: 38, height: 38)
        #else
        Image(systemName: "airplayvideo").frame(width: 38, height: 38)
        #endif
    }
}

#if os(iOS)
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.cyan)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

private enum PlayerSheet: String, Identifiable {
    case channels, options
    var id: String { rawValue }
}

public struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @State private var sheet: PlayerSheet?

    public init(app: AppModel, request: PlayRequest) {
        _model = StateObject(wrappedValue: PlayerModel(app: app, request: request))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(engine: model.engine).id(model.engineEpoch).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2).onEnded { v in doubleTap(at: v.location) }
                        .exclusively(before: TapGesture().onEnded { withAnimation(.easeOut(duration: 0.2)) { model.toggleControls() } })
                )
                .simultaneousGesture(DragGesture(minimumDistance: 28).onEnded { v in
                    if model.isLive, abs(v.translation.height) > 90, abs(v.translation.width) < 90 { model.zap(v.translation.height < 0 ? 1 : -1) }
                })
                .simultaneousGesture(MagnificationGesture().onEnded { s in
                    if (s > 1.15 && !model.fill) || (s < 0.87 && model.fill) { model.toggleFill() }
                })
            overlays
            if model.controlsVisible { controls.transition(.opacity) }
        }
        .preferredColorScheme(.dark)
        .hideStatusBar(!model.controlsVisible)
        .onAppear { model.start() }
        .onDisappear { model.close() }
        .sheet(item: $sheet) { s in
            switch s {
            case .channels: ChannelListSheet(model: model) { sheet = nil }
            case .options: PlayerOptionsSheet(model: model) { sheet = nil }
            }
        }
    }

    private func doubleTap(at p: CGPoint) {
        guard !model.isLive else { return }
        #if os(iOS)
        let w = UIScreen.main.bounds.width
        #else
        let w: CGFloat = 400
        #endif
        model.seek(by: p.x < w / 2 ? -10 : 10)
    }

    // MARK: overlays

    @ViewBuilder private var overlays: some View {
        if (model.phase == .loading || model.phase == .buffering) && !model.controlsVisible {
            ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.5)
        }
        if let b = model.zapBanner {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    RemoteImage(b.logo, title: b.name, maxPixel: 160, contentMode: .fit)
                        .frame(width: 54, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(b.number)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.cyan)
                        Text(b.name).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: 360)
                .glass(radius: 18, strong: true)
                .padding(.bottom, model.controlsVisible ? 150 : 60)
            }
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        VStack {
            if let n = model.notice {
                Text(n).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8).glass(radius: 20, strong: true)
                    .padding(.top, 60).transition(.opacity)
            }
            Spacer()
        }
        if case .failed(let msg) = model.phase { errorCard(msg) }
        if let n = model.upNext { upNextCard(n) }
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(Theme.gold)
            Text(model.isLive ? "Il canale non si apre" : "Non riesco a riprodurre il video").font(.system(size: 18, weight: .bold))
            Text(msg).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).lineLimit(4)
            HStack(spacing: 10) {
                Button("Riprova") { model.retry() }.buttonStyle(GlassButtonStyle(prominent: true))
                if model.canSwitchEngine { Button("Prova con \(model.engineName == "VLC" ? "AVPlayer" : "VLC")") { model.switchEngine() }.buttonStyle(GlassButtonStyle()) }
                Button("Chiudi") { model.close() }.buttonStyle(GlassButtonStyle())
            }
        }
        .padding(22)
        .frame(maxWidth: 380)
        .glass(radius: 24, strong: true)
        .padding(20)
    }

    private func upNextCard(_ e: EpisodeRow) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prossimo episodio · tra \(model.upNextIn) s").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cyan)
                    Text("S\(e.season) E\(e.number) · \(e.title)").font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    HStack {
                        Button("Riproduci ora") { model.playNextEpisode() }.buttonStyle(GlassButtonStyle(prominent: true))
                        Button("Annulla") { model.cancelUpNext(); model.close() }.buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(16)
                .frame(maxWidth: 340)
                .glass(radius: 20, strong: true)
            }
            .padding(20)
        }
    }

    // MARK: controls

    private var controls: some View {
        ZStack {
            VStack {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                topBar
                Spacer()
                centerBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func roundButton(_ system: String, size: CGFloat = 20, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action(); model.showControls() } label: {
            Image(systemName: system).font(.system(size: size, weight: .semibold)).foregroundStyle(.white).frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            roundButton("chevron.down", size: 22) { model.close() }
            if model.isLive, model.logo != nil {
                RemoteImage(model.logo, title: model.title, maxPixel: 120, contentMode: .fit)
                    .frame(width: 44, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                if !model.subtitle.isEmpty { Text(model.subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if model.supportsPiP { roundButton(model.pipActive ? "pip.exit" : "pip.enter") { model.togglePiP() } }
            AirPlayButton()
            roundButton("ellipsis.circle") { sheet = .options }
        }
    }

    private var centerBar: some View {
        HStack(spacing: 44) {
            if model.isLive {
                roundButton("backward.fill", size: 26) { model.zap(-1) }
            } else {
                roundButton("gobackward.10", size: 30) { model.seek(by: -10) }
            }
            Button { Haptics.tap(); model.togglePlay() } label: {
                Group {
                    if model.phase == .loading || model.phase == .buffering {
                        ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.3)
                    } else {
                        Image(systemName: model.phase == .playing ? "pause.fill" : "play.fill").font(.system(size: 34, weight: .bold))
                    }
                }
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            if model.isLive {
                roundButton("forward.fill", size: 26) { model.zap(1) }
            } else {
                roundButton("goforward.10", size: 30) { model.seek(by: 10) }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if model.isLive { liveInfo } else { scrubber }
            HStack(spacing: 8) {
                if model.isLive {
                    pill("list.bullet", "Canali") { sheet = .channels }
                    if !model.qualities.isEmpty { pill("sparkles.tv", model.qualityCurrent) { sheet = .options } }
                }
                if !model.audio.isEmpty || !model.subs.isEmpty { pill("captions.bubble", "Audio e sub") { sheet = .options } }
                pill(model.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", model.fill ? "Adatta" : "Riempi") { model.toggleFill() }
                if !model.isLive, model.hasNextEpisode { pill("forward.end.fill", "Prossimo") { model.playNextEpisode() } }
                Spacer(minLength: 0)
                if !model.resolution.isEmpty { Text(model.resolution).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.tertiaryText) }
            }
        }
    }

    private func pill(_ icon: String, _ text: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action(); model.showControls() } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass(radius: 16)
        }
        .buttonStyle(.plain)
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { Double(model.positionMs) }, set: { model.seek(toMs: Int64($0)) }),
                   in: 0...Double(max(model.durationMs, 1)),
                   onEditingChanged: { editing in model.scrubbing = editing; if editing { model.showControls() } })
                .tint(Theme.cyan)
                .disabled(model.durationMs <= 0)
            HStack {
                Text(TimeText.duration(model.positionMs)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                Spacer()
                Text("-" + TimeText.duration(max(0, model.durationMs - model.positionMs))).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var liveInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("LIVE").font(.system(size: 11, weight: .heavy)).padding(.horizontal, 7).padding(.vertical, 3).background(Theme.live, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                if let n = model.now {
                    Text(n.t).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(TimeText.clock(n.s))–\(TimeText.clock(n.e))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                } else {
                    Text("In diretta").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
            }
            if let n = model.now, n.e > n.s {
                let frac = min(1, max(0, Double(Int64(Date().timeIntervalSince1970) - n.s) / Double(n.e - n.s)))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(Theme.cyan).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 3)
            }
            if let x = model.next {
                Text("Poi · \(TimeText.clock(x.s))  \(x.t)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
    }
}

// MARK: sheets

struct ChannelListSheet: View {
    @ObservedObject var model: PlayerModel
    var close: () -> Void
    @State private var rows: [LiveChannel] = []
    @State private var guide: [String: (now: Prog?, next: Prog?)] = [:]

    var body: some View {
        NavigationStack {
            List(rows) { c in
                Button {
                    model.playChannel(c.key)
                    close()
                } label: {
                    HStack(spacing: 12) {
                        Text("\(c.num)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.secondaryText).frame(width: 30, alignment: .trailing)
                        RemoteImage(c.logo, title: c.name, maxPixel: 120, contentMode: .fit)
                            .frame(width: 48, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            if let n = guide[c.key]?.now { Text(n.t).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                        }
                        Spacer()
                        if c.key == model.currentKey { Image(systemName: "play.circle.fill").foregroundStyle(Theme.cyan) }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.white.opacity(c.key == model.currentKey ? 0.10 : 0.03))
            }
            .groupedList()
            .background(GlassBackground())
            .navigationTitle("Canali")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine", action: close) } }
        }
        .presentationDetents([.medium, .large])
        .task {
            rows = model.zapList
            guide = model.app.backend.nowNext(keys: rows.map { $0.key })
        }
    }
}

struct PlayerOptionsSheet: View {
    @ObservedObject var model: PlayerModel
    var close: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if model.isLive && !model.qualities.isEmpty {
                    Section("Qualità del canale") {
                        ForEach(model.qualities) { q in
                            Button { model.chooseQuality(q); close() } label: {
                                HStack { Text(q.label); Spacer(); if q.current { Image(systemName: "checkmark").foregroundStyle(Theme.cyan) } }
                            }
                        }
                        if !model.resolution.isEmpty { Text("In riproduzione: \(model.resolution)").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if !model.audio.isEmpty {
                    Section("Audio") {
                        ForEach(model.audio) { t in
                            Button { model.selectAudio(t.id) } label: {
                                HStack { Text(t.name); Spacer(); if t.selected { Image(systemName: "checkmark").foregroundStyle(Theme.cyan) } }
                            }
                        }
                    }
                }
                if !model.subs.isEmpty {
                    Section("Sottotitoli") {
                        Button { model.selectSubtitle(nil) } label: {
                            HStack { Text("Nessuno"); Spacer(); if !model.subs.contains(where: { $0.selected }) { Image(systemName: "checkmark").foregroundStyle(Theme.cyan) } }
                        }
                        ForEach(model.subs) { t in
                            Button { model.selectSubtitle(t.id) } label: {
                                HStack { Text(t.name); Spacer(); if t.selected { Image(systemName: "checkmark").foregroundStyle(Theme.cyan) } }
                            }
                        }
                    }
                }
                if !model.isLive {
                    Section("Velocità") {
                        ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { r in
                            Button { model.setRate(r) } label: {
                                HStack { Text(r == 1 ? "Normale" : "\(String(format: "%g", r))×"); Spacer(); if model.rate == r { Image(systemName: "checkmark").foregroundStyle(Theme.cyan) } }
                            }
                        }
                    }
                }
                Section("Timer di spegnimento") {
                    if let left = model.sleepLeft { Text("Si ferma tra \(Int(left / 60) + 1) min").foregroundStyle(.secondary) }
                    ForEach([15, 30, 60, 90], id: \.self) { m in Button("Tra \(m) minuti") { model.setSleep(minutes: m); close() } }
                    if model.sleepLeft != nil { Button("Annulla il timer", role: .destructive) { model.setSleep(minutes: nil) } }
                }
                Section("Motore video") {
                    HStack { Text("In uso"); Spacer(); Text(model.engineName).foregroundStyle(.secondary) }
                    if model.canSwitchEngine { Button("Cambia motore e riprova") { model.switchEngine(); close() } }
                    Button("Riprova") { model.retry(); close() }
                }
            }
            .groupedList()
            .background(GlassBackground())
            .navigationTitle("Opzioni")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine", action: close) } }
        }
        .presentationDetents([.medium, .large])
    }
}
