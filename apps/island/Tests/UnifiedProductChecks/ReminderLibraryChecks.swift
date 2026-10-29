import AppKit
import AVFoundation
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runReminderLibraryChecks(check:(Bool,String)->Void) async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("island-media-check-"+UUID().uuidString)
    let store=WorkspaceStore(root:root,startTimers:false)
    check(store.screenMaterials.count==4 && store.restPlan.materialID=="cat","four bundled effects, walking cat is default")
    check(store.screenMaterials.first?.name=="猫咪走动" && !store.screenMaterials.contains{$0.name.contains("伸懒腰")},"old stretch removed")
    for material in store.screenMaterials {
        let request=try store.screenReminderRequest(style:.init(materialID:material.id),title:"合成预览")
        let url=request.videoURL!
        let info=try await ScreenReminderMedia.inspect(url)
        check(abs(info.duration-material.durationSeconds)<0.2,"packaged duration matches: "+material.id)
        check(info.alpha==material.hasAlpha,"packaged alpha matches: "+material.id)
        let asset=AVURLAsset(url:url)
        check(try await asset.load(.isPlayable),"native player decodes: "+material.id)
        let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true;generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        let (frame,_)=try await generator.image(at:CMTime(seconds:4,preferredTimescale:600))
        check(frame.width>0 && frame.height>0,"video frame decoded: "+material.id)
        if material.hasAlpha {
            let bitmap=NSBitmapImageRep(cgImage:frame)
            var transparent=0,opaque=0
            for y in stride(from:0,to:bitmap.pixelsHigh,by:16) {for x in stride(from:0,to:bitmap.pixelsWide,by:16) {
                let alpha=bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 1
                if alpha<0.05 {transparent += 1};if alpha>0.95 {opaque += 1}
            }}
            check(transparent>100 && opaque>10,"real transparent and visible pixels: "+material.id)
        }
    }
    let opaqueSource=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ScreenReminder/gemini-greeting.mp4")
    let sample=root.appendingPathComponent("opaque-import.mp4")
    let exporter=AVAssetExportSession(asset:AVURLAsset(url:opaqueSource),presetName:AVAssetExportPreset640x480)!
    exporter.timeRange=CMTimeRange(start:CMTime(seconds:2,preferredTimescale:600),duration:CMTime(seconds:1,preferredTimescale:600))
    try await exporter.export(to:sample,as:.mp4)
    let original=try Data(contentsOf:sample)
    let cutout=try await store.importScreenReminderVideo(sample)
    let cutoutURL=try ScreenReminderMedia.ownedURL(cutout,root:root)
    let cutoutInfo=try await ScreenReminderMedia.inspect(cutoutURL)
    check(cutout.hasAlpha && cutoutInfo.alpha,"opaque custom video is processed into a real alpha movie before saving")
    check(try Data(contentsOf:sample)==original,"custom video source stays unchanged after local background removal")
    check(store.removeScreenMaterial(cutout.id),"processed custom video can be removed")
    let presenter=ScreenReminderPresenter(displaysWindows:false,sessionIsLocked:{false})
    let cat=try store.screenReminderRequest(style:.init(),title:"合成猫咪")
    let rick=try store.screenReminderRequest(style:.init(materialID:"rick"),title:"合成传送门")
    let frame=CGRect(x:0,y:0,width:800,height:600)
    try presenter.present(cat,testFrame:frame);try presenter.present(cat,testFrame:frame);try presenter.present(rick,testFrame:frame)
    presenter.removeMaterial("cat")
    check(presenter.pendingCount==0 && presenter.deliveredTitles.last=="合成传送门","deleting current material removes queued copies and advances")
    check(presenter.verificationWindows.allSatisfy{!$0.isVisible && !$0.isOpaque && !$0.canBecomeKey},"effect windows stay transparent and do not take focus")
    presenter.dismissAll()
    let now=Date(),date=Date().addingTimeInterval(600)
    let task=try store.addTodo(title:"合成待办",now:now)
    let schedule=try store.upsertScreenSchedule(title:"合成计划",firstFire:date,repeatMinutes:30,style:.init())
    store.setRestEnabled(true,now:now)
    _=store.mutate {s in
        s.defaultTodoScreen = .init()
        s.items[0].screenReminder = .init();s.items[0].completionReminder = .init()
        var archived=s.items[0];archived.id=UUID();archived.archivedAt=now;s.items.append(archived)
        var trashed=s.items[0];trashed.id=UUID();s.trash=[trashed]
    }
    let restDate=store.restPlan.fireAt
    check(store.removeScreenMaterial("cat"),"in-use builtin can be removed")
    check(store.restPlan.materialID=="rick" && store.restPlan.fireAt==restDate,"rest fallback retains countdown")
    check(store.disk.defaultTodoScreen?.materialID=="rick" && store.disk.items.allSatisfy{$0.screenReminder?.materialID=="rick" && $0.completionReminder?.materialID=="rick"},"active and archived references replaced")
    check(store.disk.trash?.first?.completionReminder?.materialID=="rick","recoverable task references replaced")
    check(store.screenSchedules.first{$0.id==schedule}?.fireAt==date,"deletion never changes scheduled time")
    check(store.screenSchedules.first?.style.materialID=="rick","schedule fallback changed")
    check(store.disk.items.contains{$0.id==task},"task identity preserved")
    let reloaded=WorkspaceStore(root:root,startTimers:false)
    check(!reloaded.screenMaterials.contains{$0.id=="cat"},"removed builtin stays absent after reload")
    check(try reloaded.screenReminderRequest(style:.init(),title:"旧选择").material.id=="rick","stale selected material resolves available fallback")
    let source=ScreenReminderMedia.bundledURL("rick")!,sourceBytes=try Data(contentsOf:source)
    let imported=try await reloaded.importScreenReminderVideo(source)
    let copy=try ScreenReminderMedia.ownedURL(imported,root:root)
    reloaded.changeRest{$0.materialID=imported.id}
    check(reloaded.removeScreenMaterial(imported.id),"active imported video can be deleted")
    check(try !FileManager.default.fileExists(atPath:copy.path) && Data(contentsOf:source)==sourceBytes,"only imported copy moves to Trash, original preserved")
    for material in reloaded.screenMaterials {check(reloaded.removeScreenMaterial(material.id),"delete remaining "+material.id)}
    let empty=WorkspaceStore(root:root,startTimers:false)
    check(empty.screenMaterials.isEmpty && empty.disk.defaultTodoScreen==nil && empty.restPlan.materialID.isEmpty,"empty library persists without resurrecting builtins")
    check(empty.screenSchedules.allSatisfy{$0.lightOnly==true} && empty.disk.items.allSatisfy{$0.screenReminder==nil && $0.completionReminder==nil},"empty library switches effects to island text")
    var notices=0,effects=0;empty.notify={_ in notices += 1};empty.presentScreenReminder={_ in effects += 1}
    empty.tickRest(now:now.addingTimeInterval(3601),away:false)
    check(notices==1 && effects==0 && empty.error.isEmpty,"empty-library rest reminder still fires as text")
    empty.changeRest{$0.intervalMinutes=30};check(empty.restPlan.intervalMinutes==30,"rest remains editable when library empty")
    empty.restoreBuiltinScreenMaterials()
    check(empty.screenMaterials.count==4 && empty.restPlan.materialID=="cat","explicit restore returns bundled effects")
    check(WorkspaceStore(root:root,startTimers:false).screenMaterials.count==4,"explicit restore persists")
    let brokenRoot=root.appendingPathComponent("failed-save"),broken=WorkspaceStore(root:brokenRoot,startTimers:false)
    let file=brokenRoot.appendingPathComponent("workspace.json")
    try FileManager.default.moveItem(at:file,to:brokenRoot.appendingPathComponent("retained.json"));try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    check(!broken.removeScreenMaterial("cat") && broken.screenMaterials.count==4,"failed save never removes media")
    if let flag=CommandLine.arguments.firstIndex(of:"--render"),flag+1<CommandLine.arguments.count,CommandLine.arguments.contains("--reminders-only") {
        let output=URL(fileURLWithPath:CommandLine.arguments[flag+1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let theme=NookResolvedTheme.resolve(theme:AgentStore.shared.selectedSkin.theme,preferences:.init(chromePalette:.light),effectiveColorScheme:.light,reduceTransparency:true)
        for (name,s) in [("library",WorkspaceStore(root:root.appendingPathComponent("full-render"),startTimers:false)),("empty",WorkspaceStore(root:root.appendingPathComponent("empty-render"),startTimers:false))] {
            if name=="empty" {for m in s.screenMaterials {s.removeScreenMaterial(m.id)}}
            let view=NSHostingView(rootView:WorkspaceReminderLibrary(store:s,selected:.constant(s.screenMaterials.first?.id ?? "")).padding(24).frame(width:700).environment(\.nookResolvedTheme,theme).preferredColorScheme(.light).foregroundStyle(theme.primaryLabel).background(Color.white))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:640),styleMask:.borderless,backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=view
            view.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(250))
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"));window.close()
        }
    }
}
