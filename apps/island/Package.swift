// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YuIsland",
    platforms: [.macOS("15.0")],
    dependencies: [.package(path: "Vendor/OpenNook")],
    targets: [
        .target(name: "IslandShell", dependencies: [.product(name: "NookApp", package: "OpenNook")], exclude: ["Feishu/SOURCE.md", "Danmu/SOURCE.md", "Platform/SOURCE.md"]),
        .target(name: "IslandLegacyFixtures", dependencies: ["IslandShell"], path: "Tests/LegacyFixtures"),
        .executableTarget(name: "YuIsland", dependencies: ["IslandShell"]),
        .executableTarget(name: "IslandLayoutChecks", dependencies: ["IslandShell"], path: "Tests/IslandLayoutChecks"),
        .executableTarget(name: "SurfaceInteractionChecks", dependencies: ["IslandShell"], path: "Tests/SurfaceInteractionChecks"),
        .executableTarget(name: "ExperienceMotionChecks", dependencies: ["IslandShell"], path: "Tests/ExperienceMotionChecks"),
        .executableTarget(name: "DockGeometryChecks", dependencies: ["IslandShell"], path: "Tests/DockGeometryChecks"),
        .executableTarget(name: "IslandChecks", dependencies: ["IslandShell"], path: "Tests/IslandChecks"),
        .executableTarget(name: "FusionChecks", dependencies: ["IslandShell", "IslandLegacyFixtures"], path: "Tests/FusionTests"),
        .executableTarget(name: "AgentChecks", dependencies: ["IslandShell"], path: "Tests/AgentTests"),
        .executableTarget(name: "TodoChecks", dependencies: ["IslandShell"], path: "Tests/TodoChecks"),
        .executableTarget(name: "CompactClickChecks", dependencies: ["IslandShell"], path: "Tests/CompactClickChecks"),
        .executableTarget(name: "NavigationChecks", dependencies: ["IslandShell", "IslandLegacyFixtures"], path: "Tests/NavigationChecks"),
        .executableTarget(name: "PlatformChecks", dependencies: ["IslandShell"], path: "Tests/PlatformChecks"),
        .executableTarget(name: "UnifiedFeishuChecks", dependencies: ["IslandShell"], path: "Tests/UnifiedFeishuChecks"),
        .executableTarget(name: "UnifiedProductChecks", dependencies: ["IslandShell"], path: "Tests/UnifiedProductChecks")
    ]
)
