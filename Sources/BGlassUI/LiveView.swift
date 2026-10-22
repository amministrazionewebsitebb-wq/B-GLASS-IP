import BGlassCore
import SwiftUI

/// The TV page: the channels with what is on now, or the programme guide.
struct LiveView: View {
    @EnvironmentObject var app: AppModel
    enum Mode: Hashable { case list, guide }

    @State private var mode: Mode
    @State private var filter: LiveFilter?
    @State private var channels: [LiveChannel] = []
    @State private var guide: [String: (now: Prog?, next: Prog?)] = [:]
    @State private var categories: [LiveCategory] = []
    @State private var hasMain = false
    @State private var hasFavs = false
    @State private var query = ""
    @State private var loaded = false
    @State private var pickingCategory = false

    init(guide: Bool = false) { _mode = State(initialValue: guide ? .guide : .list) }

    private var current: LiveFilter { filter ?? (hasMain ? .main : .all) }

    private var chips: [(LiveFilter, String)] {
        var c: [(LiveFilter, String)] = []
        if hasMain { c.append((.main, "Principali")) }
        if hasFavs { c.append((.favorites, "Preferiti")) }
        c.append((.all, "Tutti"))
        if case .category(_, let name) = current { c.append((current, name)) }
        return c
    }

    private var shown: [LiveChannel] {
        let q = Hash.fold(query).trimmed
        return q.isEmpty ? channels : channels.filter { Hash.fold($0.name).contains(q) }
    }

    private struct LoadKey: Equatable { var data: DataKey; var filter: LiveFilter }

    var body: some View {
        VStack(spacing: 12) {
            PillPicker(items: [(Mode.list, "Canali"), (Mode.guide, "Guida TV")], selection: $mode)
            ChipBar(items: chips, selection: Binding(get: { current }, set: { filter = $0 }),
                    trailing: categories.isEmpty ? nil : ("Categorie", { pickingCategory = true }))
            if !loaded {
                Spacer(); ProgressView().tint(.white); Spacer()
            } else if shown.isEmpty {
                Spacer()
                if current == .favorites {
                    EmptyState(icon: "heart", title: "Nessun preferito", message: "Tieni premuto un canale e scegli «Aggiungi ai preferiti».")
                } else if !query.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: "Nessun canale con questo nome")
                } else {
                    EmptyState(icon: "tv", title: app.liveReady ? "Nessun canale" : "Carico i canali…")
                }
                Spacer()
            } else if mode == .list {
                list
            } else {
                GuideView(channels: shown, play: { app.playLive($0, among: shown.map { $0.key }) })
            }
        }
        .padding(.top, 4)
        .background(GlassBackground())
        .navigationTitle("TV")
        .toolbar { ToolbarItem(placement: .primaryAction) { ProfileMenu() } }
        .searchable(text: $query, prompt: "Cerca un canale")
        .refreshable { app.refreshNow() }
        .task(id: LoadKey(data: app.dataKey, filter: current)) { await reload() }
        .task(id: app.guideRevision) {
            while !Task.isCancelled {                          // what is on changes by the minute
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await refreshGuideNow()
            }
        }
        .sheet(isPresented: $pickingCategory) {
            CategoryPicker(categories: categories) { c in filter = .category(src: c.src, name: c.name); pickingCategory = false }
        }
    }

    private var list: some View {
        ScrollView {
            LoadingBanner().padding(.bottom, 6)
            LazyVStack(spacing: 0) {
                ForEach(shown) { c in
                    Button { app.playLive(c.key, among: shown.map { $0.key }) } label: {
                        ChannelRowView(channel: c, now: guide[c.key]?.now, next: guide[c.key]?.next)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { app.toggleFav(c.key); Task { await reload() } } label: {
                            Label(c.fav ? "Togli dai preferiti" : "Aggiungi ai preferiti", systemImage: c.fav ? "heart.slash" : "heart")
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func reload() async {
        guard let p = app.profile else { return }
        let b = app.backend, f = current
        let r = await Task.detached(priority: .userInitiated) { () -> (Bool, [LiveCategory], [LiveChannel], [String: (now: Prog?, next: Prog?)]) in
            let main = b.mainChannels().count >= 6
            let effective: LiveFilter = (f == .main && !main) ? .all : f
            let list = b.channels(effective, profile: p)
            return (main, b.liveCategories(profile: p), list, b.nowNext(keys: list.prefix(3000).map { $0.key }))
        }.value
        hasMain = r.0
        categories = r.1
        channels = r.2
        guide = r.3
        hasFavs = !p.favs.isEmpty
        loaded = true
    }

    private func refreshGuideNow() async {
        let keys = channels.prefix(3000).map { $0.key }
        let b = app.backend
        guide = await Task.detached { b.nowNext(keys: keys) }.value
    }
}

struct ChannelRowView: View {
    let channel: LiveChannel
    let now: Prog?
    let next: Prog?
    var playing = false

    var body: some View {
        HStack(spacing: 14) {
            ChannelLogo(channel: channel.name, logo: channel.logo, width: 76, height: 50)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(playing ? Theme.cyan : Color.clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(channel.num)").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.tertiaryText)
                    Text(channel.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(playing ? Theme.cyan : Theme.secondaryText).lineLimit(1)
                    if channel.fav { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Theme.live) }
                }
                Text(now?.t ?? (channel.radio ? "Radio" : "In diretta")).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if let n = now {
                    HStack(spacing: 8) {
                        ProgressLine(fraction: TimeText.fraction(n), height: 3).frame(width: 70)
                        Text("\(TimeText.clock(n.s)) – \(TimeText.clock(n.e))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.tertiaryText)
                    }
                }
                if let x = next {
                    Text("Poi \(TimeText.clock(x.s)) · \(x.t)").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if playing { Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)).foregroundStyle(Theme.cyan) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(playing ? Theme.cyan.opacity(0.10) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 106) }
        .contentShape(Rectangle())
    }
}

struct CategoryPicker: View {
    let categories: [LiveCategory]
    let pick: (LiveCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(categories.filter { query.isEmpty || Hash.fold($0.label).contains(Hash.fold(query)) }) { c in
                Button { pick(c) } label: {
                    HStack { Text(c.label).lineLimit(1); Spacer(); Text("\(c.count)").foregroundStyle(Theme.tertiaryText) }
                }
                .listRowBackground(Theme.surface)
            }
            .groupedList()
            .background(GlassBackground())
            .searchable(text: $query, prompt: "Cerca una categoria")
            .navigationTitle("Categorie")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: guide grid

struct GuideView: View {
    @EnvironmentObject var app: AppModel
    let channels: [LiveChannel]
    let play: (String) -> Void

    @State private var window: [String: [Prog]] = [:]
    @State private var selected: GuideSelection?

    private let rowH: CGFloat = 62
    private let headH: CGFloat = 32
    private let colW: CGFloat = 78
    private let ppm: CGFloat = 4.4                    // points per minute

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
                    ForEach(channels.prefix(300)) { c in
                        Button { play(c.key) } label: {
                            ChannelLogo(channel: c.name, logo: c.logo, width: 62, height: 42).frame(width: colW, height: rowH)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(channels.prefix(300)) { c in row(c) }
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
                    .offset(x: CGFloat(i) * 30 * ppm + 6, y: 8)
            }
        }
    }

    private var nowLine: some View {
        let x = CGFloat(Int64(Date().timeIntervalSince1970) - from) / 60 * ppm
        return Rectangle().fill(Theme.live).frame(width: 2).frame(maxHeight: .infinity).offset(x: x).allowsHitTesting(false)
    }

    private func row(_ c: LiveChannel) -> some View {
        let progs = window[c.key] ?? []
        let now = Int64(Date().timeIntervalSince1970)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: rowH)
            if progs.isEmpty {
                Text(c.name + " · guida non disponibile").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).padding(.leading, 12).frame(height: rowH)
            }
            ForEach(progs, id: \.s) { p in
                let s = max(p.s, from), e = min(p.e, to)
                if e > s {
                    let x = CGFloat(s - from) / 60 * ppm
                    let w = max(8, CGFloat(e - s) / 60 * ppm - 3)
                    let live = p.s <= now && p.e > now
                    Button { selected = GuideSelection(channel: c, prog: p) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.t).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Text("\(TimeText.clock(p.s))").font(.system(size: 11)).foregroundStyle(live ? Color.white.opacity(0.8) : Theme.tertiaryText)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .frame(width: w, height: rowH - 6, alignment: .topLeading)
                        .background((live ? Theme.blue : Theme.surface), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        let keys = Array(channels.prefix(300)).map { $0.key }
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
                    Button { play() } label: { Label("Guarda il canale", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                }
                .padding(18)
            }
            .background(GlassBackground())
            .navigationTitle("Programma")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
