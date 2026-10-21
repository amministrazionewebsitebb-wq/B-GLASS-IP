import BGlassCore
import SwiftUI

enum MainTab: Hashable { case home, live, movies, series, search }

struct MainView: View {
    @EnvironmentObject var app: AppModel
    @State private var tab = MainTab.home

    var body: some View {
        TabView(selection: $tab) {
            tabRoot { HomeView(go: { tab = $0 }) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(MainTab.home)
            tabRoot { LiveView() }
                .tabItem { Label("TV", systemImage: "tv.fill") }.tag(MainTab.live)
            tabRoot { VODBrowserView(kind: .movie) }
                .tabItem { Label("Film", systemImage: "film.fill") }.tag(MainTab.movies)
            tabRoot { VODBrowserView(kind: .series) }
                .tabItem { Label("Serie TV", systemImage: "rectangle.stack.fill") }.tag(MainTab.series)
            tabRoot { SearchView() }
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }.tag(MainTab.search)
        }
        .tint(Theme.cyan)
        .onAppear { tabBarLook() }
    }

    private func tabRoot<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Card.self) { DetailView(card: $0) }
                .navigationDestination(for: CategoryRoute.self) { CategoryGridView(route: $0) }
        }
    }

    private func tabBarLook() {
        #if os(iOS)
        let a = UITabBarAppearance()
        a.configureWithDefaultBackground()
        a.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        a.backgroundColor = UIColor(Theme.ink.opacity(0.35))
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
        let n = UINavigationBarAppearance()
        n.configureWithTransparentBackground()
        n.titleTextAttributes = [.foregroundColor: UIColor.white]
        n.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = n
        UINavigationBar.appearance().scrollEdgeAppearance = n
        UINavigationBar.appearance().compactAppearance = n
        #endif
    }
}

/// The profile button at the top right of every page: switch profile, settings.
struct ProfileMenu: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Menu {
            if let p = app.profile { Text(p.name) }
            Button { app.showSettings = true } label: { Label("Impostazioni", systemImage: "gearshape") }
            Button { if let p = app.profile { app.setupProfile = p } } label: { Label("Scegli i contenuti", systemImage: "checklist") }
            Button { app.refreshGuide() } label: { Label("Aggiorna la guida TV", systemImage: "arrow.clockwise") }
            Divider()
            Button { app.leaveProfile() } label: { Label("Cambia profilo", systemImage: "person.2") }
        } label: {
            if let p = app.profile { Avatar(name: p.name, color: p.color, size: 30) }
        }
    }
}

struct CategoryRoute: Hashable {
    let title: String
    let kind: Kind
    let cats: [String]
    let genre: String?
}
