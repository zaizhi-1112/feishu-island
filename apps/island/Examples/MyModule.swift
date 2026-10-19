import NookApp
import SwiftUI

// Copy into Sources/IslandShell, then register in IslandHost.configuration():
// host.register(MyModule.info) { MyModule(context: $0) }
@MainActor
final class MyModule: NookModule {
    nonisolated static let info = NookModuleDescriptor(
        id: "local.youzi.island.my-module",
        displayName: "新模块", icon: "square.grid.2x2",
        backgroundPolicy: .unloadOnSwitchAway
    )
    var descriptor: NookModuleDescriptor { Self.info }
    private let context: NookModuleContext
    init(context: NookModuleContext) { self.context = context }

    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "新模块", symbol: "square.grid.2x2")
        config.setHome { Text("在这里放你的功能").padding(32) }
        return config
    }

    // Use context.defaults for preferences; context.containerURL for module files.
    // Stop timers/subscriptions in onDeactivate. Join async work in prepareForSwitchAway.
    // The launch module starts in init; it does not receive an initial onActivate call.
}
