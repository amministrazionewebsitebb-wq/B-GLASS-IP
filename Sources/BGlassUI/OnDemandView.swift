import BGlassCore
import SwiftUI

/// Films and series: a shop window on top, then rows by genre of the whole catalogue.
struct OnDemandView: View {
    @EnvironmentObject var app: AppModel
    @State private var kind = Kind.movie
    @State private var rows: [Row] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false

    private struct LoadKey: Equatable { var data: DataKey; var kind: Kind }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                PillPicker(items: [(Kind.movie, "Film"), (Kind.series, "Serie TV")], selection: $kind)
                LoadingBanner()
                if !loaded {
                    RailSkeleton(); RailSkeleton(); RailSkeleton()
                } else if rows.isEmpty {
                    EmptyState(icon: kind == .movie ? "film" : "rectangle.stack",
                               title: app.libraryReady ? (kind == .movie ? "Nessun film nella lista" : "Nessuna serie nella lista") : "Carico il catalogo…",
                               message: app.libraryReady ? "La tua lista non contiene questa parte, oppure va aggiornata." : "")
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    let featured = (rows.first { $0.rowId == "trend" || $0.rowId == "top" } ?? rows[0]).items.filter { $0.logo != nil }.prefix(6)
                    if !featured.isEmpty { HeroCarousel(cards: Array(featured)) }
                    ForEach(rows) { r in
                        PosterRail(title: r.title, cards: r.items,
                                   route: r.cats != nil ? CategoryRoute(title: r.title, kind: kind, cats: r.cats ?? [], genre: r.genre) : nil)
                            .onAppear { if r.id == rows.last?.id { Task { await more() } } }
                    }
                    if loadingMore { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                }
                Color.clear.frame(height: 20)
            }
            .padding(.top, 4)
        }
        .background(GlassBackground())
        .navigationTitle("On Demand")
        .toolbar { ToolbarItem(placement: .primaryAction) { ProfileMenu() } }
        .refreshable { app.refreshNow() }
        .task(id: LoadKey(data: app.dataKey, kind: kind)) { await reload() }
    }

    private func reload() async {
        guard let p = app.profile else { return }
        let b = app.backend, k = kind
        let r = await Task.detached(priority: .userInitiated) { b.vodRows(profile: p, kind: k, per: 24, offset: 0, limit: 8, all: true) }.value
        rows = r.rows
        total = r.total
        loaded = true
    }

    private func more() async {
        guard !loadingMore, rows.count < total, let p = app.profile else { return }
        loadingMore = true
        let b = app.backend, k = kind, off = rows.count
        let r = await Task.detached(priority: .userInitiated) { b.vodRows(profile: p, kind: k, per: 24, offset: off, limit: 6, all: true) }.value
        rows += r.rows.filter { x in !rows.contains { $0.id == x.id } }
        loadingMore = false
    }
}

/// "See all" for a row: every title of a category (or genre) in a grid, paged as you scroll.
struct CategoryGridView: View {
    @EnvironmentObject var app: AppModel
    let route: CategoryRoute
    @State private var cards: [Card] = []
    @State private var total = 0
    @State private var busy = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 10, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(cards) { c in
                    NavigationLink(value: c) { PosterCard(card: c, width: 104) }.buttonStyle(.plain)
                        .onAppear { if c.id == cards.last?.id { Task { await load() } } }
                }
            }
            .padding(16)
            if busy { ProgressView().tint(.white).padding() }
        }
        .background(GlassBackground())
        .navigationTitle(route.title)
        .inlineTitle()
        .task { await load() }
    }

    private func load() async {
        guard !busy, cards.isEmpty || cards.count < total, let p = app.profile else { return }
        busy = true
        let b = app.backend, off = cards.count, r = route
        let page = await Task.detached(priority: .userInitiated) {
            b.vodItems(profile: p, kind: r.kind, cats: r.cats.isEmpty ? nil : r.cats, genre: r.genre, offset: off, limit: 60, all: true)
        }.value
        total = page.total
        cards += page.items
        busy = false
    }
}
