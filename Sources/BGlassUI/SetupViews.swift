import BGlassCore
import SwiftUI

/// Choosing what a profile sees: recommended channel packs, or category by category. Opens full screen, right after a profile is created.
struct SetupFlowView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let profileId: String
    @State private var profile: Profile?
    @State private var copyFrom = false

    var body: some View {
        NavigationStack {
            List {
                if !app.refreshes.isEmpty { Section { LoadingBanner().listRowBackground(Color.clear).listRowInsets(EdgeInsets()) } }
                Section {
                    Text("Le liste hanno migliaia di voci e quasi tutte sono inutili. Qui scegli solo quello che vuoi vedere: potrai cambiare idea quando vuoi.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondaryText).listRowBackground(Color.clear)
                }
                Section("Canali TV") {
                    NavigationLink { PacksView(profileId: profileId) } label: {
                        row("sparkles.tv", "Canali consigliati", "Sport, cinema, news, bambini… trovati per nome nella tua lista", badge: "\(profile?.packs.count ?? 0) attivi")
                    }
                    NavigationLink { ContentPickerView(profileId: profileId, kind: .live) } label: {
                        row("tv", "Scegli per categoria", "Sfoglia le categorie dei canali", badge: "\(profile?.live.count ?? 0)")
                    }
                    if (profile?.live.count ?? 0) > 1 {
                        NavigationLink { ChannelOrderView(profileId: profileId) } label: { row("arrow.up.arrow.down", "Ordine dei canali", "Trascina per riordinare", badge: nil) }
                    }
                }
                Section("Film") {
                    NavigationLink { ContentPickerView(profileId: profileId, kind: .movie) } label: {
                        row("film", "Scegli le categorie dei film", "Ogni categoria diventa una riga; i generi si uniscono da soli", badge: "\(profile?.movies.count ?? 0)")
                    }
                }
                Section("Serie TV") {
                    NavigationLink { ContentPickerView(profileId: profileId, kind: .series) } label: {
                        row("rectangle.stack", "Scegli le categorie delle serie", "", badge: "\(profile?.series.count ?? 0)")
                    }
                }
                if app.profiles.count > 1 {
                    Section {
                        Button { copyFrom = true } label: { row("person.2", "Copia da un altro profilo", "Parti dalla scelta di qualcun altro", badge: nil) }
                    }
                }
            }
            .groupedList()
            .background(GlassBackground())
            .navigationTitle("Scegli cosa guardare")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { finish() } } }
            .confirmationDialog("Copia da…", isPresented: $copyFrom, titleVisibility: .visible) {
                ForEach(app.profiles.filter { $0.id != profileId }) { p in
                    Button(p.name) { app.backend.copySelection(from: p.id, to: profileId); refresh(); app.show("Scelta copiata da \(p.name)") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: refresh)
        .interactiveDismissDisabled()
    }

    private func refresh() { profile = app.backend.profiles.get(profileId) }

    private func finish() {
        app.reloadProfile()
        app.backend.warmVariants()
        app.refreshGuide(auto: true)
        dismiss()
    }

    private func row(_ icon: String, _ title: String, _ sub: String, badge: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.cyan).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(Theme.secondaryText) }
            }
            Spacer()
            if let b = badge { Text(b).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cyan) }
        }
    }
}

// MARK: packs

struct PacksView: View {
    @EnvironmentObject var app: AppModel
    let profileId: String
    @State private var packs: [PackInfo] = []
    @State private var channels = 0
    @State private var busy = false

    var body: some View {
        List {
            Section {
                Text("Pacchetti pronti: l'app cerca i canali per nome nella tua lista, preferisce l'HD e salta quelli che non trova. Si aggiornano da soli quando la lista cambia.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).listRowBackground(Color.clear)
                Toggle("Includi i canali 4K", isOn: Binding(get: { app.flag("packs4k", false) }, set: { app.set("packs4k", flag: $0); Task { await reload() } }))
            }
            Section("Pacchetti") {
                ForEach(packs) { p in
                    HStack(spacing: 12) {
                        NavigationLink { PackDetailView(profileId: profileId, group: p.group, title: p.title) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(.system(size: 16, weight: .semibold))
                                Text(p.desc).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                                Text("Trovati \(p.found) su \(p.total)").font(.system(size: 11, weight: .medium)).foregroundStyle(p.found == 0 ? Theme.gold : Theme.cyan)
                            }
                        }
                        Toggle("", isOn: Binding(get: { p.enabled }, set: { toggle(p, $0) })).labelsHidden()
                    }
                }
            }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle("Canali consigliati")
        .inlineTitle()
        .overlay { if busy || packs.isEmpty { ProgressView().tint(.white) } }
        .task { await reload() }
    }

    private func reload() async {
        guard let p = app.backend.profiles.get(profileId) else { return }
        let b = app.backend
        let r = await Task.detached(priority: .userInitiated) { b.packsList(profile: p) }.value
        packs = r
    }

    private func toggle(_ p: PackInfo, _ on: Bool) {
        busy = true
        let b = app.backend, id = profileId
        Task {
            await Task.detached(priority: .userInitiated) { b.setPack(id, group: p.group, on: on) }.value
            await reload()
            busy = false
            Haptics.tap()
            app.refreshGuide(auto: true)
        }
    }
}

struct PackDetailView: View {
    @EnvironmentObject var app: AppModel
    let profileId: String
    let group: String
    let title: String
    @State private var entries: [PackEntryInfo] = []

    var body: some View {
        List(entries) { e in
            HStack(spacing: 10) {
                Image(systemName: e.found ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(e.found ? Theme.cyan : Theme.tertiaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.system(size: 15, weight: .medium))
                    if e.found { Text("\(e.chosen)\(e.quality.isEmpty ? "" : " · \(e.quality)")").font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                    else { Text(e.why).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText) }
                }
                Spacer()
                if e.off { Text("tolto").font(.system(size: 11)).foregroundStyle(Theme.gold) }
            }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle(title)
        .inlineTitle()
        .task {
            guard let p = app.backend.profiles.get(profileId) else { return }
            let b = app.backend, g = group
            entries = await Task.detached { b.packDetail(profile: p, group: g) }.value
        }
    }
}

// MARK: categories

struct ContentPickerView: View {
    @EnvironmentObject var app: AppModel
    let profileId: String
    let kind: Kind
    @State private var cats: [CatInfo] = []
    @State private var query = ""
    @State private var results: [Backend.Brief] = []
    @State private var total = 0
    @State private var picked = Set<String>()
    @State private var loading = true

    private var title: String { kind == .live ? "Canali" : kind == .movie ? "Film" : "Serie TV" }

    var body: some View {
        List {
            if query.trimmed.unicodeScalars.count >= 2 {
                Section {
                    if total > 0 {
                        HStack {
                            Button("Aggiungi tutti (\(total))") { bulkQuery(true) }
                            Spacer()
                            Button("Togli tutti", role: .destructive) { bulkQuery(false) }
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    ForEach(results) { b in ItemToggleRow(brief: b, picked: picked.contains(b.key)) { toggle(b) } }
                    if results.count < total { Text("Altri \(total - results.count) risultati: affina la ricerca.").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText) }
                } header: { Text("\(total) risultati") }
            } else {
                Section {
                    ForEach(cats) { c in
                        HStack(spacing: 12) {
                            Button { toggleAll(c) } label: {
                                Image(systemName: c.selected == 0 ? "circle" : c.selected >= c.count ? "checkmark.circle.fill" : "minus.circle.fill")
                                    .font(.system(size: 24)).foregroundStyle(c.selected == 0 ? Theme.tertiaryText : Theme.cyan)
                            }
                            .buttonStyle(.plain)
                            NavigationLink {
                                CategoryItemsView(profileId: profileId, kind: kind, src: c.src, cat: c.name, title: c.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.label).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                    Text(c.selected > 0 ? "\(c.selected) scelti su \(c.count)" : "\(c.count) titoli").font(.system(size: 12)).foregroundStyle(c.selected > 0 ? Theme.cyan : Theme.secondaryText)
                                }
                            }
                        }
                    }
                } footer: {
                    if cats.isEmpty && !loading { Text("La lista non ha ancora caricato questa parte. Riprova tra poco.").foregroundStyle(Theme.secondaryText) }
                }
            }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle(title)
        .inlineTitle()
        .searchable(text: $query, prompt: "Cerca (es. sky sport, rai)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Seleziona tutte le categorie") { selectEverything(true) }
                    Button("Svuota la scelta", role: .destructive) { selectEverything(false) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .overlay { if loading && cats.isEmpty { ProgressView().tint(.white) } }
        .task { reloadCats() }
        .task(id: query) { await search() }
    }

    private func reloadCats() {
        let p = app.backend.profiles.get(profileId)
        picked = p?.set(kind).keySet ?? []
        cats = app.backend.libCategories(profile: p, kind: kind)
        loading = false
    }

    private func toggleAll(_ c: CatInfo) {
        let on = c.selected < c.count
        app.backend.selectCategory(profileId, kind: kind, src: c.src, cat: c.name, on: on)
        Haptics.tap()
        reloadCats()
    }

    private func selectEverything(_ on: Bool) {
        if on { for c in cats { app.backend.selectCategory(profileId, kind: kind, src: c.src, cat: c.name, on: true) } }
        else { app.backend.clearSelection(profileId, kind: kind) }
        reloadCats()
    }

    private func toggle(_ b: Backend.Brief) {
        let on = !picked.contains(b.key)
        app.backend.select(profileId, kind: kind, keys: [b.key], on: on)
        if on { picked.insert(b.key) } else { picked.remove(b.key) }
        Haptics.tap()
    }

    private func search() async {
        let q = query.trimmed
        if q.unicodeScalars.count < 2 { results = []; total = 0; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        let b = app.backend, p = b.profiles.get(profileId), k = kind
        let r = await Task.detached(priority: .userInitiated) { b.libItems(profile: p, kind: k, query: q, limit: 80) }.value
        results = r.items
        total = r.total
        picked = p?.set(kind).keySet ?? picked
    }

    private func bulkQuery(_ on: Bool) {
        app.backend.selectQuery(profileId, kind: kind, src: -1, cat: nil, query: query.trimmed, on: on)
        app.show(on ? "Aggiunti \(total) risultati" : "Tolti \(total) risultati")
        picked = app.backend.profiles.get(profileId)?.set(kind).keySet ?? picked
        Haptics.success()
    }
}

struct ItemToggleRow: View {
    let brief: Backend.Brief
    let picked: Bool
    let action: () -> Void
    @State private var local: Bool?

    var body: some View {
        let on = local ?? picked
        Button {
            local = !on
            action()
        } label: {
            HStack(spacing: 12) {
                if brief.kind == .live { ChannelLogo(channel: brief.name, logo: brief.logo, width: 48, height: 34) }
                else {
                    RemoteImage(brief.logo, title: brief.name, maxPixel: 120).frame(width: 36, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(brief.name).font(.system(size: 15, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(brief.cat).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 24)).foregroundStyle(on ? Theme.cyan : Theme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: picked) { _ in local = nil }
    }
}

struct CategoryItemsView: View {
    @EnvironmentObject var app: AppModel
    let profileId: String
    let kind: Kind
    let src: Int
    let cat: String
    let title: String
    @State private var items: [Backend.Brief] = []
    @State private var total = 0
    @State private var picked = Set<String>()
    @State private var query = ""
    @State private var busy = false

    var body: some View {
        List {
            Section {
                HStack {
                    Button("Seleziona tutti") { all(true) }
                    Spacer()
                    Button("Deseleziona tutti", role: .destructive) { all(false) }
                }
                .font(.system(size: 14, weight: .semibold))
            }
            Section {
                ForEach(items) { b in
                    ItemToggleRow(brief: b, picked: picked.contains(b.key)) { toggle(b) }
                        .onAppear { if b.id == items.last?.id { Task { await load(reset: false) } } }
                }
            } header: { Text("\(total) titoli") }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle(title)
        .inlineTitle()
        .searchable(text: $query, prompt: "Cerca in questa categoria")
        .task(id: query) { try? await Task.sleep(nanoseconds: 200_000_000); if !Task.isCancelled { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        if busy && !reset { return }
        if !reset && items.count >= total && total > 0 { return }
        busy = true
        let b = app.backend, p = b.profiles.get(profileId), k = kind, s = src, c = cat, q = query
        let off = reset ? 0 : items.count
        let r = await Task.detached(priority: .userInitiated) { b.libItems(profile: p, kind: k, src: s, cat: c, query: q, offset: off, limit: 80) }.value
        total = r.total
        items = reset ? r.items : items + r.items
        picked = p?.set(kind).keySet ?? picked
        busy = false
    }

    private func toggle(_ b: Backend.Brief) {
        let on = !picked.contains(b.key)
        app.backend.select(profileId, kind: kind, keys: [b.key], on: on)
        if on { picked.insert(b.key) } else { picked.remove(b.key) }
        Haptics.tap()
    }

    private func all(_ on: Bool) {
        if query.trimmed.isEmpty { app.backend.selectCategory(profileId, kind: kind, src: src, cat: cat, on: on) }
        else { app.backend.selectQuery(profileId, kind: kind, src: src, cat: cat, query: query.trimmed, on: on) }
        picked = app.backend.profiles.get(profileId)?.set(kind).keySet ?? picked
        Haptics.success()
        Task { await load(reset: true) }
    }
}

// MARK: order

struct ChannelOrderView: View {
    @EnvironmentObject var app: AppModel
    let profileId: String
    @State private var channels: [LiveChannel] = []

    var body: some View {
        List {
            Section {
                HStack {
                    Button("Ordina A–Z") { sort(false) }
                    Spacer()
                    Button("Per categoria") { sort(true) }
                }
                .font(.system(size: 14, weight: .semibold))
            }
            Section {
                ForEach(channels) { c in
                    HStack(spacing: 12) {
                        ChannelLogo(channel: c.name, logo: c.logo, width: 44, height: 32)
                        Text(c.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    }
                }
                .onMove { from, to in
                    channels.move(fromOffsets: from, toOffset: to)
                    app.backend.moveSelected(profileId, kind: .live, from: from, to: to)
                }
                .onDelete { idx in
                    let keys = idx.map { channels[$0].key }
                    channels.remove(atOffsets: idx)
                    app.backend.select(profileId, kind: .live, keys: keys, on: false)
                }
            }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle("Ordine dei canali")
        .inlineTitle()
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .task { load() }
    }

    private func load() {
        guard let p = app.backend.profiles.get(profileId) else { return }
        channels = app.backend.liveList(profile: p)
    }

    private func sort(_ byCat: Bool) {
        app.backend.sortSelected(profileId, kind: .live, byCategory: byCat)
        load()
    }
}
