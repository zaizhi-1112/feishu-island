@testable import IslandLegacyFixtures
import AppKit
import Foundation
@testable import IslandShell

extension FusionTests {
    func testAgentNoticeRoutingAndTiming() throws {
        let (s,d,suite)=store(); defer { d.removePersistentDomain(forName:suite) }
        var unreadQueries=0
        s.playback.checkUnread={_,_ in unreadQueries += 1}
        s.receiveAgentNotice(id:"agent-off",source:"Dot",text:"合成处理完成")
        XCTAssertEqual(s.playback.agentAccepted,0)
        s.updateDanmu(.init(enabled:true))
        s.receiveAgentNotice(id:"agent-one",source:"Dot",text:String(repeating:"合成长文\n",count:40))
        s.receiveAgentNotice(id:"agent-one",source:"Dot",text:"重复回执")
        XCTAssertEqual(s.playback.agentAccepted,1); XCTAssertTrue(s.messages.isEmpty)
        s.playback.overlay?.tick()
        XCTAssertEqual(unreadQueries,0); XCTAssertEqual(s.playback.visible,1)
        XCTAssertTrue(s.playback.overlay?.flying.first?.content.string.hasPrefix("Dot · ") == true)
        XCTAssertLessThan(s.playback.overlay?.flying.first?.content.string.count ?? 1000,90)
        s.toggleMute(); s.receiveAgentNotice(id:"muted",source:"Codex",text:"合成结果")
        XCTAssertEqual(s.playback.agentAccepted,1)
        s.toggleMute();s.playback.suspend(true)
        s.receiveAgentNotice(id:"locked",source:"豆包工作",text:"合成结果")
        XCTAssertEqual(s.playback.agentAccepted,1)
        s.playback.suspend(false);s.toggleReceiving()
        XCTAssertFalse(s.enabled)
        s.receiveAgentNotice(id:"agent-receiver-off",source:"Codex",text:"合成结果")
        XCTAssertEqual(s.playback.agentAccepted,2);XCTAssertTrue(s.messages.isEmpty)
        s.updateDanmu(.init(enabled:true,paused:true))
        s.receiveAgentNotice(id:"paused",source:"Dot",text:"合成结果")
        s.playback.overlay?.tick();XCTAssertEqual(s.playback.visible,0)
        XCTAssertFalse(s.playback.windowVisible)

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("agent-notice-check-"+UUID().uuidString)
        let work=WorkspaceStore(root:root,startTimers:false)
        var notices:[String]=[]
        work.agentNotice={_,source,text in notices.append(source+text)}
        let id=try work.add(text:"合成材料",minutes:0)
        try work.receiveAgentResult(id,text:"合成结果")
        try work.receiveAgentResult(id,text:"合成结果")
        XCTAssertEqual(notices.count,1);XCTAssertTrue(notices[0].hasPrefix("Agent"))
        let now=Date();work.setReminder(id,date:now.addingTimeInterval(-1))
        var todoNotices=0; work.notify={_ in todoNotices+=1}
        work.tickReminders(now:now);work.tickReminders(now:now)
        XCTAssertEqual(notices.count,1) // Todo reminders must not enter the Agent/danmu feed.
        XCTAssertEqual(todoNotices,1) // The unified todo module delivers one light reminder.
        var item=work.disk.items[0];item.service="dot";item.dotQueuedAt=now
        item.dotDeliveries=["test":DotDelivery(accepted:true,acceptedAt:now.addingTimeInterval(2))]
        item.aiStartedAt=now.addingTimeInterval(20)
        item.aiCompletedAt=now.addingTimeInterval(35)
        XCTAssertEqual(WorkTaskTiming.summary(item),"通知送达 2秒 · 等待领取 18秒 · 处理 15秒")
        item.service="codex";XCTAssertNil(WorkTaskTiming.summary(item))
        XCTAssertEqual(HubCardPresentation.displayText("1.完成材料。2.整理结果。3.继续计划"),"1.完成材料。\n\n2.整理结果。\n\n3.继续计划")
        XCTAssertEqual(HubCardPresentation.displayText("数值1.25，日期2026.10.24"),"数值1.25，日期2026.10.24")
    }
}
