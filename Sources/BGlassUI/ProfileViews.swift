import BGlassCore
import SwiftUI

// MARK: PIN

/// A four digit keypad. `onDone` returns true when the PIN is right (or accepted); false shakes and clears.
struct PinEntry: View {
    let title: String
    var subtitle: String = ""
    let onDone: (String) -> Bool
    var onCancel: () -> Void

    @State private var digits = ""
    @State private var shake = 0

    var body: some View {
        VStack(spacing: 22) {
            Text(title).font(.system(size: 20, weight: .bold))
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center) }
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i < digits.count ? Theme.cyan : Color.white.opacity(0.18)).frame(width: 16, height: 16)
                }
            }
            .modifier(ShakeEffect(travel: CGFloat(shake)))
            VStack(spacing: 12) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                    HStack(spacing: 14) { ForEach(row, id: \.self) { n in key("\(n)") } }
                }
                HStack(spacing: 14) {
                    Button("Annulla", action: onCancel).font(.system(size: 15, weight: .semibold)).frame(width: 74, height: 60).buttonStyle(.plain)
                    key("0")
                    Button { if !digits.isEmpty { digits.removeLast() } } label: { Image(systemName: "delete.left").font(.system(size: 20)).frame(width: 74, height: 60) }.buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground())
        .preferredColorScheme(.dark)
    }

    private func key(_ d: String) -> some View {
        Button {
            Haptics.tap()
            guard digits.count < 4 else { return }
            digits += d
            if digits.count == 4 {
                let entered = digits
                if onDone(entered) { return }
                Haptics.warning()
                withAnimation(.default) { shake += 1 }
                digits = ""
            }
        } label: {
            Text(d).font(.system(size: 28, weight: .medium)).frame(width: 74, height: 60).glass(radius: 30)
        }
        .buttonStyle(.plain)
    }
}

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(travel * .pi * 4), y: 0))
    }
}

// MARK: picker

public struct ProfilePickerView: View {
    @EnvironmentObject var app: AppModel
    @State private var managing = false
    @State private var editor: ProfileEditorTarget?
    @State private var pinFor: Profile?
    @State private var addingList = false

    public init() {}

    public var body: some View {
        ZStack {
            GlassBackground()
            VStack(spacing: 0) {
                HStack {
                    Wordmark(size: 24)
                    Spacer()
                    if !app.profiles.isEmpty {
                        Button(managing ? "Fine" : "Gestisci") { withAnimation { managing.toggle() } }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.cyan)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14)
                LoadingBanner().padding(.top, 10)
                Spacer(minLength: 20)
                if app.profiles.isEmpty { firstProfile } else { picker }
                Spacer(minLength: 20)
                subscription
            }
        }
        .sheet(item: $editor) { t in ProfileEditorView(target: t) }
        .sheet(item: $pinFor) { p in
            PinEntry(title: "PIN di \(p.name)", onDone: { pin in
                if pin == p.pin { pinFor = nil; app.chooseProfile(p.id); return true }
                return false
            }, onCancel: { pinFor = nil })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $addingList) { AddListView() }
    }

    private var firstProfile: some View {
        VStack(spacing: 18) {
            Text("Crea il tuo profilo").font(.system(size: 26, weight: .bold))
            Text("Ogni persona ha i suoi canali, film e serie: scegli solo quello che ti interessa, senza migliaia di voci inutili.")
                .font(.system(size: 15)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).padding(.horizontal, 28)
            Button("Crea profilo") { editor = .new }.buttonStyle(GlassButtonStyle(prominent: true))
        }
    }

    private var picker: some View {
        VStack(spacing: 24) {
            Text(managing ? "Modifica i profili" : "Chi guarda?").font(.system(size: 28, weight: .bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 18)], spacing: 22) {
                ForEach(app.profiles) { p in
                    Button {
                        if managing { editor = .edit(p) }
                        else if p.pin.isEmpty { Haptics.tap(); app.chooseProfile(p.id) }
                        else { pinFor = p }
                    } label: {
                        VStack(spacing: 9) {
                            ZStack(alignment: .bottomTrailing) {
                                Avatar(name: p.name, color: p.color, size: 82)
                                if managing { Image(systemName: "pencil.circle.fill").font(.system(size: 26)).foregroundStyle(.white, Theme.blue) }
                                else if !p.pin.isEmpty { Image(systemName: "lock.fill").font(.system(size: 11)).padding(6).background(.black.opacity(0.6), in: Circle()) }
                            }
                            Text(p.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(summary(p)).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button { editor = .new } label: {
                    VStack(spacing: 9) {
                        Image(systemName: "plus").font(.system(size: 30, weight: .light)).frame(width: 82, height: 82).glass(radius: 41)
                        Text("Aggiungi").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        Text(" ").font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    private func summary(_ p: Profile) -> String {
        var parts: [String] = []
        if !p.live.isEmpty { parts.append("\(p.live.count) canali") }
        if !p.movies.isEmpty { parts.append("\(p.movies.count) film") }
        if !p.series.isEmpty { parts.append("\(p.series.count) serie") }
        return parts.isEmpty ? "Da configurare" : parts.joined(separator: " · ")
    }

    @ViewBuilder private var subscription: some View {
        let soon = app.sources.filter { $0.expTs > 0 }.sorted { $0.expTs < $1.expTs }.first
        VStack(spacing: 8) {
            if let s = soon {
                let days = Int((Double(s.expTs) - Date().timeIntervalSince1970) / 86400)
                Label(days < 0 ? "«\(s.name)» è scaduta il \(s.expires)" : "«\(s.name)» scade il \(s.expires) (\(days) giorni)", systemImage: days <= 14 ? "exclamationmark.circle.fill" : "calendar")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(days <= 14 ? Theme.gold : Theme.tertiaryText)
            }
            Button("Gestisci le liste") { addingList = true }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText).buttonStyle(.plain)
        }
        .padding(.bottom, 18)
    }
}

enum ProfileEditorTarget: Identifiable {
    case new
    case edit(Profile)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let p): return p.id
        }
    }
}

struct ProfileEditorView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: ProfileEditorTarget

    @State private var name = ""
    @State private var color = 0
    @State private var kids = false
    @State private var usePin = false
    @State private var pin = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    private var existing: Profile? {
        if case .edit(let p) = target { return p }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        Avatar(name: name.isEmpty ? "?" : name, color: color, size: 96).padding(.top, 8)
                        TextField("Nome", text: $name)
                            .font(.system(size: 18, weight: .semibold)).multilineTextAlignment(.center)
                            .padding(.vertical, 12).glass(radius: 14)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Colore").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                                ForEach(0..<Theme.avatars.count, id: \.self) { i in
                                    Button { color = i } label: {
                                        Circle().fill(Theme.avatars[i]).frame(width: 30, height: 30)
                                            .overlay(Circle().strokeBorder(.white, lineWidth: color == i ? 3 : 0))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(14).glass(radius: 16)
                        VStack(spacing: 12) {
                            Toggle("Profilo bambini (nasconde i contenuti per adulti)", isOn: $kids)
                            Toggle("Proteggi con PIN", isOn: $usePin)
                            if usePin {
                                TextField("PIN di 4 cifre", text: $pin).rawInput(numeric: true)
                                    .font(.system(size: 18, weight: .semibold)).multilineTextAlignment(.center)
                                    .padding(.vertical, 10).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    .onChange(of: pin) { v in pin = String(v.filter { $0.isNumber }.prefix(4)) }
                            }
                        }
                        .padding(14).glass(radius: 16)
                        if let p = existing {
                            Button("Scegli canali, film e serie") { dismiss(); app.setupProfile = app.backend.profiles.get(p.id) }.buttonStyle(GlassButtonStyle())
                            if app.profiles.count > 1 { Button("Elimina il profilo", role: .destructive) { confirmDelete = true }.padding(.top, 6) }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(existing == nil ? "Nuovo profilo" : "Modifica profilo")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: save).disabled(name.trimmed.isEmpty || (usePin && pin.count != 4)) }
            }
            .alert("Eliminare il profilo?", isPresented: $confirmDelete) {
                Button("Elimina", role: .destructive) { if let p = existing { app.deleteProfile(p.id); dismiss() } }
                Button("Annulla", role: .cancel) {}
            } message: { Text("Canali, preferiti e posizioni di questo profilo andranno persi.") }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let p = existing { name = p.name; color = p.color; kids = p.kids; usePin = !p.pin.isEmpty; pin = p.pin }
            else { color = app.profiles.count % Theme.avatars.count }
        }
    }

    private func save() {
        let nm = name.trimmed
        let pn = usePin ? pin : ""
        if let p = existing {
            app.editProfile(p.id) { $0.name = nm; $0.color = color; $0.kids = kids; $0.pin = pn }
            dismiss()
        } else {
            let p = app.createProfile(name: nm, color: color, pin: pn, kids: kids)
            dismiss()
            if app.profile == nil { app.chooseProfile(p.id) }
        }
    }
}
