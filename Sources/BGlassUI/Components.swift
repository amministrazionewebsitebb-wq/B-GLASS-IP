import BGlassCore
import SwiftUI

// MARK: posters and rails

struct RatingBadge: View {
    let value: Double
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.gold)
            Text(String(format: "%.1f", value)).font(.system(size: 10, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.black.opacity(0.62), in: Capsule())
    }
}

struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28))
                Capsule().fill(Theme.cyan).frame(width: max(height, g.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

struct PosterCard: View {
    let card: Card
    var width: CGFloat = 116
    var showTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                RemoteImage(card.logo, title: card.name, maxPixel: Int(width * 3))
                if let f = card.fraction {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).frame(height: 38)
                    ProgressLine(fraction: f).padding(.horizontal, 8).padding(.bottom, 7)
                }
            }
            .frame(width: width, height: width * 1.5)
            .overlay(alignment: .topTrailing) { if card.rate > 0 { RatingBadge(value: card.rate).padding(6) } }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            if showTitle {
                Text(card.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var route: CategoryRoute?
    var action: (() -> Void)?

    private var seeAll: some View {
        HStack(spacing: 3) { Text("Vedi tutto"); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cyan)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            if let route = route {
                NavigationLink(value: route) { seeAll }.buttonStyle(.plain)
            } else if let action = action {
                Button(action: action) { seeAll }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// A titled horizontal strip of posters.
struct PosterRail: View {
    let title: String
    let cards: [Card]
    var width: CGFloat = 116
    var seeAll: (() -> Void)?
    var route: CategoryRoute?
    /// Without an action the poster opens its page; with one (continue watching) it does that instead.
    var action: ((Card) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title, route: route, action: seeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(cards) { c in
                        if let action = action {
                            Button { action(c) } label: { PosterCard(card: c, width: width) }.buttonStyle(.plain)
                        } else {
                            NavigationLink(value: c) { PosterCard(card: c, width: width) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: channels

struct ChannelLogo: View {
    let channel: String
    let logo: String?
    var width: CGFloat = 56
    var height: CGFloat = 40
    var body: some View {
        RemoteImage(logo, title: channel, maxPixel: Int(width * 3), contentMode: .fit)
            .frame(width: width, height: height)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
    }
}

/// "Now on" tile of the home page: logo, what is on and how far it is.
struct OnAirTile: View {
    let channel: LiveChannel
    let now: Prog?
    var width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ChannelLogo(channel: channel.name, logo: channel.logo, width: 52, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(now?.t ?? "In diretta").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let n = now, n.e > n.s {
                ProgressLine(fraction: min(1, max(0, Double(Int64(Date().timeIntervalSince1970) - n.s) / Double(n.e - n.s))), height: 3)
            } else {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
            }
        }
        .padding(12)
        .frame(width: width)
        .glass(radius: 16)
    }
}

// MARK: profiles

struct Avatar: View {
    let name: String
    let color: Int
    var size: CGFloat = 72
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.avatar(color), Theme.avatar(color).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            Text(String(name.trimmed.prefix(1)).uppercased()).font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.avatar(color).opacity(0.5), radius: 12, y: 4)
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
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(Theme.cyan.opacity(0.85))
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
                    LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: phase * g.size.width * 1.6)
                }
                .clipped()
            )
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct PosterSkeleton: View {
    var width: CGFloat = 116
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(width: width, height: width * 1.5)
            .modifier(Shimmer())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RailSkeleton: View {
    var title: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title.isEmpty { RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)).frame(width: 140, height: 18).padding(.horizontal, 16) }
            else { SectionTitle(title: title) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) { ForEach(0..<6, id: \.self) { _ in PosterSkeleton() } }.padding(.horizontal, 16)
            }
            .disabled(true)
        }
    }
}

/// Shows a list that is still loading (channels first, then films and series) at the top of a screen.
struct LoadingBanner: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let running = app.refreshes.filter { $0.value.running }
        if let (id, info) = running.first {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.source(id)?.name ?? "Lista").font(.system(size: 14, weight: .semibold))
                    Text(info.text).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button { app.cancelRefresh(id) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.secondaryText) }.buttonStyle(.plain)
            }
            .padding(12)
            .glass(radius: 16)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let (id, info) = app.refreshes.first(where: { $0.value.error != nil }), let err = info.error {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("«\(app.source(id)?.name ?? "Lista")» non si aggiorna").font(.system(size: 14, weight: .semibold))
                    Text(err).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(3)
                }
                Spacer()
                Button("Riprova") { app.refresh(id) }.font(.system(size: 13, weight: .semibold)).buttonStyle(.plain).foregroundStyle(Theme.cyan)
            }
            .padding(12)
            .glass(radius: 16)
            .padding(.horizontal, 16)
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
                .glass(radius: 22, strong: true)
                .padding(.bottom, 96)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.toast)
        .allowsHitTesting(false)
    }
}

/// B-Glass wordmark.
struct Wordmark: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: 0) {
            Text("B‑").font(.system(size: size, weight: .heavy))
            Text("Glass").font(.system(size: size, weight: .heavy)).foregroundStyle(Theme.accent)
        }
    }
}
