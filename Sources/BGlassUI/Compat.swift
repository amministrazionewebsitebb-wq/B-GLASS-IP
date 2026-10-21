import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformView = UIView
public typealias PlatformViewRepresentable = UIViewRepresentable
#elseif canImport(AppKit)
import AppKit
public typealias PlatformView = NSView
public typealias PlatformViewRepresentable = NSViewRepresentable
#endif

/// The few places where iOS and macOS differ. The screens are written for iOS; macOS is only used to render previews and type-check.
extension View {
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func fullScreenCoverCompat<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    @ViewBuilder func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped).scrollContentBackground(.hidden)
        #else
        listStyle(.inset).scrollContentBackground(.hidden)
        #endif
    }

    /// Plain text input for addresses and credentials: no capital letters, no autocorrection.
    @ViewBuilder func rawInput(url: Bool = false, numeric: Bool = false) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled(true).keyboardType(numeric ? .numberPad : (url ? .URL : .default))
        #else
        autocorrectionDisabled(true)
        #endif
    }

    @ViewBuilder func hideStatusBar(_ hidden: Bool) -> some View {
        #if os(iOS)
        statusBarHidden(hidden)
        #else
        self
        #endif
    }

    @ViewBuilder func clearNavBar() -> some View {
        #if os(iOS)
        toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

extension Color {
    static var systemBackgroundCompat: Color { Theme.ink }
}
