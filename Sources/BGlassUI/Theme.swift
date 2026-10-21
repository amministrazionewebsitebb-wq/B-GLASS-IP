import BGlassCore
import SwiftUI

/// The B-Glass look: deep blue "ink" backgrounds, frosted glass panels, cyan accents (the palette of the Android app, redrawn for a phone).
public enum Theme {
    public static let ink = Color(red: 2 / 255, green: 10 / 255, blue: 26 / 255)              // #020a1a
    public static let ink2 = Color(red: 4 / 255, green: 25 / 255, blue: 59 / 255)             // #04193b
    public static let navy = Color(red: 10 / 255, green: 37 / 255, blue: 82 / 255)            // #0a2552
    public static let blue = Color(red: 1 / 255, green: 82 / 255, blue: 164 / 255)            // #0152a4
    public static let cyan = Color(red: 109 / 255, green: 207 / 255, blue: 246 / 255)         // #6dcff6
    public static let sky = Color(red: 151 / 255, green: 194 / 255, blue: 237 / 255)          // #97c2ed
    public static let gold = Color(red: 245 / 255, green: 213 / 255, blue: 26 / 255)          // #f5d51a
    public static let live = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
    public static let secondaryText = Color.white.opacity(0.62)
    public static let tertiaryText = Color.white.opacity(0.42)

    /// Profile avatar colours, indexed by `Profile.color`.
    public static let avatars: [Color] = [
        Color(red: 0.00, green: 0.48, blue: 1.00), Color(red: 0.20, green: 0.78, blue: 0.35), Color(red: 1.00, green: 0.62, blue: 0.04),
        Color(red: 0.69, green: 0.32, blue: 0.87), Color(red: 1.00, green: 0.27, blue: 0.23), Color(red: 0.19, green: 0.69, blue: 0.78),
        Color(red: 1.00, green: 0.18, blue: 0.33), Color(red: 0.35, green: 0.34, blue: 0.84),
    ]

    public static func avatar(_ index: Int) -> Color { avatars[((index % avatars.count) + avatars.count) % avatars.count] }

    public static let background = LinearGradient(colors: [ink2, ink], startPoint: .top, endPoint: .bottom)
    public static let accent = LinearGradient(colors: [cyan, Color(red: 0.25, green: 0.55, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Two stable, pleasant colours for a title without artwork.
    static func placeholderColors(_ seed: String) -> [Color] {
        var h: UInt32 = 2166136261
        for b in seed.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let hue = Double(h % 360) / 360
        return [Color(hue: hue, saturation: 0.55, brightness: 0.55), Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.28)]
    }
}

/// The screen background: a blue gradient with a soft glow, behind everything.
public struct GlassBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.blue.opacity(0.45), .clear], center: .topLeading, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Theme.cyan.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

struct GlassStyle: ViewModifier {
    var radius: CGFloat
    var strong: Bool
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(strong ? 0.10 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
    }
}

extension View {
    /// Frosted glass panel with a bright edge.
    public func glass(radius: CGFloat = 16, strong: Bool = false) -> some View { modifier(GlassStyle(radius: radius, strong: strong)) }
}

/// Primary and secondary buttons used all over the app.
public struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool
    var tint: Color
    public init(prominent: Bool = false, tint: Color = Theme.cyan) { self.prominent = prominent; self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.88) : Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    static func clock(_ t: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
    }

    /// 1:23:45 or 23:45
    static func duration(_ ms: Int64) -> String {
        let s = max(0, Int(ms / 1000))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    static func date(ms: Int64) -> String {
        if ms <= 0 { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }
}

#if os(iOS)
import UIKit
#endif
