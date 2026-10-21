// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "BGlass",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "BGlassCore", targets: ["BGlassCore"]),
        .library(name: "BGlassUI", targets: ["BGlassUI"]),
    ],
    targets: [
        // Foundation-only logic: playlists, Xtream, guide, packs, qualities, library, profiles.
        .target(name: "BGlassCore", resources: [.copy("Resources/packs.txt")]),
        // SwiftUI screens and the player. The iOS app target is only a thin shell around this.
        .target(name: "BGlassUI", dependencies: ["BGlassCore"]),
        // XCTest is not part of the command line tools, so the checks are a plain executable: `swift run bglass-checks`.
        .executableTarget(name: "BGlassChecks", dependencies: ["BGlassCore"]),
    ]
)
