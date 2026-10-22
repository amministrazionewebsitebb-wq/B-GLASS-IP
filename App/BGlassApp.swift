import BGlassUI
import SwiftUI
#if os(iOS)
import UIKit

/// Lets the player turn with the phone while the rest of the app stays upright.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
#endif

@main
struct BGlassApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    init() {
        #if canImport(MobileVLCKit)
        // VLC reads what Apple's player cannot (MKV, AVI, raw MPEG-TS): it is linked in when the build was made with it.
        Engines.makeVLC = { VLCEngine() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
