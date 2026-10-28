import AppKit
import Foundation

struct RestReminderPlan:Codable,Equatable {
    var enabled=false
    var intervalMinutes=60
    var pauseWhenAway=true
    var sound=false
    var materialID="cat"
    var paused=false
    var systemPaused=false
    var remainingSeconds:Double=3600
    var fireAt:Date?
    var valid:Bool {(5...240).contains(intervalMinutes) && remainingSeconds.isFinite && (0...86400).contains(remainingSeconds) && (fireAt.map{$0.timeIntervalSince1970.isFinite} ?? true)}
    func remaining(at now:Date)->Double {max(0,fireAt?.timeIntervalSince(now) ?? remainingSeconds)}
    mutating func restart(now:Date,seconds:Double?=nil){remainingSeconds=seconds ?? Double(intervalMinutes)*60;fireAt=enabled && !paused && !systemPaused ? now.addingTimeInterval(remainingSeconds):nil}
    mutating func setPaused(_ value:Bool,now:Date){remainingSeconds=remaining(at:now);paused=value;fireAt=enabled && !paused && !systemPaused ? now.addingTimeInterval(remainingSeconds):nil}
    mutating func setAway(_ away:Bool,now:Date){let next=away && pauseWhenAway;guard next != systemPaused else{return};remainingSeconds=remaining(at:now);systemPaused=next;fireAt=enabled && !paused && !systemPaused ? now.addingTimeInterval(remainingSeconds):nil}
}

@MainActor extension WorkspaceStore {
    var restPlan:RestReminderPlan {disk.restReminder ?? RestReminderPlan(materialID:screenMaterials.first?.id ?? "")}
    func changeRest(_ change:(inout RestReminderPlan)->Void){var plan=restPlan;change(&plan);guard plan.valid,(screenMaterials.isEmpty || screenMaterials.contains(where:{$0.id==plan.materialID})) else{error="提醒间隔应为5到240分钟，并选择可用素材。";return};if mutate({$0.restReminder=plan}) {error=""}}
    func setRestEnabled(_ enabled:Bool,now:Date=Date()){changeRest{p in p.enabled=enabled;p.paused=false;p.systemPaused=false;p.restart(now:now)}}
    func postponeRest(now:Date=Date()){changeRest{p in p.restart(now:now,seconds:600)};dismissScreenReminder()}
    func tickRest(now:Date=Date(),away:Bool) {
        var plan=restPlan
        guard plan.enabled else{return}
        let before=plan;plan.setAway(away,now:now)
        if before != plan {guard mutate({$0.restReminder=plan}) else{return}}
        guard !away,!plan.paused,!plan.systemPaused,let fire=plan.fireAt,fire<=now else{return}
        plan.restart(now:now)
        guard mutate({$0.restReminder=plan}) else{return}
        guard !screenMaterials.isEmpty else {notify("站起来，活动一下");return}
        do {var request=try screenReminderRequest(style:.init(materialID:plan.materialID),title:"站起来，活动一下");request.sound=plan.sound;request.isRest=true;presentScreenReminder(request)}
        catch {self.error=error.localizedDescription;notify("该休息一下了（提醒素材暂不可用）")}
    }
    func renameScreenMaterial(_ id:String,name:String){let name=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty,name.count<=60 else{error="素材名称请填写1到60个字。";return};_ = mutate{s in if let i=s.screenMaterials?.firstIndex(where:{$0.id==id}){s.screenMaterials![i].name=name}}}
    func materialUsage(_ id:String) -> [String] {
        var uses:[String]=[]
        if restPlan.materialID==id {uses.append("休息提醒")}
        if disk.defaultTodoScreen?.materialID==id {uses.append("待办与日程的默认提醒")}
        if screenSchedules.contains(where:{$0.style.materialID==id}) {uses.append("其他计划提醒")}
        if disk.items.contains(where:{$0.screenReminder?.materialID==id || $0.completionReminder?.materialID==id}) {uses.append("待办或完成效果（含已归档）")}
        if (disk.trash ?? []).contains(where:{$0.screenReminder?.materialID==id || $0.completionReminder?.materialID==id}) {uses.append("最近删除中的可恢复待办")}
        return uses
    }
    func materialIsUsed(_ id:String)->Bool {!materialUsage(id).isEmpty}
    @discardableResult func removeScreenMaterial(_ id:String) -> Bool {
        guard let material=screenMaterials.first(where:{$0.id==id}) else{return false}
        let fallback=screenMaterials.first(where:{$0.id != id})?.id
        func replace(_ style:ScreenReminderStyle?) -> ScreenReminderStyle? {
            guard var style,style.materialID==id else{return style}
            guard let fallback else{return nil}
            style.materialID=fallback;return style
        }
        let owned=material.filename == nil ? nil : try? ScreenReminderMedia.ownedURL(material,root:todoStorageRoot)
        let plan=restPlan
        guard mutate({s in
            s.removedScreenMaterialIDs=Array(Set((s.removedScreenMaterialIDs ?? [])+[id])).sorted()
            s.screenMaterials?.removeAll{$0.id==id}
            if plan.materialID==id {var updated=plan;updated.materialID=fallback ?? "";s.restReminder=updated}
            s.defaultTodoScreen=replace(s.defaultTodoScreen)
            for i in s.items.indices {s.items[i].screenReminder=replace(s.items[i].screenReminder);s.items[i].completionReminder=replace(s.items[i].completionReminder)}
            for i in (s.trash ?? []).indices {s.trash![i].screenReminder=replace(s.trash![i].screenReminder);s.trash![i].completionReminder=replace(s.trash![i].completionReminder)}
            for i in (s.screenSchedules ?? []).indices where s.screenSchedules![i].style.materialID==id {
                if let updated=replace(s.screenSchedules![i].style) {s.screenSchedules![i].style=updated}
                else {s.screenSchedules![i].style.materialID="";s.screenSchedules![i].lightOnly=true}
            }
        }) else{return false}
        if integrationEnabled {ScreenReminderPresenter.shared.removeMaterial(id)}
        if let owned {
            do {try FileManager.default.trashItem(at:owned,resultingItemURL:nil)}
            catch {self.error="已从素材库删除；本机副本暂时无法移到废纸篓，已保留。"}
        }
        return true
    }
    func restoreBuiltinScreenMaterials() {
        let builtins=Set(ScreenReminderMaterial.builtins.map(\.id))
        _ = mutate {s in
            s.removedScreenMaterialIDs?.removeAll{builtins.contains($0)}
            if s.restReminder?.materialID=="" {s.restReminder?.materialID="cat"}
        }
    }
}
