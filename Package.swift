// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portrero",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Portrero", targets: ["Portrero"]),
    ],
    targets: [
        // Pure Foundation logic (rules, matching, profile parsing) so it can be unit tested in isolation.
        .target(name: "PortreroCore"),
        // The AppKit/SwiftUI app. Bundled into Portrero.app by scripts/build.sh.
        .executableTarget(
            name: "Portrero",
            dependencies: ["PortreroCore"]
        ),
        .testTarget(
            name: "PortreroCoreTests",
            dependencies: ["PortreroCore"]
        ),
    ]
)
