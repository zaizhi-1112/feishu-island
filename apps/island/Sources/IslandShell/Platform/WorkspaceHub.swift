import AppKit
import Foundation
import CryptoKit

@MainActor
extension WorkspaceStore {
    func readFeishuMaterial(_ link: String, instruction: String?) {
        Task { do {
            let text = try await readLocalFeishuDocument(link)
            _ = try add(text:"来源："+link+"\n\n"+text,instruction:instruction)
        } catch { self.error = error.localizedDescription } }
    }
    func readLocalFeishuDocument(_ link: String) async throws -> String {
        guard let connection = LocalFeishuBindings.connection(.archive) else { LocalFeishuService.shared.open(.archive); throw WorkError.message("请先连接本机飞书文档账号。") }
        let result = try await Task.detached { try LocalCLIJob.request(connection, purpose: .archive, arguments: ["docs", "+fetch", "--as", "user", "--doc", link]) }.value
        return WorkArchive.strings(WorkArchive.data(result)).joined(separator: "\n")
    }
    func connectHub(callback: String) { Task { do { let url = try await hubClient.begin(callback:callback); NSWorkspace.shared.open(url) } catch { self.error = error.localizedDescription } } }
    func finishHub(query: [URLQueryItem]) async throws {
        try await hubClient.finish(query:query); _ = mutate { $0.selectedCards = [] }
        hub = HubSnapshot(connected:true,name:"本人虚实中台",error:"正在读取本人卡片…")
        Task { await refreshHub(); if disk.selectedCards.isEmpty { _ = mutate { $0.selectedCards = hub.cards.filter{$0.kind == "report"}.map(\.id) } } }
    }
    func disconnectHub() { hub = HubSnapshot(); _ = mutate { $0.selectedCards = [] }; Task { await hubClient.disconnect() } }
    func refreshHub() async {
        guard !hubBusy else { return }; hubBusy = true; defer { hubBusy = false }; lastHubRefresh = Date()
        do { hub = try await hubClient.snapshot() } catch { hub.error = error.localizedDescription }
    }
    func toggleCard(_ id: String) { _ = mutate { s in if s.selectedCards.contains(id) { s.selectedCards.removeAll{$0 == id} } else { s.selectedCards.append(id) } } }
    func moveCard(_ id: String, direction: Int) { _ = mutate { s in guard let i = s.selectedCards.firstIndex(of:id) else { return }; let j = i+direction; if s.selectedCards.indices.contains(j) { s.selectedCards.swapAt(i,j) } } }
    var visibleCards: [HubCard] { disk.selectedCards.compactMap { id in hub.cards.first(where:{$0.id == id}) } }}
