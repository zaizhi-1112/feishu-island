@testable import IslandLegacyFixtures
import Foundation
import AppKit
import AVFoundation
@testable import IslandShell

extension FusionTests {
    @MainActor func testScreenReminderSchedulingAndTransparency() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("island-reminder-synthetic-"+UUID().uuidString)
        let store=WorkspaceStore(root:root,startTimers:false)
        var requests:[ScreenReminderRequest]=[], notices=0
        store.presentScreenReminder={requests.append($0)}; store.notify={_ in notices+=1}
        let now=Date()
        let ordinary=try store.add(text:"合成：原有普通提醒",minutes:1)
        store.setReminder(ordinary,date:now.addingTimeInterval(-1))
        store.tickReminders(now:now)
        XCTAssertEqual(notices,1); XCTAssertEqual(requests.count,0)
        XCTAssertNil(store.disk.items.first?.screenReminder)
        let originalJSON=try JSONEncoder().encode(store.disk)
        var oldJSON=try JSONSerialization.jsonObject(with:originalJSON) as! [String:Any]
        oldJSON.removeValue(forKey:"screenSchedules"); oldJSON.removeValue(forKey:"screenMaterials")
        var oldItems=oldJSON["items"] as! [[String:Any]]; oldItems[0].removeValue(forKey:"screenReminder"); oldJSON["items"]=oldItems
        let migrated=try JSONDecoder().decode(WorkDisk.self,from:JSONSerialization.data(withJSONObject:oldJSON))
        XCTAssertNil(migrated.items.first?.screenReminder); XCTAssertNil(migrated.screenSchedules)
        let style=ScreenReminderStyle(materialID:"cat",durationSeconds:12)
        let selected=try store.add(text:"合成：开会前整理材料",minutes:1,screenReminder:style)
        store.setReminder(selected,date:now.addingTimeInterval(-1))
        store.tickReminders(now:now); store.tickReminders(now:now.addingTimeInterval(1))
        XCTAssertEqual(requests.count,1); XCTAssertEqual(requests.first?.style,style)
        let reread=WorkspaceStore(root:root,startTimers:false)
        reread.presentScreenReminder={requests.append($0)}; reread.tickReminders(now:now.addingTimeInterval(2))
        XCTAssertEqual(requests.count,1)
        XCTAssertTrue(reread.disk.items.first(where:{$0.id==selected})?.reminded == true)
        reread.complete(selected); reread.snooze(selected,minutes:1)
        reread.tickReminders(now:now.addingTimeInterval(200)); XCTAssertEqual(requests.count,1)

        let repeatID=try store.upsertScreenSchedule(title:"合成久坐",firstFire:now.addingTimeInterval(1),repeatMinutes:30,style:style)
        let onceID=try store.upsertScreenSchedule(title:"合成倒计时",firstFire:now.addingTimeInterval(1),repeatMinutes:nil,style:style)
        store.tickReminders(now:now); XCTAssertEqual(requests.count,1)
        let afterSleep=now.addingTimeInterval(86400)
        store.tickReminders(now:afterSleep)
        XCTAssertEqual(requests.count,2) // coalesced once, not 48 missed intervals
        XCTAssertTrue(requests.last!.title.contains("还有1项"))
        XCTAssertEqual(store.screenSchedules.first(where:{$0.id==repeatID})?.fireAt,afterSleep.addingTimeInterval(1800))
        XCTAssertFalse(store.screenSchedules.first(where:{$0.id==onceID})!.enabled)
        store.tickReminders(now:afterSleep.addingTimeInterval(1)); XCTAssertEqual(requests.count,2)
        store.setScreenScheduleEnabled(repeatID,enabled:false)
        store.tickReminders(now:afterSleep.addingTimeInterval(3600)); XCTAssertEqual(requests.count,2)
        store.deleteScreenSchedule(onceID); XCTAssertFalse(store.screenSchedules.contains(where:{$0.id==onceID}))
        do { _=try store.upsertScreenSchedule(title:"合成无效间隔",firstFire:now,repeatMinutes:0,style:style); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        do { _=try store.upsertScreenSchedule(title:"合成无效素材",firstFire:now,repeatMinutes:1,style:.init(materialID:"../../private",durationSeconds:5)); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        do { _=try store.upsertScreenSchedule(id:UUID(),title:"合成已删提醒",firstFire:now,repeatMinutes:1,style:style); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        let final=WorkspaceStore(root:root,startTimers:false)
        XCTAssertEqual(final.screenSchedules.count,1); XCTAssertFalse(final.screenSchedules[0].enabled)
        do { try final.previewScreenReminder(style); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }

        let hidden=ScreenReminderPresenter(displaysWindows:false,sessionIsLocked:{false})
        let request=try store.screenReminderRequest(style:style,title:"合成离屏检查")
        try hidden.present(request,testFrame:CGRect(x:0,y:0,width:800,height:600))
        XCTAssertEqual(hidden.verificationWindows.count,2)
        XCTAssertTrue(hidden.verificationWindows.allSatisfy{!$0.isVisible && !$0.isOpaque && !$0.canBecomeKey && !$0.canBecomeMain})
        XCTAssertTrue(hidden.verificationWindows.first!.ignoresMouseEvents)
        XCTAssertFalse(hidden.verificationWindows.last!.ignoresMouseEvents)
        XCTAssertEqual(hidden.verificationWindows.first!.backgroundColor,.clear)
        XCTAssertLessThan(hidden.verificationWindows.last!.frame.width,150)
        hidden.dismiss(); XCTAssertEqual(hidden.verificationWindows.count,0)
        let locked=ScreenReminderPresenter(displaysWindows:false,sessionIsLocked:{true})
        do { try locked.present(request,testFrame:CGRect(x:0,y:0,width:800,height:600)); XCTAssertTrue(false) } catch { XCTAssertEqual(locked.verificationWindows.count,0) }
        XCTAssertEqual(ScreenReminderRules.playbackSeconds(request),12)
        var long=request; long.material.durationSeconds=119.8; XCTAssertEqual(ScreenReminderRules.playbackSeconds(long),120)
        XCTAssertLessThan(ScreenReminderRules.visualFrame(in:CGSize(width:800,height:600),hasAlpha:false).width,400)

        let evidence=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/screen-reminder-evidence")
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        let personal=root.appendingPathComponent("not-video.mov"); try Data("合成非视频".utf8).write(to:personal)
        do { _=try await store.importScreenReminderVideo(personal); XCTAssertTrue(false) } catch { XCTAssertEqual(store.disk.screenMaterials?.count ?? 0,0) }
        XCTAssertEqual(try String(contentsOf:personal,encoding:.utf8),"合成非视频")
        let link=root.appendingPathComponent("linked.mov"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:personal)
        do { try ScreenReminderMedia.validateFile(link); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        let bad=ScreenReminderMaterial(id:"synthetic",name:"合成越界",filename:"../../private.mov",durationSeconds:1,hasAlpha:false)
        do { _=try ScreenReminderMedia.ownedURL(bad,root:root); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        // The shipped AI-generated portal is a non-personal fixture. Inspect its
        // real alpha track, import a private copy, and preserve the source bytes.
        let portal=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/ScreenReminder/rick-portal.mov")
        let original=try Data(contentsOf:portal)
        let imported=try await store.importScreenReminderVideo(portal)
        XCTAssertTrue(imported.hasAlpha)
        XCTAssertTrue(abs(imported.durationSeconds-10)<0.2)
        let owned=try ScreenReminderMedia.ownedURL(imported,root:root)
        XCTAssertEqual(try Data(contentsOf:owned),original)
        XCTAssertEqual(try Data(contentsOf:portal),original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:owned.path)[.posixPermissions] as? Int,0o600)
        let persisted=WorkspaceStore(root:root,startTimers:false)
        XCTAssertEqual(persisted.disk.screenMaterials?.first?.id,imported.id)
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:owned)); generator.appliesPreferredTrackTransform=true
        let (frame,_)=try await generator.image(at:CMTime(seconds:2,preferredTimescale:600))
        let bitmap=NSBitmapImageRep(cgImage:frame)
        var transparent=0, opaque=0
        for y in stride(from:0,to:bitmap.pixelsHigh,by:16) { for x in stride(from:0,to:bitmap.pixelsWide,by:16) {
            let alpha=bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 1
            if alpha<0.05 { transparent+=1 }; if alpha>0.95 { opaque+=1 }
        } }
        XCTAssertGreaterThan(transparent,100); XCTAssertGreaterThan(opaque,10)
        try bitmap.representation(using:.png,properties:[:])!.write(to:evidence.appendingPathComponent("rick-alpha-frame.png"))
    }
}
