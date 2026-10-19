// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YuIsland",
    platforms: [.macOS("15.0")],
    dependencies: [.package(path: "Vendor/OpenNook")],
    targets: [
        .target(name: "IslandShell", dependencies: [.product(name: "NookApp", package: "OpenNook")], exclude: ["Feishu/SOURCE.md", "Danmu/SOURCE.md"]),
        .executableTarget(name: "YuIsland", dependencies: ["IslandShell"]),
        .executableTarget(name: "IslandChecks", dependencies: ["IslandShell"], path: "Tests/IslandChecks"),
        .executableTarget(name: "FusionChecks", dependencies: ["IslandShell"], path: "Tests/FusionTests")
    ]
)
