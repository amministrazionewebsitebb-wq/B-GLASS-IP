import BGlassCore
import SwiftUI

struct HomeData {
    var featured: [Card] = []
    var onAir: [(channel: LiveChannel, now: Prog?)] = []
    var onAirKeys: [String] = []
    var movies: [Row] = []
    var series: [Row] = []
}

/// What makes a screen rebuild its rows.
struct DataKey: Equatable {
    var content: Int
    var guide: Int
    var profile: String
    var ready: Bool
    var live: Bool
}

extension AppModel {
    var dataKey: DataKey { DataKey(content: contentRevision, guide: guideRevision, profile: profile?.id ?? "", ready: libraryReady, live: liveReady) }

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
            VStack(alignment: .leading, spacing: 28) {
                header
                LoadingBanner()
                expiryNotice
                if let d = data {
                    if !d.featured.isEmpty { HeroCarousel(cards: d.featured) }
                    content(d)
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.surface).aspectRatio(1.45, contentMode: .fit).modifier(Shimmer())
                        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                    RailSkeleton(title: "In onda ora")
                }
                Color.clear.frame(height: 20)
            }
        }
        .background(GlassBackground())
        .hideNavBar()
        .refreshable { app.refreshNow() }
        .task(id: app.dataKey) { data = await load() }
    }

    private var header: some View {
        HStack {
            Wordmark(size: 24)
            Spacer()
            ProfileMenu()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder private func content(_ d: HomeData) -> some View {
        if !d.onAir.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "In onda ora") { go(.live) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(d.onAir, id: \.channel.key) { item in
                            Button { app.playLive(item.channel.key) } label: { LiveTile(channel: item.channel, now: item.now) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        if let p = app.profile {
            let cw = app.backend.continueWatching(profile: p)
            if !cw.isEmpty { PosterRail(title: "Continua a guardare", cards: cw, width: 120, action: { app.resume($0) }) }
            let mine = app.backend.myList(profile: p)
            if !mine.isEmpty { PosterRail(title: "La mia lista", cards: mine) }
        }
        ForEach(Array(d.movies.enumerated()), id: \.element.id) { i, r in
            PosterRail(title: i == 0 ? "Film del momento" : r.title, cards: r.items, seeAll: { go(.ondemand) })
        }
        ForEach(Array(d.series.enumerated()), id: \.element.id) { i, r in
            PosterRail(title: i == 0 ? "Serie TV del momento" : r.title, cards: r.items, seeAll: { go(.ondemand) })
        }
        if !app.libraryReady && d.movies.isEmpty {
            HStack(spacing: 10) { ProgressView().tint(.white); Text("Carico film e serie…").font(.system(size: 14)).foregroundStyle(Theme.secondaryText) }
                .padding(.horizontal, 16)
        } else if d.onAir.isEmpty && d.movies.isEmpty && d.series.isEmpty && app.libraryReady {
            EmptyState(icon: "tv", title: "La lista è vuota", message: "Controlla la lista nelle impostazioni o aggiornala.", action: "Impostazioni") { app.showSettings = true }
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var expiryNotice: some View {
        if let s = app.sources.filter({ $0.expTs > 0 }).min(by: { $0.expTs < $1.expTs }) {
            let days = Int((Double(s.expTs) - Date().timeIntervalSince1970) / 86400)
            if days <= 10 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.gold)
                    Text(days < 0 ? "L'abbonamento «\(s.name)» è scaduto." : "L'abbonamento «\(s.name)» scade tra \(max(days, 0)) giorni (\(s.expires)).")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(12).glass(radius: 12).padding(.horizontal, 16)
            }
        }
    }

    private func load() async -> HomeData {
        guard let p = app.profile else { return HomeData() }
        let b = app.backend
        return await Task.detached(priority: .userInitiated) { () -> HomeData in
            var d = HomeData()
            // channels: favourites first, then the main ones; those with a guide in front
            var seen = Set<String>()
            let pool = (b.channels(.favorites, profile: p) + b.channels(.main, profile: p)).filter { seen.insert($0.key).inserted }
            let first = Array((pool.isEmpty ? Array(b.channels(.all, profile: p).prefix(30)) : pool).prefix(30))
            let nn = b.nowNext(keys: first.map { $0.key })
            d.onAir = (first.filter { nn[$0.key]?.now != nil } + first.filter { nn[$0.key]?.now == nil }).prefix(16).map { ($0, nn[$0.key]?.now) }
            d.onAirKeys = d.onAir.map { $0.channel.key }
            let m = b.vodRows(profile: p, kind: .movie, per: 20, limit: 3, all: true)
            let s = b.vodRows(profile: p, kind: .series, per: 20, limit: 2, all: true)
            var movieRows: [Row] = []
            if let first = m.rows.first { movieRows.append(first) }
            if let top = m.rows.first(where: { $0.rowId == "top" }), top.id != m.rows.first?.id { movieRows.append(top) }
            d.movies = movieRows
            d.series = s.rows.first.map { [$0] } ?? []
            // the carousel: what is trending, with artwork, films and series mixed
            let films = (m.rows.first(where: { $0.rowId == "trend" || $0.rowId == "top" }) ?? m.rows.first)?.items.filter { $0.logo != nil } ?? []
            let shows = s.rows.first?.items.filter { $0.logo != nil } ?? []
            var mixed: [Card] = []
            for i in 0..<6 {
                if i < films.count { mixed.append(films[i]) }
                if i < shows.count && mixed.count < 6 { mixed.append(shows[i]) }
                if mixed.count >= 6 { break }
            }
            d.featured = Array(mixed.prefix(6))
            return d
        }.value
    }
}

/// The big titles at the top of the home page (and of On Demand), swiping sideways.
struct HeroCarousel: View {
    @EnvironmentObject var app: AppModel
    let cards: [Card]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 10) {
            #if os(iOS)
            TabView(selection: $index) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in HeroCard(card: c).tag(i) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: heroHeight)
            #else
            if let c = cards.first { HeroCard(card: c).frame(height: heroHeight) }
            #endif
            if cards.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<cards.count, id: \.self) { i in
                        Capsule().fill(i == index ? Color.white : Color.white.opacity(0.3)).frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: index)
            }
        }
        .task(id: cards.map { $0.key }) {
            // turns by itself, like a shop window
            while !Task.isCancelled && cards.count > 1 {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % cards.count }
            }
        }
    }

    private var heroHeight: CGFloat {
        #if os(iOS)
        return min(UIScreen.main.bounds.width, 500) * 0.72
        #else
        return 280
        #endif
    }
}

struct HeroCard: View {
    @EnvironmentObject var app: AppModel
    let card: Card
    @State private var backdrop: String?
    @State private var meta = ""

    var body: some View {
        NavigationLink(value: card) {
            ZStack(alignment: .bottomLeading) {
                art
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.kind == .series ? "SERIE TV" : "FILM").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.sky)
                    Text(card.title).font(.system(size: 26, weight: .heavy)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if card.rate > 0 { RatingBadge(value: card.rate) }
                        if !meta.isEmpty { Text(meta).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                    }
                    HStack(spacing: 10) {
                        Button {
                            if card.kind == .movie { app.play(.movie(key: card.key, resume: card.progress)) } else { app.watchSeries(card) }
                        } label: { Label(card.progress > 0 ? "Riprendi" : "Guarda", systemImage: "play.fill").padding(.horizontal, 6) }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                        MyListButton(key: card.key)
                    }
                    .padding(.top, 2)
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .task(id: card.key) {
            if let d = await app.backend.vodDetails(card.key) {
                if !d.backdrop.isEmpty { backdrop = d.backdrop }
                meta = [d.year, d.genre.split(separator: ",").first.map { String($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            }
        }
    }

    @ViewBuilder private var art: some View {
        if let b = backdrop {
            RemoteImage(b, title: card.name, maxPixel: 1200).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        } else {
            // only a portrait poster: blurred behind, sharp on the right
            ZStack(alignment: .trailing) {
                RemoteImage(card.logo, title: card.name, maxPixel: 500).blur(radius: 26).opacity(0.75).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                RemoteImage(card.logo, title: card.name, maxPixel: 600)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
                    .padding(.vertical, 18).padding(.trailing, 18)
            }
        }
    }
}

/// "+" / "✓" for La mia lista.
struct MyListButton: View {
    @EnvironmentObject var app: AppModel
    let key: String
    var body: some View {
        let on = app.backend.inMyList(app.profile, key)
        Button {
            guard let p = app.profile else { return }
            let now = app.backend.toggleMyList(p.id, key: key)
            app.refreshProfileSnapshot()
            Haptics.tap()
            app.show(now ? "Aggiunto a La mia lista" : "Tolto da La mia lista")
        } label: { Image(systemName: on ? "checkmark" : "plus") }
            .buttonStyle(IconButtonStyle(size: 48))
    }
}
