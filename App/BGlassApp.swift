import BGlassUI
import SwiftUI

@main
struct BGlassApp: App {
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
