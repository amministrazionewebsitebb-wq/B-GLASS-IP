import BGlassCore
import SwiftUI

/// The page of a film or a series: artwork, story, play buttons, seasons and episodes.
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
    private var inProfile: Bool { profile?.has(card.kind, card.key) ?? false }
    private var allEpisodes: [EpisodeRow] { series?.seasons.flatMap { $0.episodes } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                story
                if card.kind == .series { episodes }
                Color.clear.frame(height: 30)
            }
        }
        .background(
            ZStack {
                GlassBackground()
                RemoteImage(backdrop, title: "", maxPixel: 900).blur(radius: 40).opacity(0.28).ignoresSafeArea()
            }
        )
        .navigationTitle("")
        .inlineTitle()
        .clearNavBar()
        .task(id: card.key) { await load() }
    }

    private var backdrop: String? {
        if let b = details?.backdrop, !b.isEmpty { return b }
        if let s = series?.backdrop, !s.isEmpty { return s }
        return card.logo
    }

    // MARK: sections

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            PosterCard(card: card, width: 118, showTitle: false)
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title).font(.system(size: 26, weight: .heavy)).lineLimit(4)
                FlowMeta(items: meta)
                if card.rate > 0 { RatingBadge(value: card.rate) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 6)
    }

    private var meta: [String] {
        var m: [String] = []
        let y = details?.year ?? series?.year ?? ""
        if !y.isEmpty { m.append(y) }
        if let d = details?.duration, !d.isEmpty { m.append(d) }
        let g = details?.genre ?? series?.genre ?? ""
        if !g.isEmpty { m.append(g) }
        if card.kind == .series, let s = series, !s.seasons.isEmpty { m.append("\(s.seasons.count) stagion\(s.seasons.count == 1 ? "e" : "i")") }
        if !card.extra.isEmpty, card.extra.contains("episod") { m.append(card.extra) }
        return m
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if card.kind == .movie {
                if card.progress > 0 || (profile?.resume[card.key] ?? 0) > 0 {
                    let pos = profile?.resume[card.key] ?? card.progress
                    Button { app.play(.movie(key: card.key, resume: pos)) } label: { Label("Riprendi da \(TimeText.duration(pos))", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                    Button { app.play(.movie(key: card.key, resume: 0)) } label: { Label("Dall'inizio", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(GlassButtonStyle())
                } else {
                    Button { app.play(.movie(key: card.key, resume: 0)) } label: { Label("Guarda", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                }
            } else if let (ep, pos) = continueEpisode {
                Button { play(ep, resume: pos) } label: {
                    Label(pos > 0 ? "Riprendi S\(ep.season) E\(ep.number)" : "Guarda S\(ep.season) E\(ep.number)", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
            } else if loading {
                Button {} label: { HStack { ProgressView().tint(.white); Text("Carico gli episodi…") }.frame(maxWidth: .infinity) }.buttonStyle(GlassButtonStyle()).disabled(true)
            }
            HStack(spacing: 10) {
                Button { toggleProfile() } label: {
                    Label(inProfile ? "Nel tuo profilo" : "Aggiungi al profilo", systemImage: inProfile ? "checkmark" : "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                if let t = details?.trailer, !t.isEmpty, let u = URL(string: t.hasPrefix("http") ? t : "https://www.youtube.com/watch?v=\(t)") {
                    Button { openURL(u) } label: { Label("Trailer", systemImage: "play.rectangle").frame(maxWidth: .infinity) }.buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var story: some View {
        let plot = details?.plot ?? ""
        VStack(alignment: .leading, spacing: 10) {
            if !plot.isEmpty {
                Text(plot).font(.system(size: 15)).foregroundStyle(.white.opacity(0.88)).lineLimit(expanded ? nil : 5)
                    .onTapGesture { withAnimation { expanded.toggle() } }
            } else if loading {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)).frame(height: 70).modifier(Shimmer()).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if let c = (details?.cast ?? series?.cast), !c.isEmpty { labeled("Cast", c) }
            if let d = (details?.director ?? series?.director), !d.isEmpty { labeled("Regia", d) }
            if let f = failed { Text(f).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText) }
        }
        .padding(.horizontal, 16)
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        (Text(k + "  ").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.secondaryText) + Text(v).font(.system(size: 13)).foregroundColor(.white.opacity(0.85)))
    }

    @ViewBuilder private var episodes: some View {
        if let s = series, !s.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Episodi").font(.system(size: 20, weight: .bold))
                    Spacer()
                    if s.seasons.count > 1 {
                        Menu {
                            ForEach(s.seasons) { se in Button("Stagione \(se.number)") { season = se.number } }
                        } label: {
                            HStack(spacing: 4) { Text("Stagione \(season)"); Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
                                .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 7).glass(radius: 14)
                        }
                    }
                }
                .padding(.horizontal, 16)
                let current = s.seasons.first { $0.number == season } ?? s.seasons[0]
                LazyVStack(spacing: 10) {
                    ForEach(current.episodes) { ep in
                        Button { play(ep, resume: profile?.resume[ep.rk] ?? 0) } label: { EpisodeRowView(ep: ep, progress: progress(ep)) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        } else if !loading, card.kind == .series {
            Text("Nessun episodio disponibile.").font(.system(size: 14)).foregroundStyle(Theme.secondaryText).padding(.horizontal, 16)
        }
    }

    // MARK: logic

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

    private func toggleProfile() {
        guard let p = profile else { return }
        let on = !inProfile
        app.backend.select(p.id, kind: card.kind, keys: [card.key], on: on)
        app.reloadProfile()
        Haptics.tap()
        app.show(on ? "Aggiunto al tuo profilo" : "Tolto dal tuo profilo")
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                RemoteImage(ep.image, title: "E\(ep.number)", maxPixel: 360)
                if let f = progress { ProgressLine(fraction: f).padding(.horizontal, 6).padding(.bottom, 5) }
            }
            .frame(width: 124, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ep.number). \(ep.title)").font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                if !ep.duration.isEmpty { Text(ep.duration).font(.system(size: 12)).foregroundStyle(Theme.secondaryText) }
                if !ep.plot.isEmpty { Text(ep.plot).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle").font(.system(size: 22)).foregroundStyle(Theme.cyan)
        }
        .padding(10)
        .glass(radius: 16)
    }
}

/// Small facts separated by dots ("2024 · 1h 40m · Azione").
struct FlowMeta: View {
    let items: [String]
    var body: some View {
        Text(items.joined(separator: "  ·  ")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryText).lineLimit(3)
    }
}
