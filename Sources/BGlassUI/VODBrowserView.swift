import BGlassCore
import SwiftUI

/// The films or series page: Netflix-style rows by genre, built from the viewer's own selection.
struct VODBrowserView: View {
    @EnvironmentObject var app: AppModel
    let kind: Kind
    @State private var rows: [Row] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false

    private var title: String { kind == .movie ? "Film" : "Serie TV" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                LoadingBanner()
                if !loaded {
                    RailSkeleton(title: "In evidenza"); RailSkeleton(); RailSkeleton()
                } else if rows.isEmpty {
                    emptyState.frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    if let hero = heroCard { HeroCard(card: hero) }
                    ForEach(rows) { r in
                        PosterRail(title: r.title, cards: r.items,
                                   route: r.cats != nil ? CategoryRoute(title: r.title, kind: kind, cats: r.cats ?? [], genre: r.genre) : nil)
                            .onAppear { if r.id == rows.last?.id { Task { await more() } } }
                    }
                    if loadingMore { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(GlassBackground())
        .navigationTitle(title)
        .toolbar { ToolbarItem(placement: .primaryAction) { ProfileMenu() } }
        .refreshable { app.refreshNow() }
        .task(id: app.dataKey) { await reload() }
    }

    private var heroCard: Card? {
        let r = rows.first { $0.rowId == "trend" || $0.rowId == "top" } ?? rows.first
        return r?.items.first { $0.logo != nil }
    }

    @ViewBuilder private var emptyState: some View {
        if !app.libraryReady {
            VStack(spacing: 12) { ProgressView().tint(.white); Text("Carico \(kind == .movie ? "i film" : "le serie")…").foregroundStyle(Theme.secondaryText) }
        } else if (app.profile?.set(kind).isEmpty ?? true) {
            EmptyState(icon: kind == .movie ? "film" : "rectangle.stack", title: kind == .movie ? "Nessun film nel profilo" : "Nessuna serie nel profilo",
                       message: "Scegli le categorie che ti interessano: vedrai solo quelle, in righe per genere.",
                       action: "Scegli i contenuti") { app.setupProfile = app.profile }
        } else {
            EmptyState(icon: "magnifyingglass", title: "Niente da mostrare", message: "I contenuti scelti non sono più nella lista. Prova ad aggiornarla.")
        }
    }

    private func reload() async {
        guard let p = app.profile else { return }
        let b = app.backend, k = kind
        let r = await Task.detached(priority: .userInitiated) { b.vodRows(profile: p, kind: k, per: 24, offset: 0, limit: 8) }.value
        rows = r.rows
        total = r.total
        loaded = true
    }

    private func more() async {
        guard !loadingMore, rows.count < total, let p = app.profile else { return }
        loadingMore = true
        let b = app.backend, k = kind, off = rows.count
        let r = await Task.detached(priority: .userInitiated) { b.vodRows(profile: p, kind: k, per: 24, offset: off, limit: 6) }.value
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

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
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
        let page = await Task.detached(priority: .userInitiated) { b.vodItems(profile: p, kind: r.kind, cats: r.cats.isEmpty ? nil : r.cats, genre: r.genre, offset: off, limit: 60) }.value
        total = page.total
        cards += page.items
        busy = false
    }
}
