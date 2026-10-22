import BGlassCore
import SwiftUI

/// The whole app: loading, welcome (no list yet), who is watching, and the main tabs.
public struct RootView: View {
    @StateObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel? = nil) {
        _app = StateObject(wrappedValue: model ?? AppModel())
    }

    public var body: some View {
        ZStack {
            GlassBackground()
            switch app.stage {
            case .loading: SplashView()
            case .welcome: WelcomeView()
            case .profiles: ProfilePickerView()
            case .main: MainView()
            }
            ToastOverlay()
        }
        .environmentObject(app)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
        .animation(.easeInOut(duration: 0.25), value: app.stage)
        .task { app.boot() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { app.maintain() } else { app.flush() }
        }
        .fullScreenCoverCompat(item: Binding(get: { app.playRequest }, set: { if $0 == nil { app.playRequest = nil } })) { req in
            PlayerView(app: app, request: req).environmentObject(app)
        }
        .sheet(isPresented: $app.showSettings) { SettingsView().environmentObject(app) }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            ImageLoader.shared.dropMemory()
        }
        #endif
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Wordmark(size: 44)
            ProgressView().tint(.white)
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Wordmark(size: 52)
            Text("Il tuo IPTV, in vetro.")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.secondaryText).padding(.top, 8)
            VStack(alignment: .leading, spacing: 16) {
                feature("person.2.fill", "Un profilo per ognuno", "Ognuno vede solo i canali, i film e le serie che ha scelto.")
                feature("sparkles.tv", "Pacchetti di canali pronti", "Sport, cinema, news, bambini: li ritrova da soli nella tua lista.")
                feature("play.rectangle.on.rectangle.fill", "Come una piattaforma di streaming", "Righe per genere, riprendi da dove eri rimasto, guida TV.")
            }
            .padding(.horizontal, 28).padding(.top, 34)
            Spacer()
            VStack(spacing: 12) {
                Button { adding = true } label: { Text("Aggiungi la tua lista").frame(maxWidth: .infinity) }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                Text("Xtream Codes o link M3U. B-Glass è solo un lettore e non include contenuti.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28).padding(.bottom, 30)
        }
        .sheet(isPresented: $adding) { AddListView() }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.cyan).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
