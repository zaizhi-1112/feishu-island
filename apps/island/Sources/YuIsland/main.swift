import NookApp
import IslandShell
import AppKit

if MainActor.assumeIsolated({ CompanySandbox.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DotSandbox.runIfRequested() }) { exit(0) }

if MainActor.assumeIsolated({ IslandInstaller.runIfNeeded() }) { exit(0) }

// Finder normally reuses the running app. Guard direct executable launches as well.
if let id = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id)
    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleURL.map(IslandInstaller.isInstallSource) != true }) {
    if ProcessInfo.processInfo.arguments.contains("--self-test") {
        fputs("Close the running YuIsland before --self-test. No checks were executed.\n", stderr)
        exit(2)
    }
    existing.activate()
    exit(0)
}
NookApp.main(IslandHost.configuration())
