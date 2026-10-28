import AppKit
import Foundation
import CryptoKit

@MainActor
extension WorkspaceStore {
    func importChrome(_ data: Data) throws {
        guard chromeImportEnabled else { throw WorkError.message("请先在一切在岛材料页开启接收Chrome网页。") }
        guard draftText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, draftImages.isEmpty, draftFiles.isEmpty, !webBusy else { throw WorkError.message("一切在岛已有草稿，请先处理或清空；本次没有覆盖。") }
        draftText = try WorkChromeImport.material(data); chromeDraft=true; boardTab=0; error=""
    }
    func beginMaterialDrop() -> Bool {
        guard !ingestSaving else { return false }
        ingestActive = false; ingestSaving = true; return true
    }
    func endMaterialDrop() { ingestSaving = false }
    @discardableResult func add(text: String, files: [URL] = [], instruction: String? = nil, minutes: Int? = nil, images: [PendingWorkImage] = [], project: String? = nil, service: String? = nil, screenReminder: ScreenReminderStyle? = nil) throws -> UUID {
        guard disk.items.filter({ $0.archivedAt == nil }).count < 500, files.count <= 20, text.utf8.count <= 200_000 else { throw WorkError.message("当前材料或待办过多，请先归档已完成事项。历史会长期保留。") }
        var parts = text.isEmpty ? [] : [text]
        for url in files { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; parts.append("文件：\(url.lastPathComponent)\n" + (try WorkMaterial.read(url))) }
        if !images.isEmpty { parts.append("附件图片：" + images.map { $0.image.name }.joined(separator:"、")) }
        guard images.count <= 6, images.reduce(0,{$0+$1.data.count}) <= 20_000_000 else { throw WorkError.message("一次最多6张图片，总大小不超过20MB。") }
        let input = parts.joined(separator:"\n\n")
        guard !input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, input.utf8.count <= 200_000 else { throw WorkError.message("放入文字、链接或材料文件，总文字不超过200KB。") }
        let reminder = minutes ?? disk.reminderMinutes
        guard (0...10080).contains(reminder) else { throw WorkError.message("提醒时间请设为0到10080分钟，0表示不提醒。") }
        let title = String((files.first?.lastPathComponent ?? images.first?.image.name ?? text.split(separator:"\n").first.map(String.init) ?? "材料").prefix(48))
        var item = WorkItem(title:title.isEmpty ? "图片材料" : title,input:input,files:files.map(\.lastPathComponent),instruction:instruction ?? disk.recipes.first?.instruction ?? "整理要点",images:images.isEmpty ? nil : images.map(\.image),project:String((project ?? draftProject).prefix(60)),service:service ?? draftService,due:reminder == 0 ? nil : Date().addingTimeInterval(Double(reminder)*60))
        item.screenReminder = screenReminder ?? draftScreenReminder
        if let style=item.screenReminder { try ScreenReminderRules.validate(style,materials:screenMaterials) }
        if !files.isEmpty {
            let directory = todoStorageRoot.appendingPathComponent("Files/"+item.id.uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            item.archiveFiles = try files.map { file in
                let access = file.startAccessingSecurityScopedResource(); defer { if access { file.stopAccessingSecurityScopedResource() } }
                let filename = UUID().uuidString+"-"+file.lastPathComponent
                let destination = directory.appendingPathComponent(filename)
                try Data(contentsOf:file).write(to:destination,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
                return WorkFile(name:file.lastPathComponent,filename:filename)
            }
        }
        if !images.isEmpty {
            let directory = todoStorageRoot.appendingPathComponent("Images/"+item.id.uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            for image in images {
                let url = directory.appendingPathComponent(image.image.filename)
                try image.data.write(to:url,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            }
        }
        guard mutate({ $0.items.insert(item,at:0) }) else { throw WorkError.message(error) }
        selected = item.id; acceptedAt = Date(); accepted += 1; ingestActive = true
        let generation = accepted
        Task { [weak self] in
            try? await Task.sleep(for:.seconds(IngestMotion.duration))
            guard let self, self.accepted == generation else { return }
            self.ingestActive = false
        }
        openBoard(); return item.id
    }
    /// Only explicit draft links are fetched. Files, webpage links and chat messages never recurse.
    func preparedLinkInput(reader: @escaping @Sendable (URL) throws -> WorkWebPage = { try WorkWebReader.read($0) }) async throws -> String {
        let original=draftText
        guard readWebLinks, !chromeDraft else { return original }
        guard !webBusy else { throw WorkError.message("正在提取正文，请稍候。") }
        if webInput == original, !webPages.isEmpty { return original+"\n\n"+webPages.map(\.material).joined(separator:"\n\n") }
        let urls=try WorkWebReader.links(in:original)
        guard !urls.isEmpty else { return original }
        webBusy=true; defer { webBusy=false }
        let pages=try await Task.detached(priority:.utility) { try urls.map { try reader($0) } }.value
        guard readWebLinks, draftText==original else { throw WorkError.message("输入或读取选项已变化，本次未提交，请重新提取。") }
        let combined=original+"\n\n"+pages.map(\.material).joined(separator:"\n\n")
        guard combined.utf8.count<=200_000 else { throw WorkError.message("合并正文超过200KB，请减少链接或拆分。") }
        webInput=original; webPages=pages
        return combined
    }
    func previewLinks() {
        Task { do { guard try !WorkWebReader.links(in:draftText).isEmpty else { throw WorkError.message("请先放入HTTPS网页链接。") }; _ = try await preparedLinkInput(); error="" } catch { self.error=error.localizedDescription } }
    }
    func setMinutes(_ minutes: Int) {
        guard (0...10080).contains(minutes) else { return }
        let followsDefault = draftReminderMinutes == disk.reminderMinutes
        guard mutate({ $0.reminderMinutes = minutes }) else { return }
        if followsDefault { draftReminderMinutes = minutes }
    }
    func addRecipe(title: String, instruction: String) throws {
        guard !title.isEmpty, title.count <= 40, !instruction.isEmpty, instruction.count <= 12000, disk.recipes.count < 40 else { throw WorkError.message("请填写40字以内名称和12000字以内处理要求。") }
        _ = mutate { $0.recipes.append(.init(id:UUID().uuidString,title:title,instruction:instruction)) }
    }
    func importSkill() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        panel.message = "选择材料处理类SKILL.md；仅作为文字要求，不执行脚本、工具或MCP。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try addRecipe(title:url.deletingLastPathComponent().lastPathComponent,instruction:WorkMaterial.read(url)) } catch { self.error = error.localizedDescription }
    }
    func attachImage(_ data: Data, name: String = "粘贴截图") {
        do {
            let image = try PendingWorkImage.decode(data,name:name)
            guard draftImages.count < 6, draftImages.reduce(0,{$0+$1.data.count})+image.data.count <= 20_000_000 else { throw WorkError.message("一次最多6张图片，总大小不超过20MB。") }
            draftImages.append(image); error = ""
        } catch { self.error = error.localizedDescription }
    }
    func pasteMaterial() {
        let pb = NSPasteboard.general
        if let data = pb.data(forType:.png) ?? pb.data(forType:.tiff) { attachImage(data); return }
        if let text = pb.string(forType:.string) { draftText += (draftText.isEmpty ? "" : "\n")+text }
        else { error = "剪贴板里没有可粘贴的文字或图片。" }
    }
    func pickFiles(instruction: String? = nil, minutes: Int? = nil) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard urls.count <= 20 else { error = "一次最多20个材料文件。"; return }
        Task { do {
            let result = try await Task.detached { () -> (String,[PendingWorkImage]) in
                var texts: [String] = [], images: [PendingWorkImage] = []
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if WorkspaceStore.isImage(url) { images.append(try PendingWorkImage.read(url)) }
                    else { texts.append("文件："+url.lastPathComponent+"\n"+(try WorkMaterial.read(url))) }
                }
                return (texts.joined(separator:"\n\n"),images)
            }.value
            guard draftFiles.count+urls.filter({!Self.isImage($0)}).count <= 20 else { throw WorkError.message("一次最多20个文件。") }
            guard draftImages.count+result.1.count <= 6, (draftImages+result.1).reduce(0,{$0+$1.data.count})<=20_000_000 else { throw WorkError.message("一次最多6张图片，总大小不超过20MB。") }
            guard draftText.utf8.count+result.0.utf8.count<=200_000 else { throw WorkError.message("文字材料超过200KB。") }
            draftImages += result.1
            draftFiles += urls.filter{!Self.isImage($0)}
            // File text is extracted exactly once when committing the draft. Retain
            // the original path only until then; the task owns a private copy afterwards.
            error = ""
        } catch { self.error = error.localizedDescription } }
    }
    nonisolated static func isImage(_ url: URL) -> Bool { ["png","jpg","jpeg","heic","heif","webp","tiff","tif","gif","bmp"].contains(url.pathExtension.lowercased()) }
    func imageURL(item: WorkItem, image: WorkImage) -> URL { todoStorageRoot.appendingPathComponent("Images/"+item.id.uuidString+"/"+image.filename) }
}
