import AppKit

/// Explicit isolated ordinary window. Never starts Nook, Feishu, Hub timers or login items.
public enum DotSandbox {
    @MainActor public static func runIfRequested() -> Bool {
        guard Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.dot-sandbox" else { return false }
        let app=NSApplication.shared
        app.setActivationPolicy(.regular)
        let store=WorkspaceStore.shared
        store.draftProject="Dot长期合成验收"; store.draftService="dot"; store.setMinutes(0)
        // Restore only this isolated bundle's pairing state; no production service is queried.
        do { try SettingsServer.shared.dotPairing.load() } catch { store.error=error.localizedDescription }
        if !store.disk.items.contains(where:{$0.project==store.draftProject}) {
            do {
                let id=try store.add(text:"合成反馈：客户甲需要搜索支持日期筛选，客户乙需要导出显示进度。",instruction:"仅根据这段合成材料整理两条反馈。请保留日期筛选与导出进度，不读取其他资料。",minutes:0,project:store.draftProject,service:"dot")
                try store.enqueueDot(id)
            } catch { store.error=error.localizedDescription }
        }
        let suite=UserDefaults(suiteName:"local.zaizhi.feishu-island.dot-sandbox.receiver-disabled")!
        let feishu=FeishuStore(defaults:suite,receivingDefault:false)
        SettingsServer.shared.start(store:feishu,preferredPort:18767)
        UnifiedSettingsWindow.shared.open(section: .agents)
        app.run()
        return true
    }
}
