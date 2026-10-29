import AppKit

/// Finder copies do not launch apps. Opening the app on the download volume starts
/// this installer, before any preferences, readers or island windows are created.
@MainActor public enum IslandInstaller {
    public nonisolated static func isInstallSource(_ source: URL) -> Bool {
        source.path.hasPrefix("/Volumes/") || source.path.contains("/AppTranslocation/")
    }
    public static func runIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL
        guard isInstallSource(source), source.pathExtension == "app",
              Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" else { return false }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
        let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/一切在岛.app")
        let alert = NSAlert()
        alert.messageText = "安装一切在岛"
        alert.informativeText = "安装到你的应用程序文件夹，完成后直接进入使用前设置。完成设置后，灵动岛才会出现。"
        alert.addButton(withTitle: "安装并开始设置"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return true }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staged = destination.deletingLastPathComponent().appendingPathComponent(".island-install-" + UUID().uuidString + ".app")
            try fm.copyItem(at: source, to: staged)
            let verify = Process(); verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            verify.arguments = ["--verify", "--deep", "--strict", staged.path]
            verify.standardOutput = FileHandle.nullDevice; verify.standardError = FileHandle.nullDevice
            try verify.run(); verify.waitUntilExit()
            guard verify.terminationStatus == 0 else { throw NSError(domain: "IslandInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "安装包校验失败，请重新下载。已保留现场文件。"] ) }
            if let old = NSRunningApplication.runningApplications(withBundleIdentifier: "local.zaizhi.feishu-island.preview").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                guard old.terminate() else { throw NSError(domain:"IslandInstaller",code:2,userInfo:[NSLocalizedDescriptionKey:"请退出正在运行的一切在岛后重新安装。"] ) }
                let until = Date().addingTimeInterval(5)
                while !old.isTerminated && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
                guard old.isTerminated else { throw NSError(domain:"IslandInstaller",code:3,userInfo:[NSLocalizedDescriptionKey:"原应用仍在退出，请稍后再试。"] ) }
            }
            var backup: URL?
            if fm.fileExists(atPath: destination.path) {
                let folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland-InstallBackups/" + UUID().uuidString)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                backup = folder.appendingPathComponent("一切在岛.app")
                try fm.moveItem(at: destination, to: backup!)
            }
            do { try fm.moveItem(at: staged, to: destination) }
            catch { if let backup { try? fm.moveItem(at: backup, to: destination) }; throw error }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--onboarding"]
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if let error { let notice = NSAlert(error: error); notice.runModal() }
                    NSApp.terminate(nil)
                }
            }
            app.run()
        } catch {
            let failure = NSAlert(error: error); failure.runModal()
        }
        return true
    }
}
