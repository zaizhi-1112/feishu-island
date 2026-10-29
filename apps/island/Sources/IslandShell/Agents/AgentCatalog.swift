import Foundation
import Combine

/// Saved launch entries contain no credentials. Monitoring adapters remain independent.
struct AgentCatalogEntry: Codable, Identifiable, Equatable {
    var id:String
    var name:String
    var launchURL:String = ""
    var taskProvider:AgentWorkProvider? { AgentWorkProvider(rawValue:id) }
    var isBuiltin:Bool { AgentCatalogStore.builtins.contains{$0.id==id} }
    var monitorID:String? { ["codex","claude","workbuddy"].contains(id) ? id : nil }
    var symbol:String { taskProvider?.symbol ?? "sparkles" }
}

@MainActor final class AgentCatalogStore: ObservableObject {
    static let shared=AgentCatalogStore()
    nonisolated static let builtins:[AgentCatalogEntry]=[
        .init(id:"codex",name:"Codex"), .init(id:"claude",name:"Claude Code"),
        .init(id:"workbuddy",name:"WorkBuddy"), .init(id:"dot",name:"Dot"),
        .init(id:"doubao",name:"豆包工作")
    ]
    @Published private(set) var custom:[AgentCatalogEntry]=[]
    @Published private(set) var selectedID:String?
    private let defaults:UserDefaults
    private let key="agentCatalog.v1"
    private struct Saved:Codable { var custom:[AgentCatalogEntry]; var selectedID:String? }
    init(defaults:UserDefaults = UserDefaults(suiteName:"local.zaizhi.feishu-island.preview.agent-catalog")!) {
        self.defaults=defaults
        if let data=defaults.data(forKey:key), let saved=try? JSONDecoder().decode(Saved.self,from:data),
           saved.custom.count<=12,
           saved.custom.allSatisfy({$0.id.hasPrefix("custom-") && (try? Self.validate(name:$0.name,url:$0.launchURL)) != nil}),
           Set(saved.custom.map(\.id)).count==saved.custom.count,
           Set(saved.custom.map{$0.name.lowercased()}).count==saved.custom.count,
           !saved.custom.contains(where:{ entry in Self.builtins.contains{$0.name.lowercased()==entry.name.lowercased()} }) {
            custom=saved.custom
            if (Self.builtins+custom).contains(where:{$0.id==saved.selectedID}) { selectedID=saved.selectedID }
        }
    }
    var entries:[AgentCatalogEntry] { Self.builtins+custom }
    func selected(in workspace:WorkspaceStore)->AgentCatalogEntry {
        entries.first{$0.id==selectedID} ?? entries.first{$0.id==workspace.draftService} ?? Self.builtins[0]
    }
    func select(_ id:String,in workspace:WorkspaceStore) {
        guard let entry=entries.first(where:{$0.id==id}) else { return }
        selectedID=id
        if let provider=entry.taskProvider { provider.select(in:workspace) }
        save()
    }
    @discardableResult func add(name:String,url:String)->String? {
        guard custom.count<12 else { return "最多添加12个 Agent。" }
        do { try Self.validate(name:name,url:url) } catch { return error.localizedDescription }
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !entries.contains(where:{$0.name.lowercased()==name.lowercased()}) else { return "这个 Agent 已在列表中。" }
        custom.append(.init(id:"custom-"+UUID().uuidString,name:name,launchURL:url.trimmingCharacters(in:.whitespacesAndNewlines)))
        save(); return nil
    }
    func remove(_ id:String) { custom.removeAll{$0.id==id}; if selectedID==id { selectedID=nil }; save() }
    nonisolated private static func validate(name:String,url:String) throws {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines), address=url.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count<=40,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else { throw WorkError.message("名称请填写1–40个字。") }
        if !address.isEmpty {
            guard let parts=URLComponents(string:address),parts.scheme=="https",let host=parts.host,!host.isEmpty,
                  parts.user==nil,parts.password==nil,parts.query==nil,parts.fragment==nil else { throw WorkError.message("入口请填不含账号、参数或令牌的 HTTPS 地址；也可以留空。") }
        }
    }
    private func save() { if let data=try? JSONEncoder().encode(Saved(custom:custom,selectedID:selectedID)) { defaults.set(data,forKey:key) } }
}

/// These are task destinations, not the independent local monitoring adapters.
enum AgentWorkProvider: String, CaseIterable, Identifiable {
    case codex, dot, doubao, workbuddy
    var id:String { rawValue }
    var title:String { switch self { case .codex: return "Codex"; case .dot: return "Dot"; case .doubao: return "豆包工作"; case .workbuddy: return "WorkBuddy" } }
    var symbol:String { switch self { case .codex: return "terminal"; case .dot: return "sparkles"; case .doubao: return "bubble.left.and.text.bubble.right"; case .workbuddy: return "sparkles.rectangle.stack" } }
    var detail:String { switch self { case .codex: return "独立后台处理"; case .dot: return "项目任务 · 自动回传"; case .doubao: return "专属伙伴 · 结果回到岛内"; case .workbuddy: return "本人WorkBuddy · 后台处理并返回" } }
    @MainActor func select(in workspace:WorkspaceStore) { workspace.draftService=rawValue }
}

