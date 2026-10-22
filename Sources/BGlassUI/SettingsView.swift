import BGlassCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var addingList = false
    @State private var editingList: Source?
    @State private var editor: ProfileEditorTarget?
    @State private var removing: Source?
    @State private var askPin = false
    @State private var setPin = false

    var body: some View {
        NavigationStack {
            List {
                Section("Le mie liste") {
                    ForEach(app.sources) { s in sourceRow(s) }
                    Button { addingList = true } label: { Label("Aggiungi una lista", systemImage: "plus.circle") }
                    if !app.sources.isEmpty {
                        NavigationLink { SubscriptionView() } label: { Label("Abbonamento e scadenza", systemImage: "calendar.badge.clock") }
                    }
                }

                Section("Profili") {
                    ForEach(app.profiles) { p in
                        Button { editor = .edit(p) } label: {
                            HStack(spacing: 12) {
                                Avatar(name: p.name, color: p.color, size: 32)
                                Text(p.name).font(.system(size: 16, weight: .semibold))
                                Spacer()
                                if app.profile?.id == p.id { Text("In uso").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cyan) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { editor = .new } label: { Label("Aggiungi un profilo", systemImage: "plus.circle") }
                }

                Section("Guida TV") { guideRows }

                Section {
                    playbackRows
                } header: { Text("Riproduzione") } footer: {
                    Text(Engines.vlcAvailable ? "Con «Automatico» B·Glass usa il lettore Apple e passa da solo a VLC quando un canale non parte." : "Questa versione non include VLC: alcuni flussi MKV o MPEG-TS potrebbero non aprirsi.")
                }

                Section {
                    Toggle(isOn: Binding(get: { app.flag("showAdult", false) }, set: { adultTapped($0) })) {
                        Label("Contenuti per adulti", systemImage: "eye.slash")
                    }
                } footer: { Text("Restano nascosti nei profili bambini. Per mostrarli serve un PIN.") }

                Section {
                    NavigationLink { NetworkView() } label: { Label("Test della connessione", systemImage: "speedometer") }
                    NavigationLink { AboutView() } label: { Label("Informazioni", systemImage: "info.circle") }
                    NavigationLink { DiagnosticsView() } label: { Label("Registro tecnico", systemImage: "doc.text.magnifyingglass") }
                }
            }
            .groupedList()
            .background(GlassBackground())
            .navigationTitle("Impostazioni")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .sheet(isPresented: $addingList) { AddListView() }
            .sheet(item: $editingList) { s in AddListView(editing: s) }
            .sheet(item: $editor) { t in ProfileEditorView(target: t) }
            .sheet(isPresented: $askPin) {
                PinEntry(title: "PIN", subtitle: "Inserisci il PIN per mostrare i contenuti per adulti.", onDone: { pin in
                    if hashed(pin) == app.setting("expertPin", "") { app.set("showAdult", flag: true); askPin = false; return true }
                    return false
                }, onCancel: { askPin = false })
            }
            .sheet(isPresented: $setPin) {
                PinEntry(title: "Scegli un PIN", subtitle: "4 cifre: servirà per mostrare i contenuti per adulti.", onDone: { pin in
                    app.set("expertPin", hashed(pin)); app.set("showAdult", flag: true); setPin = false; return true
                }, onCancel: { setPin = false })
            }
            .confirmationDialog("Eliminare «\(removing?.name ?? "")»?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Elimina la lista", role: .destructive) { if let s = removing { app.removeSource(s.id) }; removing = nil }
            } message: { Text("Canali, film e serie di questa lista spariranno dall'app.") }
        }
        .preferredColorScheme(.dark)
    }

    private func hashed(_ pin: String) -> String { Hash.fnv("bglass-expert|" + pin) }

    private func adultTapped(_ on: Bool) {
        if !on { app.set("showAdult", flag: false); return }
        if app.setting("expertPin", "").isEmpty { setPin = true } else { askPin = true }
    }

    // MARK: lists

    @ViewBuilder private func sourceRow(_ s: Source) -> some View {
        let info = app.refreshes[s.id]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: s.type == .xtream ? "server.rack" : "link").foregroundStyle(Theme.cyan)
                Text(s.name).font(.system(size: 16, weight: .semibold))
                Spacer()
                if info?.running == true { ProgressView().tint(.white) }
                else if !s.status.isEmpty || info?.error != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold) }
            }
            Text("\(s.nLive) canali · \(s.nMovies) film · \(s.nSeries) serie").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            if let i = info, i.running { Text(i.text).font(.system(size: 12)).foregroundStyle(Theme.cyan) }
            else if let e = info?.error ?? (s.status.isEmpty ? nil : s.status) { Text(e).font(.system(size: 12)).foregroundStyle(Theme.gold) }
            else { Text(s.updated > 0 ? "Aggiornata il \(TimeText.date(ms: s.updated))" : "Mai caricata").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText) }
            HStack(spacing: 8) {
                if info?.running == true { smallButton("Annulla", "xmark") { app.cancelRefresh(s.id) } }
                else { smallButton("Aggiorna", "arrow.clockwise") { app.refresh(s.id) } }
                smallButton("Modifica", "pencil") { editingList = s }
                smallButton("Elimina", "trash") { removing = s }
            }
        }
        .padding(.vertical, 4)
    }

    private func smallButton(_ text: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: guide

    @ViewBuilder private var guideRows: some View {
        HStack {
            Label("Ultimo aggiornamento", systemImage: "calendar")
            Spacer()
            Text(app.backend.epg.updated > 0 ? TimeText.date(ms: app.backend.epg.updated) : "Mai")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
        }
        Button { app.refreshGuide() } label: {
            HStack { Label("Aggiorna ora", systemImage: "arrow.clockwise"); Spacer(); if app.guideRefreshing { ProgressView().tint(.white) } }
        }
        .disabled(app.guideRefreshing)
    }

    // MARK: playback

    @ViewBuilder private var playbackRows: some View {
        Picker("Lingua dell'audio", selection: Binding(get: { app.setting("audioLang", "ita") }, set: { app.set("audioLang", $0) })) {
            Text("Italiano").tag("ita"); Text("Inglese").tag("eng"); Text("Spagnolo").tag("spa"); Text("Francese").tag("fra"); Text("Tedesco").tag("deu"); Text("Originale").tag("auto")
        }
        Picker("Sottotitoli", selection: Binding(get: { app.setting("subLang", "off") }, set: { app.set("subLang", $0) })) {
            Text("Spenti").tag("off"); Text("Italiano").tag("ita"); Text("Inglese").tag("eng")
        }
        Picker("Lettore", selection: Binding(get: { app.setting("engine", "auto") }, set: { app.set("engine", $0) })) {
            Text("Automatico").tag("auto")
            Text("Apple").tag("av")
            if Engines.vlcAvailable { Text("VLC").tag("vlc") }
        }
        Picker("Stabilità", selection: Binding(get: { app.setting("buffer", "normal") }, set: { app.set("buffer", $0) })) {
            Text("Avvio rapido").tag("min"); Text("Normale").tag("normal"); Text("Linea lenta").tag("high")
        }
    }
}

// MARK: subscription

struct SubscriptionView: View {
    @EnvironmentObject var app: AppModel
    @State private var checking: Int?
    @State private var messages: [Int: String] = [:]

    var body: some View {
        List {
            ForEach(app.sources) { s in
                Section(s.name) {
                    row("Scadenza", s.expires.isEmpty ? "—" : s.expires)
                    if s.expTs > 0 {
                        let days = Int((Double(s.expTs) - Date().timeIntervalSince1970) / 86400)
                        row("Giorni rimasti", days < 0 ? "scaduto" : "\(days)")
                    }
                    row("Connessioni", s.maxConn.isEmpty ? "—" : "\(s.activeConn.isEmpty ? "?" : s.activeConn) in uso su \(s.maxConn)")
                    Button { check(s) } label: { HStack { Label("Controlla ora", systemImage: "arrow.clockwise"); Spacer(); if checking == s.id { ProgressView().tint(.white) } } }
                    if let m = messages[s.id] { Text(m).font(.system(size: 12)).foregroundStyle(Theme.secondaryText) }
                }
            }
            if app.sources.isEmpty { Text("Nessuna lista.") }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle("Abbonamento")
        .inlineTitle()
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(Theme.secondaryText) }
    }

    private func check(_ s: Source) {
        checking = s.id
        Task {
            do {
                let behind = Backend.xtreamBehind(s)
                if s.type != .xtream && behind == nil { messages[s.id] = "Le liste M3U non hanno informazioni sull'abbonamento."; checking = nil; return }
                let a = behind == nil ? try await app.backend.account(s) : try await app.backend.accountVia(s, api: behind!)
                messages[s.id] = a.ok ? "Account \(a.status.lowercased())" : (a.message.isEmpty ? "Account non valido" : a.message)
                app.reloadSources()
            } catch { messages[s.id] = Net.explain(error) }
            checking = nil
        }
    }
}

// MARK: network and speed

struct NetworkView: View {
    @EnvironmentObject var app: AppModel
    @State private var running = false
    @State private var stage = ""
    @State private var live = 0.0
    @State private var result: SpeedResult?
    @State private var measureStream = false
    @State private var sourceId: Int = -1
    @State private var publicIP: String?
    @State private var test: SpeedTest?
    @State private var addresses: [(name: String, ip: String)] = []

    var body: some View {
        List {
            Section("Collegamento") {
                ForEach(Array(addresses.enumerated()), id: \.offset) { _, a in
                    HStack { Text(a.name); Spacer(); Text(a.ip).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondaryText) }
                }
                if addresses.isEmpty { Text("Nessun collegamento attivo.") }
                HStack {
                    Text("IP pubblico")
                    Spacer()
                    if let ip = publicIP { Text(ip).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondaryText) }
                    else { Button("Mostra") { Task { publicIP = try? await Net.string("https://api.ipify.org") } } }
                }
            }
            Section("Speed test") {
                if app.sources.count > 0 {
                    Picker("Lista da misurare", selection: $sourceId) {
                        Text("Solo la mia linea").tag(-1)
                        ForEach(app.sources) { Text($0.name).tag($0.id) }
                    }
                    if sourceId >= 0 { Toggle("Misura anche un film di prova", isOn: $measureStream) }
                }
                if running {
                    VStack(spacing: 6) {
                        Text(String(format: stage == "Tempo di risposta" ? "%.0f ms" : (stage == "Il tuo fornitore" && live > 1000 ? "%.0f ms" : "%.1f Mbit/s"), live)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text(stage).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        ProgressView().tint(.white)
                    }
                    .frame(maxWidth: .infinity)
                    Button("Interrompi", role: .destructive) { test?.cancel() }
                } else {
                    Button { start() } label: { Label(result == nil ? "Avvia il test" : "Ripeti il test", systemImage: "play.fill") }
                }
            }
            if let r = result { resultSection(r) }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle("Connessione")
        .inlineTitle()
        .task { addresses = NetInfo.addresses() }
    }

    @ViewBuilder private func resultSection(_ r: SpeedResult) -> some View {
        Section("Risultato: \(r.grade.rawValue)") {
            metric("Download", String(format: "%.1f Mbit/s", r.downMbps))
            metric("Upload", r.upMbps > 0 ? String(format: "%.1f Mbit/s", r.upMbps) : "—")
            metric("Tempo di risposta", String(format: "%.0f ms", r.pingMs))
            metric("Variazione (jitter)", String(format: "%.0f ms", r.jitterMs))
            if let p = r.panelMs { metric("Pannello del fornitore", String(format: "%.0f ms", p)) }
            if let s = r.streamMbps { metric("Film di prova", String(format: "%.1f Mbit/s", s)) }
            if !r.formats.isEmpty { metric("Formati sostenibili", r.formats.joined(separator: ", ")) }
        }
        Section("Consigli") { ForEach(r.advice, id: \.self) { Text($0).font(.system(size: 14)) } }
    }

    private func metric(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(Theme.secondaryText).monospacedDigit() } }

    private func start() {
        running = true
        result = nil
        let t = SpeedTest()
        test = t
        let source = app.source(sourceId)
        let b = app.backend, ms = measureStream
        Task {
            let r = await t.run(provider: source, measureStream: ms, backend: b) { st, v in
                Task { @MainActor in stage = st.rawValue; live = v }
            }
            result = r
            running = false
        }
    }
}

enum NetInfo {
    /// The addresses of the active network interfaces (Wi-Fi, mobile data, VPN).
    static func addresses() -> [(name: String, ip: String)] {
        var out: [(String, String)] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let sa = a.pointee.ifa_addr, a.pointee.ifa_flags & UInt32(IFF_UP) != 0, a.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let fam = Int32(sa.pointee.sa_family)
            guard fam == AF_INET || fam == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if ip.hasPrefix("fe80") { continue }
            let n = String(cString: a.pointee.ifa_name)
            let label: String
            if n == "en0" { label = "Wi‑Fi" + (fam == AF_INET6 ? " (IPv6)" : "") }
            else if n.hasPrefix("pdp_ip") { label = "Dati mobili" + (fam == AF_INET6 ? " (IPv6)" : "") }
            else if n.hasPrefix("utun") || n.hasPrefix("ipsec") { label = "VPN" + (fam == AF_INET6 ? " (IPv6)" : "") }
            else if n.hasPrefix("en") { label = "Ethernet/altro" + (fam == AF_INET6 ? " (IPv6)" : "") }
            else { continue }
            out.append((label, ip))
        }
        return out
    }
}

// MARK: technical log

/// What the app asked the servers and what they answered (passwords hidden): to send when a list or a channel does not work.
struct DiagnosticsView: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Se una lista o un canale non funziona, copia questo registro e mandalo a chi ti assiste. Utenti e password sono nascosti.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                Text(text.isEmpty ? "Ancora niente: prova ad aggiornare la lista o ad aprire un canale." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(GlassBackground())
        .navigationTitle("Registro tecnico")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { copy() } label: { Label("Copia", systemImage: "doc.on.doc") }
                    ShareLink(item: report) { Label("Condividi", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { Diag.clear(); text = "" } label: { Label("Svuota", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { text = Diag.text }
    }

    private var report: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var head = "B-Glass \(v) · lettore: \(Engines.vlcAvailable ? "AVPlayer + VLC" : "AVPlayer")\n"
        for s in app.sources {
            head += "Lista «\(s.name)»: \(s.type == .xtream ? "Xtream" : "M3U") \(Net.brief(Diag.mask(s.url))) · \(s.nLive) canali, \(s.nMovies) film, \(s.nSeries) serie"
            head += s.ua.isEmpty ? "" : " · UA \(s.ua)"
            head += s.status.isEmpty ? "\n" : " · \(s.status)\n"
        }
        return head + "\n" + Diag.text
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = report
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
        app.show("Registro copiato")
    }
}

// MARK: about

struct AboutView: View {
    @EnvironmentObject var app: AppModel
    @State private var cache = ""

    var body: some View {
        List {
            Section("B-Glass") {
                row("Versione", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                row("Motore video", Engines.vlcAvailable ? "AVPlayer + VLC" : "AVPlayer")
                row("Titoli in libreria", "\(app.backend.lib.snap.items.count)")
                row("Cache immagini", cache)
                Button("Svuota la cache delle immagini", role: .destructive) {
                    ImageLoader.shared.clearDisk()
                    cache = ByteCountFormatter.string(fromByteCount: Int64(ImageLoader.shared.diskBytes()), countStyle: .file)
                    app.show("Cache svuotata")
                }
            }
            Section("Dispositivo") {
                row("Modello", deviceModel)
                row("Sistema", systemVersion)
                row("Memoria", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                row("Spazio libero", freeSpace)
            }
            Section {
                Text("B-Glass è solo un lettore: non fornisce né include contenuti. Le immagini e i dati dei film arrivano dal tuo fornitore (e da TMDB tramite il suo pannello).")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
        }
        .groupedList()
        .background(GlassBackground())
        .navigationTitle("Informazioni")
        .inlineTitle()
        .onAppear { cache = ByteCountFormatter.string(fromByteCount: Int64(ImageLoader.shared.diskBytes()), countStyle: .file) }
    }

    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(Theme.secondaryText) } }

    private var deviceModel: String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    private var systemVersion: String {
        #if os(iOS)
        return UIDevice.current.systemName + " " + UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private var freeSpace: String {
        let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let b = v?.volumeAvailableCapacityForImportantUsage else { return "—" }
        return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
