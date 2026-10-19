// swift-tools-version: 5.9
import PackageDescription

// Local core-only distribution. See UPSTREAM.md for version and patches.
let package = Package(
    name: "OpenNook",
    platforms: [.macOS("15.0")],
    products: [.library(name: "NookApp", targets: ["NookApp"])],
    targets: [
        .target(name: "NookSurface"),
        .target(name: "NookKit", dependencies: ["NookSurface"]),
        .target(name: "NookApp", dependencies: ["NookKit"])
    ]
)
