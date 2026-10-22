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

public struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @State private var options = false
    @State private var guide: [String: (now: Prog?, next: Prog?)] = [:]

    public init(app: AppModel, request: PlayRequest) {
        _model = StateObject(wrappedValue: PlayerModel(app: app, request: request))
    }

    public var body: some View {
        GeometryReader { g in
            let land = g.size.width > g.size.height
            VStack(spacing: 0) {
                stage(land: land, width: g.size.width)
                    .frame(width: g.size.width, height: land ? g.size.height : g.size.width * 9 / 16)
                if !land {
                    Group { if model.isLive { liveBelow } else { vodBelow } }
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: land)
            .hideStatusBar(land)
            .persistentSystemOverlays(land ? .hidden : .automatic)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onDisappear { model.close() }
        .sheet(isPresented: $options) { PlayerOptionsSheet(model: model) { options = false } }
        .task(id: model.channels.map { $0.key }) {
            // what is on now on every channel of the list, refreshed every minute
            while !Task.isCancelled && model.isLive {
                let b = model.app.backend, keys = model.channels.map { $0.key }
                guide = await Task.detached(priority: .utility) { b.nowNext(keys: keys) }.value
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    // MARK: the picture

    /// The video with everything drawn on it. It keeps the same place in the view tree in both orientations, so the picture never restarts.
    private func stage(land: Bool, width: CGFloat) -> some View {
        ZStack {
            Color.black
            VideoSurface(engine: model.engine).id(model.engineEpoch)
            touchLayer(width: width)
            if (model.phase == .loading || model.phase == .buffering) && !model.controlsVisible {
                ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.4).allowsHitTesting(false)
            }
            if model.controlsVisible {
                Group { if land { landscapeControls } else { portraitControls } }.transition(.opacity)
            }
            if land, let b = model.zapBanner, !model.controlsVisible { zapBanner(b) }
            if let n = model.notice {
                VStack {
                    Text(n).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.top, land ? 18 : 50)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            if case .failed(let msg) = model.phase { errorCard(msg, compact: !land) }
            if let n = model.upNext { upNextCard(n) }
        }
        .ignoresSafeArea(.container, edges: land ? .all : [])
        .clipped()
    }

    @ViewBuilder private func touchLayer(width: CGFloat) -> some View {
        let tap = { withAnimation(.easeOut(duration: 0.2)) { model.toggleControls() } }
        if model.isLive {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(perform: tap)
                .simultaneousGesture(MagnificationGesture().onEnded { pinch($0) })
        } else {
            Color.clear.contentShape(Rectangle())
                .gesture(SpatialTapGesture(count: 2).onEnded { v in model.seek(by: v.location.x < width / 2 ? -10 : 10) }
                    .exclusively(before: TapGesture().onEnded(tap)))
                .simultaneousGesture(MagnificationGesture().onEnded { pinch($0) })
        }
    }

    private func pinch(_ s: CGFloat) {
        if (s > 1.15 && !model.fill) || (s < 0.87 && model.fill) { model.toggleFill() }
    }

    private func fullScreen(_ on: Bool) {
        Haptics.tap()
        OrientationLock.request(landscape: on)
        model.showControls()
    }

    // MARK: controls

    private var shade: some View {
        Color.black.opacity(0.38).allowsHitTesting(false)
    }

    private var portraitControls: some View {
        ZStack {
            shade
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    iconButton("chevron.down", size: 20) { model.close() }
                    Spacer()
                    if model.supportsPiP { iconButton(model.pipActive ? "pip.exit" : "pip.enter") { model.togglePiP() } }
                    AirPlayButton()
                    iconButton("ellipsis") { options = true }
                }
                Spacer()
                HStack(alignment: .center, spacing: 10) {
                    if model.isLive { Spacer() } else { scrubber }
                    iconButton("arrow.up.left.and.arrow.down.right", size: 16) { fullScreen(true) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            centerButtons(big: false)
        }
    }

    private var landscapeControls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.15), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    iconButton("chevron.down", size: 22) { model.close() }
                    if model.isLive { ChannelLogo(channel: model.title, logo: model.logo, width: 54, height: 36) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Text(model.isLive ? (model.now?.t ?? "In diretta") : model.subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if model.isLive { iconButton(model.isFav ? "heart.fill" : "heart") { model.toggleFav() } }
                    if model.supportsPiP { iconButton(model.pipActive ? "pip.exit" : "pip.enter") { model.togglePiP() } }
                    AirPlayButton()
                    iconButton("ellipsis") { options = true }
                }
                Spacer()
                if model.isLive { landscapeLiveBottom } else { landscapeVodBottom }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            centerButtons(big: true)
        }
    }

    private func centerButtons(big: Bool) -> some View {
        HStack(spacing: big ? 56 : 40) {
            if model.isLive {
                if big && model.channels.count > 1 { iconButton("backward.end.fill", size: 24) { model.zap(-1) } }
            } else {
                iconButton("gobackward.10", size: big ? 28 : 24) { model.seek(by: -10) }
            }
            Button { Haptics.tap(); model.togglePlay() } label: {
                Group {
                    if model.phase == .loading || model.phase == .buffering {
                        ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.2)
                    } else {
                        Image(systemName: model.phase == .playing ? "pause.fill" : "play.fill").font(.system(size: big ? 30 : 24, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: big ? 70 : 56, height: big ? 70 : 56)
                .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            if model.isLive {
                if big && model.channels.count > 1 { iconButton("forward.end.fill", size: 24) { model.zap(1) } }
            } else {
                iconButton("goforward.10", size: big ? 28 : 24) { model.seek(by: 10) }
            }
        }
    }

    private var landscapeLiveBottom: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LiveBadge()
                if let n = model.now {
                    Text("\(TimeText.clock(n.s)) – \(TimeText.clock(n.e))").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                    ProgressLine(fraction: TimeText.fraction(n), height: 3).frame(maxWidth: 160)
                }
                if let x = model.next { Text("Poi \(TimeText.clock(x.s)) · \(x.t)").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(1) }
                Spacer()
                iconButton("arrow.down.right.and.arrow.up.left", size: 16) { fullScreen(false) }
            }
            if model.channels.count > 1 { channelStrip }
        }
    }

    /// The channels in a row along the bottom of the full screen picture: one tap changes channel.
    private var channelStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(model.channels) { c in
                        let on = c.key == model.currentKey
                        Button { Haptics.tap(); model.playChannel(c.key); model.showControls() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ChannelLogo(channel: c.name, logo: c.logo, width: 112, height: 62)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.white : Color.clear, lineWidth: 2))
                                Text(guide[c.key]?.now?.t ?? c.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? .white : Theme.secondaryText)
                                    .lineLimit(1).frame(width: 112, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(c.key)
                    }
                }
                .padding(.horizontal, 2)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in model.showControls() })
            .onAppear { proxy.scrollTo(model.currentKey, anchor: .center) }
        }
        .frame(height: 84)
    }

    private var landscapeVodBottom: some View {
        VStack(spacing: 8) {
            scrubber
            HStack(spacing: 8) {
                if !model.audio.isEmpty || !model.subs.isEmpty { pill("captions.bubble", "Audio e sottotitoli") { options = true } }
                if model.hasNextEpisode { pill("forward.end.fill", "Prossimo episodio") { model.playNextEpisode() } }
                Spacer()
                iconButton(model.fill ? "aspectratio.fill" : "aspectratio", size: 16) { model.toggleFill() }
                iconButton("arrow.down.right.and.arrow.up.left", size: 16) { fullScreen(false) }
            }
        }
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            Text(TimeText.duration(model.positionMs)).font(.system(size: 12, weight: .medium)).monospacedDigit()
            Slider(value: Binding(get: { Double(model.positionMs) }, set: { model.seek(toMs: Int64($0)) }),
                   in: 0...Double(max(model.durationMs, 1)),
                   onEditingChanged: { editing in model.scrubbing = editing; if editing { model.showControls() } })
                .tint(.white)
                .disabled(model.durationMs <= 0)
            Text("-" + TimeText.duration(max(0, model.durationMs - model.positionMs))).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
        }
    }

    private func iconButton(_ system: String, size: CGFloat = 18, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action(); model.showControls() } label: {
            Image(systemName: system).font(.system(size: size, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pill(_ icon: String, _ text: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action(); model.showControls() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: messages on the picture

    private func zapBanner(_ b: PlayerModel.Banner) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                ChannelLogo(channel: b.name, logo: b.logo, width: 60, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(b.number)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.sky)
                    Text(b.name).font(.system(size: 17, weight: .bold)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: 340)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 28)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func errorCard(_ msg: String, compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            Text(model.isLive ? "Il canale non si apre" : "Il video non parte").font(.system(size: compact ? 16 : 19, weight: .bold))
            Text(msg).font(.system(size: compact ? 11 : 13)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).lineLimit(compact ? 5 : 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Riprova") { model.retry() }.buttonStyle(GlassButtonStyle(prominent: true))
                if model.canSwitchEngine { Button(model.engineName == "VLC" ? "Lettore Apple" : "Prova con VLC") { model.switchEngine() }.buttonStyle(GlassButtonStyle()) }
                if !compact { Button("Chiudi") { model.close() }.buttonStyle(GlassButtonStyle()) }
            }
        }
        .padding(compact ? 12 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.82))
    }

    private func upNextCard(_ e: EpisodeRow) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prossimo episodio tra \(model.upNextIn) s").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sky)
                    Text("S\(e.season) E\(e.number) · \(e.title)").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    HStack {
                        Button("Guarda ora") { model.playNextEpisode() }.buttonStyle(GlassButtonStyle(prominent: true))
                        Button("Annulla") { model.cancelUpNext(); model.close() }.buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(14)
                .frame(maxWidth: 320)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(14)
        }
    }

    // MARK: under the picture (phone held upright)

    private var liveBelow: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ChannelLogo(channel: model.title, logo: model.logo, width: 64, height: 42)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        LiveBadge()
                        Text(model.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                    Text(model.now?.t ?? "In diretta").font(.system(size: 19, weight: .bold)).lineLimit(2)
                    if let n = model.now {
                        HStack(spacing: 8) {
                            ProgressLine(fraction: TimeText.fraction(n), height: 3).frame(width: 90)
                            Text("\(TimeText.clock(n.s)) – \(TimeText.clock(n.e))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    if let x = model.next {
                        Text("Poi \(TimeText.clock(x.s)) · \(x.t)").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button { model.toggleFav() } label: { Image(systemName: model.isFav ? "heart.fill" : "heart").foregroundStyle(model.isFav ? Theme.live : .white) }
                    .buttonStyle(IconButtonStyle(size: 40))
            }
            .padding(16)
            if model.channels.count > 1 {
                HStack {
                    Text("Canali").font(.system(size: 17, weight: .bold))
                    Text("\(model.channels.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.channels) { c in
                                Button { Haptics.tap(); model.playChannel(c.key) } label: {
                                    ChannelRowView(channel: c, now: guide[c.key]?.now, next: nil, playing: c.key == model.currentKey)
                                }
                                .buttonStyle(.plain)
                                .id(c.key)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(model.currentKey, anchor: .center) }
                    .onChange(of: model.currentKey) { k in withAnimation { proxy.scrollTo(k, anchor: .center) } }
                }
            }
        }
        .background(Theme.ink)
    }

    private var vodBelow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title).font(.system(size: 22, weight: .heavy)).lineLimit(2)
                    if !model.subtitle.isEmpty { Text(model.subtitle).font(.system(size: 14)).foregroundStyle(Theme.secondaryText).lineLimit(2) }
                }
                .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        pill("arrow.up.left.and.arrow.down.right", "Schermo intero") { fullScreen(true) }
                        if !model.audio.isEmpty || !model.subs.isEmpty { pill("captions.bubble", "Audio e sottotitoli") { options = true } }
                        if model.hasNextEpisode { pill("forward.end.fill", "Prossimo episodio") { model.playNextEpisode() } }
                    }
                    .padding(.horizontal, 16)
                }
                let eps = model.seasonEpisodes
                if eps.count > 1, let cur = model.episode {
                    Text("Stagione \(cur.season)").font(.system(size: 17, weight: .bold)).padding(.horizontal, 16).padding(.top, 6)
                    LazyVStack(spacing: 0) {
                        ForEach(eps) { ep in
                            Button { model.playEpisode(ep) } label: { EpisodeRowView(ep: ep, progress: nil, playing: ep.rk == cur.rk) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.ink)
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
                Section("Se qualcosa non va") {
                    HStack { Text("Lettore"); Spacer(); Text(model.engineName).foregroundStyle(.secondary) }
                    if model.canSwitchEngine { Button("Cambia lettore e riprova") { model.switchEngine(); close() } }
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
