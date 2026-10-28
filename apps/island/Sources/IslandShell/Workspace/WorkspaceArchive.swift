import AppKit
import Foundation
import CryptoKit

@MainActor
extension WorkspaceStore {
    func recordRemoteURL(_ id: UUID, url: String) {
        guard WorkBrowser.validTask(url), let item=disk.items.first(where:{$0.id==id}), item.service == "doubao", item.remoteTaskURL == nil || item.remoteTaskURL == url else { return }
        _ = mutate { state in if let i=state.items.firstIndex(where:{$0.id==id}) { state.items[i].remoteTaskURL=url; state.items[i].remoteSubmissionPending=false } }
    }
    nonisolated static func exportHash(_ value: String) -> String { SHA256.hash(data:Data(value.utf8)).map{String(format:"%02x",$0)}.joined() }
    func saveToFeishu(_ item: WorkItem) {
        if item.archive != nil { retryArchive(item.id); return }
        do { try configureArchive(item.id,target:draftArchive.mode == "off" ? WorkArchiveTarget(mode:"new") : draftArchive); queueArchive(item.id) }
        catch { self.error = error.localizedDescription }
    }
    func configureArchive(_ id:UUID,target:WorkArchiveTarget) throws {
        try target.validate()
        guard let item=disk.items.first(where:{$0.id==id}), item.archive?.intent == nil, item.archive?.state != "running" else { throw WorkError.message("归档进行中或写入待核对，不能改目标。") }
        if let receipt=item.archive, receipt.state == "succeeded", receipt.digest == WorkArchive.digest(item) { return }
        guard mutate({ s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].archiveTarget=target; s.items[i].archive=nil }; s.archiveTarget=target }) else { throw WorkError.message(error) }
    }
    func loadArchiveFields() {
        guard !archiveFieldsBusy else { return }
        archiveFieldsBusy=true; archiveFields=[]
        var target=draftArchive; target.field="lookup"
        Task {
            do {
                let names=try await Task.detached { () -> [String] in
                    let cli=WorkArchiveCLI(), resolved=try WorkArchive.resolve(target,cli:cli)
                    guard let t=resolved.table else { throw WorkError.message("请粘贴包含 table 参数的表格链接。") }
                    let response=WorkArchive.data(try cli.api("GET","/open-apis/bitable/v1/apps/\(t.base)/tables/\(t.table)/fields",params:["page_size":100]))
                    return (response["items"] as? [[String:Any]] ?? []).filter{$0["type"] as? Int == 1}.compactMap{$0["field_name"] as? String}
                }.value
                guard draftArchive.url == target.url else { archiveFieldsBusy=false; return }
                archiveFields=names
                if let first=names.first { draftArchive.field=first } else { error="这个表没有可收录内容的多行文本字段。请在飞书新增文本字段后再读取。" }
            } catch { self.error=error.localizedDescription }
            archiveFieldsBusy=false
        }
    }
    func queueArchive(_ id:UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), let target=item.archiveTarget, target.mode != "off" else { return }
        if let old=item.archive, old.digest != WorkArchive.digest(item) { error="结果已变化；原归档保留，请另存新任务。"; return }
        if item.archive == nil { _ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].archive=WorkArchiveReceipt(target:target,digest:WorkArchive.digest(item)) } } }
        startNextArchive()
    }
    func retryArchive(_ id:UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), item.archive?.intent == nil, item.archive?.state == "failed" else { return }
        _ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].archive?.state="pending" } }; startNextArchive()
    }
    private func startNextArchive() {
        guard !archiveBusy, let item=disk.items.reversed().first(where:{$0.archive?.state == "pending"}), let receipt=item.archive else { return }
        archiveBusy=true
        let attachments = (item.images ?? []).map { ArchiveAttachment(key:$0.id.uuidString,name:$0.name,url:imageURL(item:item,image:$0),image:true) } + (item.archiveFiles ?? []).map { ArchiveAttachment(key:$0.filename,name:$0.name,url:todoStorageRoot.appendingPathComponent("Files/"+item.id.uuidString+"/"+$0.filename),image:false) }
        Task {
            let result = await Task.detached { () -> Result<WorkArchiveReceipt,Error> in
                Result { try WorkArchive.run(item:item,initial:receipt,attachments:attachments,cli:WorkArchiveCLI()) { checkpoint in
                    let semaphore=DispatchSemaphore(value:0)
                    let box=ArchiveSaveBox()
                    Task { @MainActor in
                        box.saved=self.mutate { s in if let i=s.items.firstIndex(where:{$0.id==item.id}) { s.items[i].archive=checkpoint } }
                        semaphore.signal()
                    }
                    semaphore.wait()
                    if !box.saved { throw WorkError.message("本机归档进度未保存，停止外部写入。") }
                } }
            }.value
            self.archiveBusy=false
            switch result {
            case .success: self.selected=item.id; self.notify("飞书归档完成，点开查看链接")
            case .failure(let e): _ = self.mutate { s in if let i=s.items.firstIndex(where:{$0.id==item.id}) { s.items[i].archive?.state="failed"; s.items[i].archive?.error=e.localizedDescription } }
            }
            self.startNextArchive()
        }
    }
}
