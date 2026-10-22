import BGlassCore
import SwiftUI

/// Adds (or edits) a list: an Xtream Codes account or an M3U link.
public struct AddListView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private let editing: Source?
    private let onAdded: ((Source) -> Void)?

    @State private var type: SourceType = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var m3u = ""
    @State private var showAdvanced = false
    @State private var wantLive = true
    @State private var wantMovies = true
    @State private var wantSeries = true
    @State private var ua = ""
    @State private var epgUrl = ""
    @State private var insecure = false
    @State private var liveFmt = "auto"
    @State private var busy = false
    @State private var result: (ok: Bool, text: String)?
    @State private var duplicateAsk = false
    @State private var pasted: String?
    @State private var checkFailed = false

    public init(editing: Source? = nil, onAdded: ((Source) -> Void)? = nil) {
        self.editing = editing
        self.onAdded = onAdded
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        Picker("Tipo", selection: $type) {
                            Text("Xtream Codes").tag(SourceType.xtream)
                            Text("Link M3U").tag(SourceType.m3u)
                        }
                        .pickerStyle(.segmented)
                        .disabled(editing != nil)

                        VStack(spacing: 12) {
                            field("Nome (facoltativo)", text: $name, icon: "tag")
                            if type == .xtream {
                                field("Server, ad esempio http://miosito.it:8080", text: $server, icon: "server.rack", url: true)
                                field("Utente", text: $user, icon: "person")
                                field("Password", text: $pass, icon: "key", secure: true)
                            } else {
                                field("Indirizzo della lista (.m3u / .m3u8)", text: $m3u, icon: "link", url: true)
                                if Backend.xtreamBehind(candidateM3U) != nil {
                                    Button { switchToXtream() } label: {
                                        Label("Questo è un link Xtream: usa «Xtream Codes» per un caricamento più veloce", systemImage: "bolt.fill")
                                            .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                                    }
                                    .buttonStyle(.plain).foregroundStyle(Theme.cyan)
                                }
                            }
                        }
                        .padding(14).glass(radius: 20)

                        DisclosureGroup(isExpanded: $showAdvanced) {
                            VStack(spacing: 12) {
                                Toggle("Canali TV", isOn: $wantLive)
                                Toggle("Film", isOn: $wantMovies)
                                Toggle("Serie TV", isOn: $wantSeries)
                                field("User-Agent (lascia vuoto per il predefinito)", text: $ua, icon: "person.crop.rectangle")
                                field("Guida XMLTV (lascia vuoto per automatica)", text: $epgUrl, icon: "calendar", url: true)
                                Toggle("Ignora errori del certificato HTTPS", isOn: $insecure)
                                if type == .xtream {
                                    Picker("Formato dei canali", selection: $liveFmt) {
                                        Text("Automatico").tag("auto"); Text("HLS (m3u8)").tag("m3u8"); Text("MPEG-TS").tag("ts")
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text("Opzioni avanzate").font(.system(size: 15, weight: .semibold))
                        }
                        .tint(.white)
                        .padding(14).glass(radius: 20)

                        if busy {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Controllo la lista… se il server è particolare provo da solo altre impostazioni, può volerci un minuto.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).glass(radius: 16)
                        } else if let r = result {
                            Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(r.ok ? Theme.cyan : Theme.gold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).glass(radius: 16)
                        }

                        VStack(spacing: 10) {
                            Button { submit() } label: { Text(editing == nil ? "Aggiungi la lista" : "Salva e aggiorna").frame(maxWidth: .infinity) }
                                .buttonStyle(GlassButtonStyle(prominent: true))
                                .disabled(busy || !canSubmit)
                            if checkFailed {
                                // the check can be wrong (a panel that only answers players): let the person try anyway
                                Button { commit(build()) } label: { Text("Aggiungi comunque").frame(maxWidth: .infinity) }
                                    .buttonStyle(GlassButtonStyle())
                                    .disabled(busy || !canSubmit)
                            } else {
                                Button { Task { await test() } } label: { Text("Verifica soltanto").frame(maxWidth: .infinity) }
                                    .buttonStyle(GlassButtonStyle())
                                    .disabled(busy || !canSubmit)
                            }
                        }

                        Text("B-Glass è solo un lettore: non fornisce né include canali, film o serie. Usa la lista del tuo provider.")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).multilineTextAlignment(.center)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(editing == nil ? "Nuova lista" : "Modifica lista")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .alert("Lista già presente", isPresented: $duplicateAsk) {
                Button("Aggiungi lo stesso") { Task { await verifyAndCommit() } }
                Button("Annulla", role: .cancel) {}
            } message: { Text("Hai già aggiunto questo account: canali e film risulterebbero doppi.") }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .onChange(of: server) { v in smartPaste(v) }
        .onChange(of: m3u) { v in smartPaste(v) }
    }

    // MARK: fields

    private func field(_ placeholder: String, text: Binding<String>, icon: String, url: Bool = false, secure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.cyan).frame(width: 22)
            Group {
                if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
            }
            .rawInput(url: url)
            .font(.system(size: 16))
            .disabled(false)
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
    }

    private var candidateM3U: Source? {
        var s = Source()
        s.type = .m3u
        s.url = m3u
        return s
    }

    private var canSubmit: Bool {
        type == .xtream ? !server.trimmed.isEmpty && !user.trimmed.isEmpty : !m3u.trimmed.isEmpty
    }

    private func load() {
        guard let s = editing else { return }
        type = s.type; name = s.name; ua = s.ua; epgUrl = s.epgUrl; insecure = s.insecure
        wantLive = s.wantLive; wantMovies = s.wantMovies; wantSeries = s.wantSeries; liveFmt = s.liveFmt
        if s.type == .xtream { server = s.url; user = s.user; pass = s.pass } else { m3u = s.url }
        showAdvanced = !s.ua.isEmpty || !s.epgUrl.isEmpty || s.insecure || s.liveFmt != "auto" || !s.wantLive || !s.wantMovies || !s.wantSeries
    }

    /// A pasted "get.php?username=…&password=…" link fills server, user and password by itself.
    private func smartPaste(_ text: String) {
        guard type == .xtream, text.contains("username="), let g = XtreamClient.fromGetPhp(text), pasted != text else { return }
        pasted = text
        server = g.base; user = g.user; pass = g.pass
    }

    private func switchToXtream() {
        if let g = XtreamClient.fromGetPhp(m3u) {
            type = .xtream; server = g.base; user = g.user; pass = g.pass
        }
    }

    private func build() -> Source {
        var s = editing ?? Source()
        s.type = type
        if type == .xtream { s.url = XtreamClient.normalizeBase(server); s.user = user.trimmed; s.pass = pass.trimmingCharacters(in: .whitespacesAndNewlines) } else { s.url = m3u.trimmed; s.user = ""; s.pass = "" }
        s.ua = ua.trimmed; s.epgUrl = epgUrl.trimmed; s.insecure = insecure
        s.wantLive = wantLive; s.wantMovies = wantMovies; s.wantSeries = wantSeries
        s.liveFmt = liveFmt; s.fmtVer = 2
        if type == .xtream, editing == nil || editing?.url != s.url || editing?.user != s.user { s.fmtChecked = false; s.hls = false }
        let nm = name.trimmed
        s.name = nm.isEmpty ? (URL(string: s.url)?.host ?? "Lista") : nm
        return s
    }

    /// Checks the list and copies into the form what had to change for it to work (port, User-Agent, certificate).
    @discardableResult
    private func test() async -> Source? {
        busy = true
        result = nil
        defer { busy = false }
        do {
            let c = try await app.backend.check(build())
            result = (true, c.summary)
            checkFailed = false
            if c.source.type == .xtream { server = c.source.url }
            ua = c.source.ua
            insecure = c.source.insecure
            return c.source
        } catch {
            result = (false, Net.explain(error))
            checkFailed = true
            return nil
        }
    }

    private func submit() {
        let s = build()
        if editing == nil, app.sources.contains(where: { $0.type == s.type && $0.url == s.url && $0.user == s.user }) { duplicateAsk = true; return }
        Task { await verifyAndCommit() }
    }

    /// The list is added only once it answers, so a mistake shows here, where it can be corrected, not later as an empty home page.
    private func verifyAndCommit() async {
        guard let ok = await test() else { return }
        var s = build()
        s.url = ok.url; s.ua = ok.ua; s.insecure = ok.insecure
        commit(s)
    }

    private func commit(_ s: Source) {
        if editing != nil {
            app.updateSource(s)
            dismiss()
        } else {
            let added = app.addSource(s)
            Haptics.success()
            dismiss()
            onAdded?(added)
        }
    }
}
