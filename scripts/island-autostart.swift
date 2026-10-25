import AppKit
// Observe public app-launch events only; no desktop login inspection or message access.
let targets = [
    "/Applications/飞书工作岛.app",
    NSHomeDirectory() + "/Applications/飞书工作岛.app",
    NSHomeDirectory() + "/Applications/飞书工作岛预览版.app",
    "/Applications/飞书工作岛预览版.app"
]
let identifier = "local.zaizhi.feishu-island.preview"
func openIsland() {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
          let target = targets.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: config) { _, _ in }
}
let center = NSWorkspace.shared.notificationCenter
let observer = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          app.bundleIdentifier == "com.electron.lark" else { return }
    openIsland()
}
if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.lark").isEmpty { openIsland() }
RunLoop.main.run()
