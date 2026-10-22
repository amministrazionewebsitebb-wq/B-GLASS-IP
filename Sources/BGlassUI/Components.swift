import BGlassCore
import SwiftUI

// MARK: small pieces

struct RatingBadge: View {
    let value: Double
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.gold)
            Text(String(format: "%.1f", value)).font(.system(size: 11, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.black.opacity(0.7), in: Capsule())
    }
}

struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 3
    var tint: Color = Theme.cyan
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(tint).frame(width: max(height, g.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

struct LiveBadge: View {
    var body: some View {
        Text("LIVE").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.live, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// B-Glass wordmark.
struct Wordmark: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: 0) {
            Text("B").font(.system(size: size, weight: .heavy))
            Text("·").font(.system(size: size, weight: .heavy)).foregroundStyle(Theme.spectrum)
            Text("Glass").font(.system(size: size, weight: .heavy))
        }
        .foregroundStyle(.white)
    }
}

// MARK: posters and rails

struct PosterCard: View {
    let card: Card
    var width: CGFloat = 112
    var showTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                RemoteImage(card.logo, title: card.name, maxPixel: Int(width * 3))
                if let f = card.fraction {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 36)
                    ProgressLine(fraction: f).padding(.horizontal, 8).padding(.bottom, 7)
                }
            }
            .frame(width: width, height: width * 1.5)
            .overlay(alignment: .topTrailing) { if card.rate > 0 { RatingBadge(value: card.rate).padding(5) } }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if showTitle {
                Text(card.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var route: CategoryRoute?
    var action: (() -> Void)?

    private var more: some View {
        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.secondaryText)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 20, weight: .bold)).lineLimit(1)
            if let route = route {
                NavigationLink(value: route) { more }.buttonStyle(.plain)
            } else if let action = action {
                Button(action: action) { more }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

/// A titled horizontal strip of posters.
struct PosterRail: View {
    let title: String
    let cards: [Card]
    var width: CGFloat = 112
    var seeAll: (() -> Void)?
    var route: CategoryRoute?
    /// Without an action the poster opens its page; with one (continue watching) it does that instead.
    var action: ((Card) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title, route: route, action: seeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(cards) { c in
                        if let action = action {
                            Button { action(c) } label: { PosterCard(card: c, width: width) }.buttonStyle(.plain)
                        } else {
                            NavigationLink(value: c) { PosterCard(card: c, width: width) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: channels

struct ChannelLogo: View {
    let channel: String
    let logo: String?
    var width: CGFloat = 64
    var height: CGFloat = 42
    var body: some View {
        RemoteImage(logo, title: channel, maxPixel: Int(width * 3), contentMode: .fit)
            .padding(logo == nil ? 0 : 5)
            .frame(width: width, height: height)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A channel as a 16:9 tile: logo, what is on, how far it is.
struct LiveTile: View {
    let channel: LiveChannel
    let now: Prog?
    var width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                RemoteImage(channel.logo, title: channel.name, maxPixel: 300, contentMode: .fit)
                    .frame(width: width * 0.42, height: width * 0.22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                LiveBadge().padding(8)
                VStack {
                    Spacer()
                    if let n = now { ProgressLine(fraction: TimeText.fraction(n), height: 3, tint: Theme.live) }
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(now?.t ?? channel.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(now.map { "\(channel.name) · \(TimeText.clock($0.s))–\(TimeText.clock($0.e))" } ?? "In diretta")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

// MARK: choosing

/// A row of filter chips.
struct ChipBar<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var trailing: (String, () -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.15)) { selection = item.0 }
                    } label: {
                        Text(item.1).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(selection == item.0 ? Color.white : Theme.surface2))
                            .foregroundStyle(selection == item.0 ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                }
                if let t = trailing {
                    Button(action: t.1) {
                        HStack(spacing: 4) { Text(t.0); Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
                            .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Two or three big choices side by side, with an underline (Canali | Guida, Film | Serie TV).
struct PillPicker<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 22) {
            ForEach(items, id: \.0) { item in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = item.0 }
                } label: {
                    VStack(spacing: 6) {
                        Text(item.1).font(.system(size: 17, weight: .bold))
                            .foregroundStyle(selection == item.0 ? Color.white : Theme.tertiaryText)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 3)
                            if selection == item.0 { Capsule().fill(Theme.spectrum).frame(height: 3).matchedGeometryEffect(id: "line", in: ns) }
                        }
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: profiles

struct Avatar: View {
    let name: String
    let color: Int
    var size: CGFloat = 72
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.avatar(color), Theme.avatar(color).opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.trimmed.prefix(1)).uppercased()).font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: state

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String = ""
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38, weight: .light)).foregroundStyle(Theme.secondaryText)
            Text(title).font(.system(size: 18, weight: .bold)).multilineTextAlignment(.center)
            if !message.isEmpty { Text(message).font(.system(size: 14)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center) }
            if let a = action, let f = onAction { Button(a, action: f).buttonStyle(GlassButtonStyle(prominent: true)).padding(.top, 4) }
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: phase * g.size.width * 1.6)
                }
                .clipped()
            )
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct PosterSkeleton: View {
    var width: CGFloat = 112
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.surface)
            .frame(width: width, height: width * 1.5)
            .modifier(Shimmer())
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RailSkeleton: View {
    var title: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title.isEmpty { RoundedRectangle(cornerRadius: 5).fill(Theme.surface).frame(width: 140, height: 18).padding(.horizontal, 16) }
            else { SectionTitle(title: title) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in PosterSkeleton() } }.padding(.horizontal, 16)
            }
            .disabled(true)
        }
    }
}

/// Shows a list that is still loading at the top of a screen.
struct LoadingBanner: View {
    @EnvironmentObject var app: AppModel
    @State private var editing: Source?

    var body: some View {
        let running = app.refreshes.filter { $0.value.running }
        if let (id, info) = running.first {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sto caricando «\(app.source(id)?.name ?? "la tua lista")»").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(info.text).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(12)
            .glass(radius: 12)
            .padding(.horizontal, 16)
        } else if let (id, info) = app.refreshes.first(where: { $0.value.error != nil }), let err = info.error {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("«\(app.source(id)?.name ?? "Lista")» non si aggiorna").font(.system(size: 14, weight: .semibold))
                    Text(err).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(3)
                }
                Spacer()
                VStack(spacing: 10) {
                    Button("Riprova") { app.refresh(id) }
                    Button("Modifica") { editing = app.source(id) }
                }
                .font(.system(size: 14, weight: .semibold)).buttonStyle(.plain).foregroundStyle(Theme.cyan)
            }
            .padding(12)
            .glass(radius: 12)
            .padding(.horizontal, 16)
            .sheet(item: $editing) { s in AddListView(editing: s) }
        }
    }
}

struct ToastOverlay: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        VStack {
            Spacer()
            if let t = app.toast {
                HStack(spacing: 8) {
                    Image(systemName: t.style == .error ? "xmark.octagon.fill" : t.style == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(t.style == .info ? Theme.cyan : Theme.gold)
                    Text(t.text).font(.system(size: 14, weight: .semibold)).lineLimit(3)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glass(radius: 12, strong: true)
                .padding(.bottom, 96)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.toast)
        .allowsHitTesting(false)
    }
}
