import BGlassCore
import SwiftUI

/// The page of a film or a series: big artwork, the play button, the story, seasons and episodes.
struct DetailView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.openURL) private var openURL
    let card: Card

    @State private var details: VodDetails?
    @State private var series: SeriesDetails?
    @State private var season = 1
    @State private var loading = true
    @State private var failed: String?
    @State private var expanded = false

    private var profile: Profile? { app.profile }
    private var allEpisodes: [EpisodeRow] { series?.seasons.flatMap { $0.episodes } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artwork
                VStack(alignment: .leading, spacing: 14) {
                    Text(card.title).font(.system(size: 28, weight: .heavy)).lineLimit(3)
                    metaLine
                    actions
                    story
                }
                .padding(.horizontal, 16)
                if card.kind == .series { episodes }
                Color.clear.frame(height: 30)
            }
        }
        .background(GlassBackground())
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .inlineTitle()
        .clearNavBar()
        .task(id: card.key) { await load() }
    }

    private var backdrop: String? {
        if let b = details?.backdrop, !b.isEmpty { return b }
        if let s = series?.backdrop, !s.isEmpty { return s }
        return nil
    }

    private var artwork: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                if let b = backdrop {
                    RemoteImage(b, title: card.name, maxPixel: 1200).frame(width: g.size.width, height: g.size.height).clipped()
                } else {
                    ZStack {
                        RemoteImage(card.logo, title: card.name, maxPixel: 500).blur(radius: 30).opacity(0.7).frame(width: g.size.width, height: g.size.height).clipped()
                        RemoteImage(card.logo, title: card.name, maxPixel: 700).aspectRatio(2 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
                            .padding(.top, 70).padding(.bottom, 24)
                    }
                }
                LinearGradient(colors: [.clear, Theme.ink.opacity(0.6), Theme.ink], startPoint: .center, endPoint: .bottom)
            }
        }
        .frame(height: 330)
    }

    private var metaLine: some View {
        var m: [String] = []
        let y = details?.year ?? series?.year ?? ""
        if !y.isEmpty { m.append(y) }
        if let d = details?.duration, !d.isEmpty { m.append(d) }
        let g = (details?.genre ?? series?.genre ?? "").split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
        if !g.isEmpty { m.append(g) }
        if card.kind == .series, let s = series, !s.seasons.isEmpty { m.append("\(s.seasons.count) stagion\(s.seasons.count == 1 ? "e" : "i")") }
        return HStack(spacing: 8) {
            if card.rate > 0 { RatingBadge(value: card.rate) }
            Text(m.joined(separator: " · ")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryText).lineLimit(2)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if card.kind == .movie {
                let pos = profile?.resume[card.key] ?? card.progress
                Button { app.play(.movie(key: card.key, resume: pos)) } label: {
                    Label(pos > 0 ? "Riprendi da \(TimeText.duration(pos))" : "Guarda", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                if pos > 0, let dur = profile?.done[card.key], dur > 0 { ProgressLine(fraction: Double(pos) / Double(dur)) }
            } else if let (ep, pos) = continueEpisode {
                Button { play(ep, resume: pos) } label: {
                    Label(pos > 0 ? "Riprendi S\(ep.season) E\(ep.number)" : "Guarda S\(ep.season) E\(ep.number)", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
            } else if loading {
                Button {} label: { HStack { ProgressView().tint(.black); Text("Carico gli episodi…") }.frame(maxWidth: .infinity) }
                    .buttonStyle(GlassButtonStyle(prominent: true)).disabled(true)
            }
            HStack(spacing: 24) {
                actionIcon(app.backend.inMyList(profile, card.key) ? "checkmark" : "plus", "La mia lista") {
                    guard let p = profile else { return }
                    let on = app.backend.toggleMyList(p.id, key: card.key)
                    app.refreshProfileSnapshot()
                    Haptics.tap()
                    app.show(on ? "Aggiunto a La mia lista" : "Tolto da La mia lista")
                }
                if card.kind == .movie, (profile?.resume[card.key] ?? 0) > 0 {
                    actionIcon("arrow.counterclockwise", "Dall'inizio") { app.play(.movie(key: card.key, resume: 0)) }
                }
                if let t = details?.trailer, !t.isEmpty, let u = URL(string: t.hasPrefix("http") ? t : "https://www.youtube.com/watch?v=\(t)") {
                    actionIcon("play.rectangle", "Trailer") { openURL(u) }
                }
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func actionIcon(_ icon: String, _ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).frame(height: 24)
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var story: some View {
        let plot = details?.plot ?? series?.plot ?? ""
        VStack(alignment: .leading, spacing: 8) {
            if !plot.isEmpty {
                Text(plot).font(.system(size: 15)).foregroundStyle(.white.opacity(0.88)).lineLimit(expanded ? nil : 4)
                    .onTapGesture { withAnimation { expanded.toggle() } }
            } else if loading {
                RoundedRectangle(cornerRadius: 6).fill(Theme.surface).frame(height: 64).modifier(Shimmer()).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if let c = (details?.cast ?? series?.cast), !c.isEmpty { labeled("Con", c) }
            if let d = (details?.director ?? series?.director), !d.isEmpty { labeled("Regia", d) }
            if let f = failed { Text(f).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText) }
        }
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        (Text(k + "  ").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.tertiaryText) + Text(v).font(.system(size: 13)).foregroundColor(Theme.secondaryText))
            .lineLimit(2)
    }

    @ViewBuilder private var episodes: some View {
        if let s = series, !s.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Episodi").font(.system(size: 20, weight: .bold)).padding(.horizontal, 16)
                if s.seasons.count > 1 {
                    ChipBar(items: s.seasons.map { ($0.number, "Stagione \($0.number)") }, selection: $season)
                }
                let current = s.seasons.first { $0.number == season } ?? s.seasons[0]
                LazyVStack(spacing: 0) {
                    ForEach(current.episodes) { ep in
                        Button { play(ep, resume: profile?.resume[ep.rk] ?? 0) } label: { EpisodeRowView(ep: ep, progress: progress(ep)) }.buttonStyle(.plain)
                    }
                }
            }
        } else if !loading, card.kind == .series {
            Text("Nessun episodio disponibile.").font(.system(size: 14)).foregroundStyle(Theme.secondaryText).padding(.horizontal, 16)
        }
    }

    private func progress(_ ep: EpisodeRow) -> Double? {
        guard let p = profile, let pos = p.resume[ep.rk], let d = p.done[ep.rk], d > 0 else { return nil }
        return min(1, Double(pos) / Double(d))
    }

    /// The episode to offer: the one the viewer stopped at, or the first of the first season.
    private var continueEpisode: (EpisodeRow, Int64)? {
        guard let p = profile else { return allEpisodes.first.map { ($0, 0) } }
        let mine = p.resumeAt.filter { p.resumeParent[$0.key] == card.key }
        if let rk = mine.max(by: { $0.value < $1.value })?.key, let ep = allEpisodes.first(where: { $0.rk == rk }) { return (ep, p.resume[rk] ?? 0) }
        return allEpisodes.first.map { ($0, 0) }
    }

    private func play(_ ep: EpisodeRow, resume: Int64) {
        app.play(.episode(ep: ep, seriesKey: card.key, all: allEpisodes, resume: resume))
    }

    private func load() async {
        loading = true
        failed = nil
        details = await app.backend.vodDetails(card.key)
        if card.kind == .series {
            do {
                let s = try await app.backend.seriesDetails(card.key)
                series = s
                if let first = s.seasons.first {
                    season = first.number
                    if let cur = continueEpisode { season = cur.0.season }
                }
            } catch { failed = Net.explain(error) }
        }
        loading = false
    }
}

struct EpisodeRowView: View {
    let ep: EpisodeRow
    let progress: Double?
    var playing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottom) {
                RemoteImage(ep.image, title: "E\(ep.number)", maxPixel: 360)
                if let f = progress { ProgressLine(fraction: f).padding(.horizontal, 6).padding(.bottom, 5) }
                if playing { Image(systemName: "speaker.wave.2.fill").font(.system(size: 16)).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(playing ? Theme.cyan : Color.clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ep.number). \(ep.title)").font(.system(size: 15, weight: .semibold)).foregroundStyle(playing ? Theme.cyan : .white)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !ep.duration.isEmpty { Text(ep.duration).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText) }
                if !ep.plot.isEmpty { Text(ep.plot).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
