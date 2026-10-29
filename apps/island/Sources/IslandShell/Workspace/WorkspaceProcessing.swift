import AppKit
import Foundation
import CryptoKit

@MainActor
extension WorkspaceStore {
    func enqueueDot(_ id: UUID) throws {
        guard let item=disk.items.first(where:{$0.id==id}), item.service == "dot",
              !["done","running","queued","dot_waiting","dot_running"].contains(item.state) else { return }
        guard mutate({ s in if let i=s.items.firstIndex(where:{$0.id==id}) {
            s.items[i].state="dot_waiting"; s.items[i].aiStartedAt=nil;s.items[i].aiCompletedAt=nil;s.items[i].dotClaim=nil; s.items[i].failure=""; s.items[i].result=""; s.items[i].resultSource=nil
            s.items[i].dotDispatch=UUID(); s.items[i].dotQueuedAt=Date(); s.items[i].dotDeliveries=[:]
        } }) else { throw WorkError.message(error) }
        dotQueued()
    }
    func saveDotDelivery(taskID: UUID, dispatch: UUID, subscription: String, value: DotDelivery) -> Bool {
        guard disk.items.contains(where:{$0.id==taskID && $0.dotDispatch==dispatch && $0.state=="dot_waiting"}) else { return false }
        return mutate { s in if let i=s.items.firstIndex(where:{$0.id==taskID}) {
            if s.items[i].dotDeliveries == nil { s.items[i].dotDeliveries=[:] }
            s.items[i].dotDeliveries?[subscription]=value
        } }
    }
    func retryDotNotification(_ id: UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), item.state=="dot_waiting",
              let deliveries=item.dotDeliveries, !deliveries.isEmpty, deliveries.values.allSatisfy({$0.stopped && !$0.accepted}) else { return }
        if mutate({ s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].dotDeliveries=deliveries.mapValues{_ in DotDelivery()} } }) { dotQueued() }
    }
    func expireDotClaims(now: Date = Date()) {
        guard disk.items.contains(where:{$0.state=="dot_running" && ($0.dotClaim?.expires ?? .distantPast)<=now}) else { return }
        _ = mutate { s in for i in s.items.indices where s.items[i].state=="dot_running" && (s.items[i].dotClaim?.expires ?? .distantPast)<=now {
            s.items[i].state="interrupted"; s.items[i].dotClaim=nil; s.items[i].failure="Dot处理连接已超时，未自动重派。可确认后重试。"
        } }
    }
    func claimDot(_ id: UUID, grant: UUID, now: Date = Date()) throws -> DotClaim {
        expireDotClaims(now:now)
        guard let item=disk.items.first(where:{$0.id==id}), item.service=="dot" else { throw WorkError.message("不是Dot派单。") }
        if item.state=="dot_running", let claim=item.dotClaim, claim.grant==grant { return claim }
        guard item.state=="dot_waiting" else { throw WorkError.message("任务不可领取，请核对现有结果或重试状态。") }
        let claim=DotClaim(grant:grant,digest:WorkspaceMCP.digest(item),expires:now.addingTimeInterval(1800))
        guard mutate({s in if let i=s.items.firstIndex(where:{$0.id==id}) {s.items[i].state="dot_running";s.items[i].aiStartedAt=now;s.items[i].dotClaim=claim}}) else {throw WorkError.message(error)}
        return claim
    }
    func finishDot(_ id: UUID, grant: UUID, claim: UUID, digest: String, text: String, failed: Bool = false, now: Date = Date()) throws {
        guard let item=disk.items.first(where:{$0.id==id}), item.service=="dot", let lease=item.dotClaim,
              lease.id==claim, lease.grant==grant, lease.digest==digest, WorkspaceMCP.digest(item)==digest,
              !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.utf8.count<=60_000 else { throw WorkError.message("任务、领取凭证或材料不匹配，未覆盖。") }
        let target=failed ? "failed" : "succeeded"
        if item.state==target, (failed ? item.failure : item.result)==text { return }
        guard item.state=="dot_running", lease.expires>now else { throw WorkError.message("任务已停止或处理连接已超时，未覆盖。") }
        guard mutate({s in if let i=s.items.firstIndex(where:{$0.id==id}) {
            s.items[i].aiCompletedAt=now; s.items[i].state=target; s.items[i].result=failed ? "" : text; s.items[i].failure=failed ? text : ""; s.items[i].resultSource="Dot回传"
        }}) else { throw WorkError.message(error) }
        selected=id; boardTab=1; notify(failed ? "Dot处理未完成，点开查看" : "Dot处理完成，点开取结果")
        publishAgentResult(id)
        if !failed { queueArchive(id) }
    }
    private func publishAgentResult(_ id:UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), ["succeeded","failed"].contains(item.state) else { return }
        let source=item.service == "dot" ? "Dot" : item.service == "doubao" ? "豆包工作" : item.service == "workbuddy" ? "WorkBuddy" : item.resultSource == "外部Agent回传" ? "Agent" : WorkAI.displayName
        agentNotice("agent-"+id.uuidString+"-"+(item.dotDispatch?.uuidString ?? String((item.aiCompletedAt ?? item.created).timeIntervalSince1970)),source,(item.state == "succeeded" ? "已完成：" : "需要检查：")+item.title)
    }
    func heartbeatDot(_ id: UUID, grant: UUID, claim: UUID, now: Date = Date()) throws {
        guard let item=disk.items.first(where:{$0.id==id}), item.state=="dot_running", let lease=item.dotClaim,
              lease.grant==grant, lease.id==claim, lease.expires>now, lease.digest==WorkspaceMCP.digest(item) else { throw WorkError.message("任务处理连接已失效。") }
        guard mutate({s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].dotClaim?.expires=now.addingTimeInterval(1800) }}) else {throw WorkError.message(error)}
    }
    func receiveAgentResult(_ id: UUID, text: String) throws {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.utf8.count <= 60_000,
              let item = disk.items.first(where:{$0.id==id}), !["done","running","queued","dot_waiting","dot_running"].contains(item.state) else { throw WorkError.message("任务已完成、运行中或结果过大，未覆盖原内容。") }
        if item.result == text && item.state == "succeeded" { return }
        guard mutate({ s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].aiCompletedAt=Date();s.items[i].result=text;s.items[i].resultSource="外部Agent回传";s.items[i].state="succeeded";s.items[i].failure="" } }) else { throw WorkError.message(error) }
        selected = id; boardTab = 1; notify("Agent处理完成，点开取结果"); publishAgentResult(id)
        queueArchive(id)
    }
    func summarizeProject() {
        let project = draftProject.trimmingCharacters(in:.whitespacesAndNewlines)
        let items = disk.items.filter { ($0.project ?? "日常工作") == project }.prefix(40)
        guard !items.isEmpty else { error = "这个项目还没有材料或任务。"; return }
        let material = items.map { "来源任务：\($0.id.uuidString)\n创建时间：\($0.created.ISO8601Format())\n标题：\($0.title)\n状态：\($0.state)\n材料：\($0.input)\n结果：\($0.result)" }.joined(separator:"\n\n")
        do {
            let id = try add(text:"项目归纳："+project+"\n\n"+material,instruction:"根据所给任务记录归纳项目进展、已完成、未完成、下一步和需要本人回答的问题。每项注明来源任务标题；未完成不写成完成。附件图片未提供时不推测图片内容。",minutes:0,project:project)
            boardTab = 1; run(id)
        } catch { self.error = error.localizedDescription }
    }
    func exportDocument(_ item: WorkItem) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = item.title+".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try (item.result.isEmpty ? item.input : item.result).write(to:url,atomically:true,encoding:.utf8) } catch { self.error = "文档保存失败。" }
    }
    func run(_ id: UUID) {
        guard let original=disk.items.first(where:{$0.id==id}), original.archive?.state != "running", original.archive?.state != "pending", original.archive?.intent == nil else { error="请先完成或核对归档，再重新处理。"; return }
        if original.archiveTarget == nil {
            do { try configureArchive(id,target:draftArchive) } catch { self.error=error.localizedDescription; return }
        }
        if disk.items.first(where:{$0.id==id})?.service == "dot" { do { try enqueueDot(id) } catch { self.error=error.localizedDescription }; return }
        guard let item = disk.items.first(where: { $0.id == id }), !["done","running","queued"].contains(item.state) else { return }
        if item.service == "doubao", item.remoteSubmissionPending == true, item.remoteTaskURL == nil { error = "豆包提交结果尚未确认，未重复创建。请先在豆包核对原任务并关联链接。"; return }
        cancelledJobs.remove(id)
        if runner != nil { _ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}){s.items[i].state="queued"} }; return }
        guard mutate({ state in if let i = state.items.firstIndex(where:{$0.id == id}) { state.items[i].state = "running"; state.items[i].failure = ""; if item.service == "doubao" && item.remoteTaskURL == nil { state.items[i].remoteSubmissionPending=true } } }) else { return }
        let images = (item.images ?? []).map { imageURL(item:item,image:$0) }
        let ai: any WorkRunning
        if item.service == "doubao" {
            let browser = WorkBrowser(); browser.expectedAccount = SettingsServer.shared.connectedAccountName ?? ""
            browser.taskID = item.id.uuidString; browser.resumeURL = item.remoteTaskURL
            browser.onSubmitting = { [weak self] in Task { @MainActor in
                guard let self else { return }; _ = self.mutate { state in if let i=state.items.firstIndex(where:{$0.id==id}) { state.items[i].remoteSubmissionPending=true } }
            } }
            browser.onURL = { [weak self] url in Task { @MainActor in
                guard let self else { return }; self.recordRemoteURL(id,url:url)
            } }
            ai = browser
        } else if item.service == "workbuddy" { ai = WorkBuddyAI() }
        else { ai = WorkAI() }
        runner = ai
        job = Task { [weak self] in
            var result: Result<String,Error> = await Task.detached { Result { try ai.run(input:item.input,instruction:item.instruction,images:images) } }.value
            guard let self else { return }
            var remoteValue: String?, links: [String] = []
            if case .success(let value) = result {
                remoteValue = value; links = WorkBrowser.documentLinks(in:value)
                if item.exportSourceID != nil {
                    do {
                        guard let link = links.first else { throw WorkError.message("豆包没有返回飞书文档链接。") }
                        let body = try await self.readLocalFeishuDocument(link)
                        guard body.range(of:item.id.uuidString,options:.caseInsensitive) != nil else { throw WorkError.message("文档未包含本次任务编号，未通过对应关系核对。") }
                    } catch { result = .failure(WorkError.message("文档结果尚未通过本机飞书回读核对："+error.localizedDescription+" 可重新读取原任务，应用不会重复新建。")) }
                }
            }
            if self.cancelledJobs.remove(id) != nil { result = .failure(WorkError.message("已停止本机等候，云端任务状态请查看原任务。")) }
            if let browser = ai as? WorkBrowser {
                if let url=browser.taskURL { self.recordRemoteURL(id,url:url) }
                else if browser.knownNotSubmitted { _ = self.mutate { state in if let i=state.items.firstIndex(where:{$0.id==id}) { state.items[i].remoteSubmissionPending=false } } }
            }
            self.runner = nil; self.job = nil
            let saved = self.mutate { state in
                guard let i = state.items.firstIndex(where:{$0.id == id}), state.items[i].state == "running" else { return }
                switch result { case .success(let value): state.items[i].cloudDocuments = links; if item.exportSourceID != nil { state.items[i].exportVerifiedAt=Date() }; state.items[i].result = value; state.items[i].resultSource = item.service == "doubao" ? "豆包工作（本人网页会话）" : item.service == "workbuddy" ? "WorkBuddy（本机客户端CLI）" : WorkAI.displayName; state.items[i].state = "succeeded"; state.items[i].aiCompletedAt=Date()
                case .failure(let e): if let remoteValue { state.items[i].result=remoteValue; state.items[i].cloudDocuments=links }; state.items[i].failure = e.localizedDescription; state.items[i].state = "failed" }
            }
            if saved { self.selected = id; self.boardTab = 1; self.notify(result.isSuccess ? "材料处理完成，点开取结果" : "材料处理未完成，点开查看") }
            if saved && result.isSuccess { self.publishAgentResult(id); self.queueArchive(id) }
            if saved, let next=self.disk.items.reversed().first(where:{$0.state=="queued"}) {
                if self.mutate({s in if let i=s.items.firstIndex(where:{$0.id==next.id}){s.items[i].state="todo"}}){self.run(next.id)}
            }
        }
    }
    func cancel(_ id: UUID) {
        if let item=disk.items.first(where:{$0.id==id}), item.service == "dot", ["dot_waiting","dot_running"].contains(item.state) {
            _ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].state="interrupted"; s.items[i].dotClaim=nil; s.items[i].failure="已取消本机派单，旧回传失效；不代表外部Dot已停止。" } }; return
        }
        if disk.items.first(where:{$0.id == id})?.state == "queued" { _ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}){s.items[i].state="todo"} }; return }
        guard disk.items.first(where:{$0.id == id})?.state == "running" else { return }; cancelledJobs.insert(id); runner?.cancel()
    }
}

private extension Result { var isSuccess: Bool { if case .success = self { return true }; return false } }
