import BGlassCore
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""
    @State private var everything = false
    @State private var results = SearchResults()
    @State private var searched = false

    private struct Key: Equatable { var text: String; var everything: Bool; var content: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("", selection: $everything) {
                    Text("I miei contenuti").tag(false)
                    Text("Tutta la lista").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                if Hash.fold(text).trimmed.unicodeScalars.count < 3 {
                    EmptyState(icon: "magnifyingglass", title: "Cerca in B-Glass",
                               message: everything ? "Cerca in tutta la lista del provider e aggiungi i titoli al tuo profilo." : "Scrivi almeno tre lettere per cercare tra i tuoi canali, film e serie.")
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else if searched && results.isEmpty {
                    EmptyState(icon: "questionmark.circle", title: "Nessun risultato", message: everything ? "Nemmeno nella lista intera." : "Prova «Tutta la lista» per cercare anche fuori dal tuo profilo.")
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    if !results.movies.isEmpty { PosterRail(title: "Film (\(results.moviesTotal))", cards: results.movies) }
                    if !results.series.isEmpty { PosterRail(title: "Serie TV (\(results.seriesTotal))", cards: results.series) }
                    if !results.live.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Canali (\(results.liveTotal))")
                            LazyVStack(spacing: 8) {
                                ForEach(results.live.prefix(40)) { c in
                                    Button { app.playLive(c.key, among: results.live.map { $0.key }) } label: {
                                        HStack(spacing: 12) {
                                            ChannelLogo(channel: c.name, logo: c.logo)
                                            Text(c.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                            Spacer()
                                            if !(app.profile?.live.contains(c.key) ?? false) {
                                                Button { add(c) } label: { Image(systemName: "plus.circle").font(.system(size: 22)).foregroundStyle(Theme.cyan) }.buttonStyle(.plain)
                                            }
                                        }
                                        .padding(10).glass(radius: 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
            .padding(.top, 6)
        }
        .background(GlassBackground())
        .navigationTitle("Cerca")
        .toolbar { ToolbarItem(placement: .primaryAction) { ProfileMenu() } }
        .searchable(text: $text, prompt: "Film, serie, canali")
        .task { let b = app.backend; await Task.detached(priority: .utility) { b.warmSearch() }.value }
        .task(id: Key(text: text, everything: everything, content: app.contentRevision)) { await run() }
    }

    private func run() async {
        guard let p = app.profile else { return }
        if Hash.fold(text).trimmed.unicodeScalars.count < 3 { results = SearchResults(); searched = false; return }
        try? await Task.sleep(nanoseconds: 260_000_000)                       // wait for the end of the typing
        if Task.isCancelled { return }
        let b = app.backend, q = text, all = everything
        results = await Task.detached(priority: .userInitiated) { b.search(q, profile: p, everything: all) }.value
        searched = true
    }

    private func add(_ c: Card) {
        guard let p = app.profile else { return }
        app.backend.select(p.id, kind: .live, keys: [c.key], on: true)
        app.reloadProfile()
        Haptics.tap()
        app.show("«\(c.name)» aggiunto al tuo profilo")
    }
}
