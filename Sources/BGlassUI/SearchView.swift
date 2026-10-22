import BGlassCore
import SwiftUI

/// One box for everything: channels, films and series of the whole list.
struct SearchView: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""
    @State private var results = SearchResults()
    @State private var searched = false

    private struct Key: Equatable { var text: String; var content: Int }
    private var short: Bool { Hash.fold(text).trimmed.unicodeScalars.count < 3 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if short {
                    recents
                } else if searched && results.isEmpty {
                    EmptyState(icon: "questionmark.circle", title: "Nessun risultato", message: "Controlla come è scritto o prova con meno parole.")
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    if !results.live.isEmpty { channels }
                    if !results.movies.isEmpty { PosterRail(title: "Film", cards: results.movies) }
                    if !results.series.isEmpty { PosterRail(title: "Serie TV", cards: results.series) }
                }
                Color.clear.frame(height: 24)
            }
            .padding(.top, 6)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(GlassBackground())
        .navigationTitle("Cerca")
        .toolbar { ToolbarItem(placement: .primaryAction) { ProfileMenu() } }
        .searchable(text: $text, prompt: "Canali, film, serie")
        .onSubmit(of: .search) { remember(text) }
        .task { let b = app.backend; await Task.detached(priority: .utility) { b.warmSearch() }.value }
        .task(id: Key(text: text, content: app.contentRevision)) { await run() }
    }

    private var channels: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: "Canali")
            LazyVStack(spacing: 0) {
                ForEach(results.live.prefix(12)) { c in
                    Button { remember(text); app.playLive(c.key, among: results.live.map { $0.key }) } label: {
                        HStack(spacing: 12) {
                            ChannelLogo(channel: c.name, logo: c.logo, width: 64, height: 42)
                            Text(c.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var recents: some View {
        let list = recentList
        if list.isEmpty {
            EmptyState(icon: "magnifyingglass", title: "Cerca in B·Glass", message: "Scrivi il nome di un canale, di un film o di una serie.")
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Ricerche recenti").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button("Cancella") { app.set("recentSearches", "") }.font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
                ForEach(list, id: \.self) { q in
                    Button { text = q } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.tertiaryText)
                            Text(q).font(.system(size: 16))
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.system(size: 13)).foregroundStyle(Theme.tertiaryText)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentList: [String] { app.setting("recentSearches", "").split(separator: "\n").map(String.init) }

    private func remember(_ q: String) {
        let t = q.trimmed
        guard t.count >= 3 else { return }
        let list = [t] + recentList.filter { Hash.fold($0) != Hash.fold(t) }
        app.set("recentSearches", list.prefix(8).joined(separator: "\n"))
    }

    private func run() async {
        guard let p = app.profile else { return }
        if short { results = SearchResults(); searched = false; return }
        try? await Task.sleep(nanoseconds: 260_000_000)                       // wait for the end of the typing
        if Task.isCancelled { return }
        let b = app.backend, q = text
        results = await Task.detached(priority: .userInitiated) { b.search(q, profile: p, everything: true) }.value
        searched = true
    }
}
