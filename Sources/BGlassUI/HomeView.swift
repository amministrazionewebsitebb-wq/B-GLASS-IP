import BGlassCore
import SwiftUI

struct HomeData {
    var hero: Card?
    var onAir: [(channel: LiveChannel, now: Prog?)] = []
    var liveKeys: [String] = []
    var movies: [Row] = []
    var series: [Row] = []
    var hasAnything = false
}

/// What makes a screen rebuild its rows.
struct DataKey: Equatable {
    var content: Int
    var guide: Int
    var profile: String
    var ready: Bool
}

extension AppModel {
    var dataKey: DataKey { DataKey(content: contentRevision, guide: guideRevision, profile: profile?.id ?? "", ready: libraryReady) }

    /// Pull to refresh: the channel lists and the guide, the cheap parts.
    func refreshNow() {
        for s in sources { refresh(s.id, liveOnly: s.type == .xtream, auto: false) }
        refreshGuide()
    }
}

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    let go: (MainTab) -> Void
    @State private var data: HomeData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                LoadingBanner()
                expiryNotice
                if let d = data {
                    if let h = d.hero { HeroCard(card: h) }
                    content(d)
                } else {
                    HeroSkeleton()
                    RailSkeleton(title: "Continua a guardare")
                    RailSkeleton()
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(GlassBackground())
        .navigationTitle("")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .principal) { Wordmark(size: 21) }
            ToolbarItem(placement: .primaryAction) { ProfileMenu() }
        }
        .refreshable { app.refreshNow() }
        .task(id: app.dataKey) { data = await load() }
    }

    @ViewBuilder private func content(_ d: HomeData) -> some View {
        if let p = app.profile {
            let cw = app.backend.continueWatching(profile: p)
            if !cw.isEmpty {
                PosterRail(title: "Continua a guardare", cards: cw, width: 128, action: { app.resume($0) })
            }
        }
        if !d.onAir.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Canali in onda ora") { go(.live) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(d.onAir, id: \.channel.key) { item in
                            Button { app.playLive(item.channel.key, among: d.liveKeys) } label: { OnAirTile(channel: item.channel, now: item.now) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        ForEach(Array(d.movies.enumerated()), id: \.element.id) { i, r in
            PosterRail(title: i == 0 ? "Film del momento" : r.title, cards: r.items, seeAll: { go(.movies) })
        }
        ForEach(Array(d.series.enumerated()), id: \.element.id) { i, r in
            PosterRail(title: i == 0 ? "Serie TV del momento" : r.title, cards: r.items, seeAll: { go(.series) })
        }
        if !d.hasAnything {
            if app.libraryReady || app.liveReady {
                EmptyState(icon: "checklist", title: "Scegli cosa guardare",
                           message: "Il tuo profilo è ancora vuoto. Scegli i canali consigliati, oppure sfoglia le categorie della tua lista.",
                           action: "Scegli i contenuti") { app.setupProfile = app.profile }
                    .frame(maxWidth: .infinity)
            } else {
                RailSkeleton(title: "Film del momento")
            }
        } else if !app.libraryReady {
            HStack(spacing: 10) { ProgressView().tint(.white); Text("Carico film e serie…").font(.system(size: 13)).foregroundStyle(Theme.secondaryText) }
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var expiryNotice: some View {
        if let s = app.sources.filter({ $0.expTs > 0 }).min(by: { $0.expTs < $1.expTs }) {
            let days = Int((Double(s.expTs) - Date().timeIntervalSince1970) / 86400)
            if days <= 14 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.gold)
                    Text(days < 0 ? "L'abbonamento «\(s.name)» è scaduto il \(s.expires)." : "L'abbonamento «\(s.name)» scade il \(s.expires) (tra \(max(days, 0)) giorni).")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(12).glass(radius: 14).padding(.horizontal, 16)
            }
        }
    }

    private func load() async -> HomeData {
        guard let p = app.profile else { return HomeData() }
        let b = app.backend
        return await Task.detached(priority: .userInitiated) { () -> HomeData in
            var d = HomeData()
            let live = b.liveList(profile: p)
            d.liveKeys = live.map { $0.key }
            let ordered = live.filter { $0.fav } + live.filter { !$0.fav }
            let nn = b.nowNext(keys: ordered.prefix(80).map { $0.key })
            let withGuide = ordered.prefix(80).filter { nn[$0.key]?.now != nil }
            let pick = Array((withGuide + ordered.filter { nn[$0.key]?.now == nil }).prefix(24))
            d.onAir = pick.map { ($0, nn[$0.key]?.now) }
            let m = b.vodRows(profile: p, kind: .movie, per: 20, limit: 4)
            let s = b.vodRows(profile: p, kind: .series, per: 20, limit: 3)
            // the first row of films is "of the moment", then the best rated; series: the first row
            var movieRows: [Row] = []
            if let first = m.rows.first { movieRows.append(first) }
            if let top = m.rows.first(where: { $0.rowId == "top" }), top.id != m.rows.first?.id { movieRows.append(top) }
            d.movies = movieRows
            d.series = s.rows.first.map { [$0] } ?? []
            let candidates = (m.rows.first(where: { $0.rowId == "trend" || $0.rowId == "top" }) ?? m.rows.first)?.items.filter { $0.logo != nil } ?? []
            if !candidates.isEmpty {
                let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
                d.hero = candidates[day % min(candidates.count, 6)]
            } else if let sr = s.rows.first?.items.first(where: { $0.logo != nil }) { d.hero = sr }
            d.hasAnything = !p.live.isEmpty || !p.movies.isEmpty || !p.series.isEmpty
            return d
        }.value
    }
}

struct HeroSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 0).fill(Color.white.opacity(0.06)).aspectRatio(0.86, contentMode: .fit).modifier(Shimmer()).clipped()
    }
}

/// The big title at the top of the home page.
struct HeroCard: View {
    @EnvironmentObject var app: AppModel
    let card: Card

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(card.logo, title: card.name, maxPixel: 1000)
                .aspectRatio(0.86, contentMode: .fill)
                .clipped()
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.55), Theme.ink], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(card.kind == .series ? "SERIE TV" : "FILM").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.cyan)
                    if card.rate > 0 { RatingBadge(value: card.rate) }
                }
                Text(card.title).font(.system(size: 30, weight: .heavy)).lineLimit(2).shadow(color: .black.opacity(0.6), radius: 8)
                HStack(spacing: 10) {
                    if card.kind == .movie {
                        Button { app.play(.movie(key: card.key, resume: card.progress)) } label: {
                            Label(card.progress > 0 ? "Riprendi" : "Riproduci", systemImage: "play.fill")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                    }
                    NavigationLink(value: card) { Label("Dettagli", systemImage: "info.circle") }.buttonStyle(GlassButtonStyle())
                }
            }
            .padding(18)
        }
        .aspectRatio(0.86, contentMode: .fit)
        .clipped()
    }
}
