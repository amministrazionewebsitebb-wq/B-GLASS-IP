import BGlassCore
import SwiftUI

enum MainTab: Hashable { case home, live, ondemand, search }

struct MainView: View {
    @EnvironmentObject var app: AppModel
    @State private var tab = MainTab.home

    var body: some View {
        TabView(selection: $tab) {
            tabRoot { HomeView(go: { tab = $0 }) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(MainTab.home)
            tabRoot { LiveView() }
                .tabItem { Label("TV", systemImage: "tv.fill") }.tag(MainTab.live)
            tabRoot { OnDemandView() }
                .tabItem { Label("On Demand", systemImage: "play.rectangle.on.rectangle.fill") }.tag(MainTab.ondemand)
            tabRoot { SearchView() }
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }.tag(MainTab.search)
        }
        .tint(.white)
        .onAppear { barsLook() }
    }

    private func tabRoot<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Card.self) { DetailView(card: $0) }
                .navigationDestination(for: CategoryRoute.self) { CategoryGridView(route: $0) }
        }
    }

    private func barsLook() {
        #if os(iOS)
        let a = UITabBarAppearance()
        a.configureWithDefaultBackground()
        a.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        a.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        for item in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor.white.withAlphaComponent(0.45)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
            item.selected.iconColor = .white
            item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
        let n = UINavigationBarAppearance()
        n.configureWithTransparentBackground()
        n.titleTextAttributes = [.foregroundColor: UIColor.white]
        n.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 32, weight: .heavy)]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        scrolled.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = n
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().tintColor = .white
        #endif
    }
}

/// The profile button at the top right of every page.
struct ProfileMenu: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Menu {
            if let p = app.profile { Text(p.name) }
            Button { app.showSettings = true } label: { Label("Impostazioni", systemImage: "gearshape") }
            Button { app.refreshNow() } label: { Label("Aggiorna canali e guida", systemImage: "arrow.clockwise") }
            if app.profiles.count > 1 {
                Button { app.leaveProfile() } label: { Label("Cambia profilo", systemImage: "person.2") }
            }
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
