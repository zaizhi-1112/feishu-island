import AppKit
import Foundation
import CryptoKit

@MainActor
extension WorkspaceStore {
    var screenMaterials: [ScreenReminderMaterial] { ScreenReminderMaterial.builtins + (disk.screenMaterials ?? []) }
    var screenSchedules: [WorkScreenSchedule] { disk.screenSchedules ?? [] }
    func setTaskScreenReminder(_ id: UUID, style: ScreenReminderStyle?) {
        do { if let style { try ScreenReminderRules.validate(style,materials:screenMaterials) }
            _ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}) { s.items[i].screenReminder=style } }
        } catch { self.error=error.localizedDescription }
    }
    @discardableResult func upsertScreenSchedule(id: UUID? = nil, title: String, firstFire: Date, repeatMinutes: Int?, style: ScreenReminderStyle, enabled: Bool = true, lightOnly: Bool = false) throws -> UUID {
        try ScreenReminderRules.validate(title:title,firstFire:firstFire,repeatMinutes:repeatMinutes)
        try ScreenReminderRules.validate(style,materials:screenMaterials)
        var schedule=WorkScreenSchedule(id:id ?? UUID(),title:title.trimmingCharacters(in:.whitespacesAndNewlines),fireAt:firstFire,repeatMinutes:repeatMinutes,style:style,enabled:enabled)
        schedule.lightOnly=lightOnly
        let existing=screenSchedules.first(where:{$0.id==schedule.id})
        guard existing != nil || screenSchedules.count < 30 else { throw WorkError.message("最多保存30个提醒，请先整理。") }
        if id != nil, existing == nil { throw WorkError.message("这个提醒已删除，请重新添加。") }
        schedule.lastFiredAt=existing?.lastFiredAt
        guard mutate({ state in
            var schedules=state.screenSchedules ?? []
            if let index=schedules.firstIndex(where:{$0.id==schedule.id}) { schedules[index]=schedule }
            else { schedules.append(schedule) }; state.screenSchedules=schedules
        }) else { throw WorkError.message(error) }
        return schedule.id
    }
    func deleteScreenSchedule(_ id: UUID) { _ = mutate { $0.screenSchedules?.removeAll{$0.id==id} } }
    func setScreenScheduleEnabled(_ id: UUID, enabled: Bool) {
        _ = mutate { state in if let index=state.screenSchedules?.firstIndex(where:{$0.id==id}) {
            state.screenSchedules![index].enabled=enabled
            if enabled, let minutes=state.screenSchedules![index].repeatMinutes {
                state.screenSchedules![index].fireAt=Date().addingTimeInterval(Double(minutes)*60)
            }
        } }
    }
    func importScreenReminderVideo(_ source: URL) async throws -> ScreenReminderMaterial {
        guard (disk.screenMaterials?.count ?? 0) < 30 else { throw WorkError.message("个人提醒素材最多30个。") }
        let access=source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try ScreenReminderMedia.validateFile(source)
        let id=UUID().uuidString, filename=id+"."+source.pathExtension.lowercased()
        let directory=todoStorageRoot.appendingPathComponent("ScreenReminderMedia",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let destination=directory.appendingPathComponent(filename)
        do {
            // A copy is validated after writing, so a changing external file cannot
            // turn a valid selection into an unbounded or non-video runtime asset.
            let bytes=try Data(contentsOf:source)
            guard bytes.count <= ScreenReminderMedia.maximumBytes else { throw WorkError.message("视频超过150MB。") }
            try bytes.write(to:destination,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
            let info=try await ScreenReminderMedia.inspect(destination)
            guard !Task.isCancelled else { throw CancellationError() }
            guard (disk.screenMaterials?.count ?? 0) < 30 else { throw WorkError.message("个人提醒素材最多30个。") }
            let material=ScreenReminderMaterial(id:id,name:String(source.deletingPathExtension().lastPathComponent.prefix(60)),filename:filename,durationSeconds:info.duration,hasAlpha:info.alpha)
            guard mutate({ $0.screenMaterials=($0.screenMaterials ?? [])+[material] }) else { throw WorkError.message(error) }
            return material
        } catch {
            if FileManager.default.fileExists(atPath:destination.path) { try? FileManager.default.trashItem(at:destination,resultingItemURL:nil) }
            throw error
        }
    }
    func screenReminderRequest(style: ScreenReminderStyle, title: String) throws -> ScreenReminderRequest {
        try ScreenReminderRules.validate(style,materials:screenMaterials)
        guard let material=screenMaterials.first(where:{$0.id==style.materialID}) else { throw WorkError.message("提醒素材不可用。") }
        let url: URL?
        if material.id=="cat" { url=nil }
        else if material.id=="rick" {
            guard let resource=Bundle.main.url(forResource:"rick-portal",withExtension:"mov",subdirectory:"ScreenReminder") else { throw WorkError.message("内置瑞克素材未安装，请重新下载安装包。") }
            url=resource
        } else { url=try ScreenReminderMedia.ownedURL(material,root:todoStorageRoot) }
        return ScreenReminderRequest(title:String(title.prefix(80)),style:style,material:material,videoURL:url)
    }
    func previewScreenReminder(_ style: ScreenReminderStyle, title: String = "休息一下，抬头看看远处") throws {
        let request=try screenReminderRequest(style:style,title:title)
        // Explicit user preview in the daily app only; synthetic stores stay off-screen.
        guard integrationEnabled else { throw WorkError.message("独立检查不启动桌面提醒。") }
        try ScreenReminderPresenter.shared.present(request)
    }
    func dismissScreenReminder() { if integrationEnabled { ScreenReminderPresenter.shared.dismiss() } }
    func dismissAllScreenReminders() { if integrationEnabled { ScreenReminderPresenter.shared.dismissAll() } }
    func tickReminders(now: Date = Date()) {
        tickRest(now:now,away:remindersAreLocked() || restSleeping)
        if remindersAreLocked() || restSleeping { return }
        tickFeishuSchedules(now:now)
        let due=disk.items.filter { $0.archivedAt == nil && $0.state != "done" && !$0.reminded && ($0.due.map{$0 <= now} ?? false) }
        let scheduled=screenSchedules.filter { $0.enabled && $0.fireAt <= now }
        guard !due.isEmpty || !scheduled.isEmpty else { return }
        // Persist consumption before any visible effect; restart cannot replay a reminder.
        guard mutate({ state in
            let taskIDs=Set(due.map(\.id)), scheduleIDs=Set(scheduled.map(\.id))
            for index in state.items.indices where taskIDs.contains(state.items[index].id) {
                state.items[index].reminded=true
                if var plan=state.items[index].todoReminder {
                    plan.pendingDates.removeAll { $0 <= now }
                    var next=plan.pendingDates.min()
                    if let minutes=plan.repeatMinutes, (1...10080).contains(minutes) {
                        let repeated=now.addingTimeInterval(Double(minutes)*60)
                        if plan.repeatUntil.map({ repeated <= $0 }) ?? true { next=min(next ?? repeated,repeated) }
                    }
                    state.items[index].todoReminder=plan
                    if let next { state.items[index].due=next; state.items[index].reminded=false }
                }
            }
            for index in (state.screenSchedules ?? []).indices where scheduleIDs.contains(state.screenSchedules![index].id) {
                ScreenReminderRules.advance(&state.screenSchedules![index],now:now)
            }
        }) else { return }
        if !due.isEmpty { selected=due.first?.id; boardTab=1;todoPage="tasks" }
        // Each event chooses one route. Todo reminders never enter the Agent/danmu feed.
        let lightTitles=due.filter { $0.screenReminder == nil }.map(\.title) + scheduled.filter { $0.lightOnly == true }.map(\.title)
        if let title=lightTitles.first { notify(lightTitles.count > 1 ? title+" · 还有\(lightTitles.count-1)项提醒" : title) }
        // A single desktop reminder represents this batch; no overlapping windows or
        // storm of catch-up animations after sleeping or a long offline period.
        let candidates=due.compactMap { item in item.screenReminder.map { (item.title,$0) } } + scheduled.filter { $0.lightOnly != true }.map { ($0.title,$0.style) }
        if let first=candidates.first {
            let title=candidates.count>1 ? "\(first.0) · 还有\(candidates.count-1)项提醒" : first.0
            do { presentScreenReminder(try screenReminderRequest(style:first.1,title:title)) }
            catch { self.error=error.localizedDescription; notify("提醒时间到了 · "+title+"（冲屏素材暂不可用）") }
        }
    }
}
