import BGlassCore
import SwiftUI

/// The TV page: the viewer's channels with what is on now, or the programme guide.
struct LiveView: View {
    @EnvironmentObject var app: AppModel
    enum Mode: String { case list = "Canali", guide = "Guida" }

    @State private var mode: Mode

    init(guide: Bool = false) { _mode = State(initialValue: guide ? .guide : .list) }
    @State private var channels: [LiveChannel] = []
    @State private var guide: [String: (now: Prog?, next: Prog?)] = [:]
    @State private var group = "Tutti"
    @State private var query = ""
    @State private var loaded = false
    @State private var pickerKey: String?

    private var groups: [String] {
        var g = ["Tutti"]
        if channels.contains(where: { $0.fav }) { g.append("Preferiti") }
        var seen = Set<String>()
        for c in channels where seen.insert(c.cat).inserted { g.append(c.cat) }
        return g
    }

    private var shown: [LiveChannel] {
        var l = channels
        if group == "Preferiti" { l = l.filter { $0.fav } } else if group != "Tutti" { l = l.filter { $0.cat == group } }
        let q = Hash.fold(query).trimmed
        if !q.isEmpty { l = l.filter { Hash.fold($0.name).contains(q) } }
        return l
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Canali").tag(Mode.list); Text("Guida").tag(Mode.guide)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
            if !channels.isEmpty { chips }
            if !loaded {
                Spacer(); ProgressView().tint(.white); Spacer()
            } else if channels.isEmpty {
                Spacer()
                EmptyState(icon: "tv", title: "Nessun canale nel profilo",
                           message: "Scegli i pacchetti consigliati (sport, cinema, news…) o le categorie della tua lista.",
                           action: "Scegli i canali") { app.setupProfile = app.profile }
                Spacer()
            } else if mode == .list {
                list
            } else {
                GuideView(channels: shown, play: { app.playLive($0, among: shown.map { $0.key }) })
            }
        }
        .background(GlassBackground())
        .navigationTitle("TV")
        .toolbar { ToolbarItem(placement: .primaryAction) { ProfileMenu() } }
        .searchable(text: $query, prompt: "Cerca un canale")
        .refreshable { app.refreshNow() }
        .task(id: app.dataKey) { await reload() }
        .task(id: app.guideRevision) {
            // what is on changes by the minute
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await refreshGuideNow()
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.self) { g in
                    Button { withAnimation(.easeOut(duration: 0.15)) { group = g }; Haptics.tap() } label: {
                        Text(g).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 13).padding(.vertical, 7)
                            .background(group == g ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Color.white.opacity(0.09)), in: Capsule())
                            .foregroundStyle(group == g ? Color.black.opacity(0.85) : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                LoadingBanner()
                ForEach(shown) { c in
                    Button { app.playLive(c.key, among: shown.map { $0.key }) } label: { ChannelRowView(channel: c, now: guide[c.key]?.now, next: guide[c.key]?.next) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { app.toggleFav(c.key) } label: { Label(c.fav ? "Togli dai preferiti" : "Aggiungi ai preferiti", systemImage: c.fav ? "heart.slash" : "heart") }
                            Button(role: .destructive) { remove(c) } label: { Label("Rimuovi dal profilo", systemImage: "minus.circle") }
                        }
                }
                if shown.isEmpty { Text("Nessun canale corrisponde.").foregroundStyle(Theme.secondaryText).padding(.top, 40) }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func remove(_ c: LiveChannel) {
        guard let p = app.profile else { return }
        app.backend.select(p.id, kind: .live, keys: [c.key], on: false)
        app.reloadProfile()
        app.show("«\(c.name)» tolto dal profilo")
    }

    private func reload() async {
        guard let p = app.profile else { return }
        let b = app.backend
        let (l, g) = await Task.detached(priority: .userInitiated) { () -> ([LiveChannel], [String: (now: Prog?, next: Prog?)]) in
            let l = b.liveList(profile: p)
            return (l, b.nowNext(keys: l.map { $0.key }))
        }.value
        channels = l
        guide = g
        loaded = true
        if !groups.contains(group) { group = "Tutti" }
    }

    private func refreshGuideNow() async {
        let keys = channels.map { $0.key }
        let b = app.backend
        guide = await Task.detached { b.nowNext(keys: keys) }.value
    }
}

struct ChannelRowView: View {
    @EnvironmentObject var app: AppModel
    let channel: LiveChannel
    let now: Prog?
    let next: Prog?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(channel.num)").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.tertiaryText).frame(width: 28, alignment: .trailing)
            ChannelLogo(channel: channel.name, logo: channel.logo)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(channel.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if channel.radio { Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 11)).foregroundStyle(Theme.cyan) }
                }
                if let n = now {
                    Text(n.t).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    if n.e > n.s { ProgressLine(fraction: min(1, max(0, Double(Int64(Date().timeIntervalSince1970) - n.s) / Double(n.e - n.s))), height: 2.5).padding(.trailing, 20) }
                    if let x = next { Text("\(TimeText.clock(x.s))  \(x.t)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText).lineLimit(1) }
                } else {
                    Text(channel.hasEpg ? "Guida in aggiornamento" : "In diretta").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            Button { app.toggleFav(channel.key) } label: {
                Image(systemName: channel.fav ? "heart.fill" : "heart").font(.system(size: 16)).foregroundStyle(channel.fav ? Theme.live : Theme.tertiaryText).frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .glass(radius: 16)
    }
}

// MARK: guide grid

struct GuideView: View {
    @EnvironmentObject var app: AppModel
    let channels: [LiveChannel]
    let play: (String) -> Void

    @State private var window: [String: [Prog]] = [:]
    @State private var selected: GuideSelection?

    private let rowH: CGFloat = 58
    private let headH: CGFloat = 30
    private let colW: CGFloat = 86
    private let ppm: CGFloat = 4.6                    // points per minute

    struct GuideSelection: Identifiable {
        let channel: LiveChannel
        let prog: Prog
        var id: String { channel.key + "\(prog.s)" }
    }

    private var from: Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        return (now / 1800) * 1800 - 1800
    }
    private var to: Int64 { from + 8 * 3600 }
    private var width: CGFloat { CGFloat(to - from) / 60 * ppm }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(width: colW, height: headH)
                    ForEach(channels.prefix(250)) { c in
                        HStack(spacing: 6) {
                            ChannelLogo(channel: c.name, logo: c.logo, width: 44, height: 32)
                            Text("\(c.num)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiaryText)
                        }
                        .frame(width: colW, height: rowH)
                        .onTapGesture { play(c.key) }
                    }
                }
                .background(.ultraThinMaterial)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(channels.prefix(250)) { c in row(c) }
                        }
                    }
                    .overlay(alignment: .topLeading) { nowLine }
                }
            }
        }
        .task(id: channels.map { $0.key }) { await load() }
        .sheet(item: $selected) { s in ProgrammeSheet(channel: s.channel, prog: s.prog, play: { play(s.channel.key); selected = nil }) }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: headH)
            ForEach(0..<16, id: \.self) { i in
                let t = from + Int64(i) * 1800
                Text(TimeText.clock(t)).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                    .offset(x: CGFloat(i) * 30 * ppm + 6, y: 6)
            }
        }
    }

    private var nowLine: some View {
        let x = CGFloat(Int64(Date().timeIntervalSince1970) - from) / 60 * ppm
        return Rectangle().fill(Theme.live).frame(width: 1.5).frame(maxHeight: .infinity).offset(x: x).allowsHitTesting(false)
    }

    private func row(_ c: LiveChannel) -> some View {
        let progs = window[c.key] ?? []
        let now = Int64(Date().timeIntervalSince1970)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: rowH)
            if progs.isEmpty {
                Text(c.hasEpg ? "…" : "Guida non disponibile").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText).padding(.leading, 12).frame(height: rowH)
            }
            ForEach(progs, id: \.s) { p in
                let s = max(p.s, from), e = min(p.e, to)
                if e > s {
                    let x = CGFloat(s - from) / 60 * ppm
                    let w = max(8, CGFloat(e - s) / 60 * ppm - 3)
                    let live = p.s <= now && p.e > now
                    Button { selected = GuideSelection(channel: c, prog: p) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.t).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Text(TimeText.clock(p.s)).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .frame(width: w, height: rowH - 6, alignment: .topLeading)
                        .background((live ? Theme.blue.opacity(0.85) : Color.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(live ? 0.35 : 0.12), lineWidth: 0.7))
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .offset(x: x, y: 3)
                }
            }
        }
        .frame(width: width, height: rowH)
    }

    private func load() async {
        let keys = Array(channels.prefix(250)).map { $0.key }
        let b = app.backend, f = from, t = to
        window = await Task.detached(priority: .userInitiated) { b.epgWindow(keys: keys, from: f, to: t) }.value
    }
}

struct ProgrammeSheet: View {
    let channel: LiveChannel
    let prog: Prog
    let play: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ChannelLogo(channel: channel.name, logo: channel.logo)
                        VStack(alignment: .leading) {
                            Text(channel.name).font(.system(size: 15, weight: .semibold))
                            Text("\(TimeText.clock(prog.s)) – \(TimeText.clock(prog.e))").font(.system(size: 13)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                        }
                    }
                    Text(prog.t).font(.system(size: 24, weight: .bold))
                    if !prog.d.isEmpty { Text(prog.d).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)) }
                    Button { play() } label: { Label("Guarda il canale", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(GlassButtonStyle(prominent: true))
                }
                .padding(18)
            }
            .background(GlassBackground())
            .navigationTitle("Programma")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
