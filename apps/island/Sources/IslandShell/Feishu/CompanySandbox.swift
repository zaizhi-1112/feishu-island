import AppKit

/// An explicitly built, isolated ordinary authorization window. It cannot start
/// the island, Feishu receiver, material queue, reminders, or login items.
public enum CompanySandbox {
    @MainActor public static func runIfRequested() -> Bool {
        guard Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.company-check" else { return false }
        let app=NSApplication.shared
        app.setActivationPolicy(.regular)
        CompanyConnection.shared.open()
        app.run()
        return true
    }
}
