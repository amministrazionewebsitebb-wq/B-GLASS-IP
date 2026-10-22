import BGlassCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The look: a streaming-TV style (deep black, a blue glow, flat cards, a white main button, red for what is live).
public enum Theme {
    public static let ink = Color(red: 0, green: 0, blue: 0)
    public static let ink2 = Color(red: 7 / 255, green: 11 / 255, blue: 22 / 255)
    public static let navy = Color(red: 11 / 255, green: 26 / 255, blue: 58 / 255)
    /// Cards and rows.
    public static let surface = Color(red: 18 / 255, green: 21 / 255, blue: 30 / 255)
    /// Raised elements on a card (secondary buttons, logo tiles, chips).
    public static let surface2 = Color(red: 30 / 255, green: 35 / 255, blue: 50 / 255)
    public static let stroke = Color.white.opacity(0.08)
    /// The accent: selections, progress, links.
    public static let cyan = Color(red: 46 / 255, green: 124 / 255, blue: 1)
    public static let blue = Color(red: 10 / 255, green: 92 / 255, blue: 1)
    public static let sky = Color(red: 140 / 255, green: 180 / 255, blue: 1)
    public static let gold = Color(red: 1, green: 204 / 255, blue: 0)
    public static let live = Color(red: 240 / 255, green: 40 / 255, blue: 74 / 255)
    public static let secondaryText = Color.white.opacity(0.68)
    public static let tertiaryText = Color.white.opacity(0.42)

    /// The colour band used sparingly: the wordmark, the selected tab line, the splash.
    public static let spectrum = LinearGradient(colors: [Color(red: 10 / 255, green: 92 / 255, blue: 1), Color(red: 107 / 255, green: 59 / 255, blue: 1),
                                                         Color(red: 232 / 255, green: 51 / 255, blue: 127 / 255)],
                                                startPoint: .leading, endPoint: .trailing)

    /// Profile avatar colours, indexed by `Profile.color`.
    public static let avatars: [Color] = [
        Color(red: 0.12, green: 0.45, blue: 1.00), Color(red: 0.20, green: 0.75, blue: 0.40), Color(red: 1.00, green: 0.58, blue: 0.10),
        Color(red: 0.62, green: 0.32, blue: 0.95), Color(red: 0.95, green: 0.25, blue: 0.35), Color(red: 0.12, green: 0.70, blue: 0.80),
        Color(red: 0.95, green: 0.20, blue: 0.60), Color(red: 0.40, green: 0.40, blue: 0.85),
    ]

    public static func avatar(_ index: Int) -> Color { avatars[((index % avatars.count) + avatars.count) % avatars.count] }

    public static let background = LinearGradient(colors: [navy, ink2, ink], startPoint: .top, endPoint: .center)
    public static let accent = LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Two stable, pleasant colours for a title without artwork.
    static func placeholderColors(_ seed: String) -> [Color] {
        var h: UInt32 = 2166136261
        for b in seed.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let hue = (0.55 + Double(h % 120) / 360).truncatingRemainder(dividingBy: 1)       // blues and violets, like the rest of the app
        return [Color(hue: hue, saturation: 0.55, brightness: 0.38), Color(hue: hue, saturation: 0.6, brightness: 0.16)]
    }
}

/// The screen background: black, with a soft blue light at the top.
public struct GlassBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            Theme.ink
            LinearGradient(colors: [Theme.navy.opacity(0.9), Theme.ink.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
            RadialGradient(colors: [Theme.blue.opacity(0.22), .clear], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    var radius: CGFloat
    var strong: Bool
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(strong ? Theme.surface2 : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct FrostedStyle: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(0.25)))
    }
}

extension View {
    /// A flat card (rows, panels).
    public func glass(radius: CGFloat = 14, strong: Bool = false) -> some View { modifier(CardStyle(radius: radius, strong: strong)) }
    /// Frosted glass, for what floats over the video.
    public func frosted(radius: CGFloat = 16) -> some View { modifier(FrostedStyle(radius: radius)) }
}

/// The main button is white with black text; the others are dark.
public struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool
    var tint: Color
    public init(prominent: Bool = false, tint: Color = .white) { self.prominent = prominent; self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(prominent ? tint : Theme.surface2))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A round icon button (players, cards).
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? Theme.surface2 : Color.clear))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

enum Haptics {
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

/// Time helpers shared by the guide and the player.
enum TimeText {
    private static let clockFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ t: Int64) -> String { clockFormat.string(from: Date(timeIntervalSince1970: TimeInterval(t))) }

    /// 1:23:45 or 23:45
    static func duration(_ ms: Int64) -> String {
        let s = max(0, Int(ms / 1000))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func date(ms: Int64) -> String {
        if ms <= 0 { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    static func fraction(_ p: Prog, now: Int64 = Int64(Date().timeIntervalSince1970)) -> Double {
        guard p.e > p.s else { return 0 }
        return min(1, max(0, Double(now - p.s) / Double(p.e - p.s)))
    }
}

/// Where the app may rotate: the player turns with the phone, everything else stays upright (as streaming apps do).
public enum OrientationLock {
    #if os(iOS)
    public static var mask: UIInterfaceOrientationMask = isPad ? .all : .portrait
    private static var free = false
    private static var observer: NSObjectProtocol?
    private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The player turns with the phone; everything else stays upright.
    @MainActor
    static func allowRotation(_ on: Bool) {
        free = on
        if isPad { return }
        if on {
            mask = .allButUpsideDown
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                    Task { @MainActor in deviceTurned() }
                }
            }
            refresh()
        } else {
            if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            mask = .portrait
            apply(.portrait)
        }
    }

    /// The full screen button: turns the screen and keeps it so until the phone is held the same way, then follows the phone again.
    @MainActor
    static func request(landscape: Bool) {
        guard free, !isPad else { return }
        mask = landscape ? .landscape : .portrait
        apply(landscape ? .landscapeRight : .portrait)
    }

    @MainActor
    private static func deviceTurned() {
        guard free, !isPad else { return }
        let o = UIDevice.current.orientation
        if (mask == .landscape && o.isLandscape) || (mask == .portrait && o == .portrait) {
            mask = .allButUpsideDown
            refresh()
        }
    }

    @MainActor
    private static func apply(_ m: UIInterfaceOrientationMask) {
        refresh()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
    }

    @MainActor
    private static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows {
                w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                w.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
    #else
    @MainActor static func allowRotation(_ on: Bool) {}
    @MainActor static func request(landscape: Bool) {}
    #endif
}
