import Foundation
import SQLite3
@testable import IslandShell


var assertionCount = 0
func check(_ value: Bool, _ label: String = #function, line: Int = #line) {
    guard value else { fputs("FAIL line \(line): \(label)\n", stderr); exit(1) }; assertionCount += 1
}
func XCTAssertTrue(_ value: Bool, line: Int = #line) { check(value, line: line) }
func XCTAssertFalse(_ value: Bool, line: Int = #line) { check(!value, line: line) }
func XCTAssertNil<T>(_ value: T?, line: Int = #line) { check(value == nil, line: line) }
func XCTAssertNotNil<T>(_ value: T?, line: Int = #line) { check(value != nil, line: line) }
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, line: Int = #line) { check(lhs == rhs, "\(lhs) != \(rhs)", line: line) }
func XCTAssertEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, line: Int = #line) { check(abs(lhs-rhs) <= accuracy, line: line) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, line: Int = #line) { do { _ = try expression(); check(false, line: line) } catch { assertionCount += 1 } }

final class AgentTests {
    let now = 1_000_000.0
    func session(_ id: String, _ state: AgentState, _ time: Double) -> AgentSession { .init(id: id, state: state, updatedAt: time) }
    func quota(_ left: Double, reset: Double? = 1_010_000) -> AgentQuota { .init(id: "week", label: "周额度", remainingPercent: left, resetsAt: reset, updatedAt: now) }
    func testConcurrentSessionsKeepWorking() {
        let snapshot = AgentSnapshot(sessions: [session("a", .working, now-10),session("b", .completed, now)])
        XCTAssertEqual(snapshot.state(now: now), .working)
    }
    func testStaleRunningCannotTurnGreen() {
        let snapshot = AgentSnapshot(sessions: [session("a", .working, now-1800),session("b", .completed, now)])
        XCTAssertEqual(snapshot.state(now: now), .unknown)
    }
    func testMissingAndFutureDataAreUnknown() {
        XCTAssertEqual(AgentSnapshot().state(now: now), .unknown)
        XCTAssertEqual(AgentSnapshot(sessions: [session("future", .working, now+120)]).state(now: now), .unknown)
        XCTAssertEqual(AgentSnapshot(sessions: [session("done", .completed, now-1800)]).state(now: now), .unknown)
    }
    func testCompletionRequiresObservedTransition() {
        var tracker = AgentAlertTracker()
        XCTAssertEqual(tracker.completions([session("old", .completed, now-1)], now: now), 0)
        XCTAssertEqual(tracker.completions([session("a", .working, now)], now: now), 0)
        XCTAssertEqual(tracker.completions([session("a", .completed, now+2)], now: now+2), 1)
        XCTAssertEqual(tracker.completions([session("a", .completed, now+2)], now: now+4), 0)
    }
    func testFailureNeverCountsAsSuccess() {
        var tracker = AgentAlertTracker()
        _ = tracker.completions([session("a", .working, now)], now: now)
        XCTAssertEqual(tracker.completions([session("a", .failed, now+1)], now: now+1), 0)
    }
    func testFastCompletionsBetweenPolls() {
        var tracker = AgentAlertTracker()
        let old = AgentSession(id:"existing",state:.completed,updatedAt:now-1,completionID:"turn1")
        XCTAssertEqual(tracker.completions([old],now:now),0)
        let fast = AgentSession(id:"existing",state:.completed,updatedAt:now+1,completionID:"turn2")
        let new = session("new",.completed,now+1)
        XCTAssertEqual(tracker.completions([fast,new],now:now+2),2)
        XCTAssertEqual(tracker.completions([fast,new],now:now+3),0)
        // Metadata updates to an already completed database row are not task completions.
        XCTAssertEqual(tracker.completions([fast,session("new",.completed,now+4)],now:now+5),0)
        XCTAssertEqual(tracker.completions([fast,session("historical",.completed,now-1)],now:now+6),0)
        XCTAssertEqual(tracker.completions([fast,session("discovered-later",.completed,now+2)],now:now+8),1)
    }
    func testThresholdStrictlyBelowTwentyAndDeduplicated() {
        var tracker = AgentAlertTracker()
        XCTAssertTrue(tracker.lowQuotas([quota(20)], profile: "codex", now: now).isEmpty)
        XCTAssertEqual(tracker.lowQuotas([quota(19.9)], profile: "codex", now: now).count, 1)
        XCTAssertTrue(tracker.lowQuotas([quota(18)], profile: "codex", now: now).isEmpty)
        XCTAssertEqual(tracker.lowQuotas([quota(19, reset: 1_020_000)], profile: "codex", now: now).count, 1)
        XCTAssertEqual(tracker.lowQuotas([quota(19)], profile: "workbuddy", now: now).count, 1)
    }
    func testNonResetCreditPoolRearmsAfterRecovery() {
        var tracker = AgentAlertTracker()
        XCTAssertEqual(tracker.lowQuotas([quota(19,reset:nil)], profile: "w", now: now).count, 1)
        XCTAssertTrue(tracker.lowQuotas([quota(50,reset:nil)], profile: "w", now: now).isEmpty)
        XCTAssertEqual(tracker.lowQuotas([quota(19,reset:nil)], profile: "w", now: now).count, 1)
    }
    func testExpiredAndInvalidQuotasNeverAlert() {
        var tracker = AgentAlertTracker()
        XCTAssertTrue(tracker.lowQuotas([quota(1,reset:now-1)], profile: "c", now: now).isEmpty)
        XCTAssertTrue(tracker.lowQuotas([quota(1)], profile: "c", now: now+901).isEmpty)
        XCTAssertFalse(quota(-1).isFresh(now: now))
        XCTAssertFalse(quota(.nan).isFresh(now: now))
        XCTAssertNotNil(AgentSnapshot(quotas: [quota(101)]).validationError)
        XCTAssertNotNil(AgentSnapshot(quotas: [quota(12),quota(13)]).validationError)
    }
    func testCodexUsesActualDurationAndMultipleBuckets() {
        let raw: [String: Any] = ["rateLimitsByLimitId": ["codex": ["primary":["usedPercent":18.0,"windowDurationMins":10080.0,"resetsAt":1_010_000]], "spark":["primary":["usedPercent":90.0,"windowDurationMins":300.0]]]]
        let values = CodexReader.parseQuotas(raw, now: now)
        XCTAssertEqual(values.count,2)
        XCTAssertEqual(values[0].remainingPercent,82)
        XCTAssertTrue(values[0].label.contains("周额度"))
        XCTAssertTrue(values[1].label.contains("5小时"))
    }
    func testMissingCodexWindowsAreNotZero() {
        XCTAssertTrue(CodexReader.parseQuotas([:],now:now).isEmpty)
        XCTAssertTrue(CodexReader.parseQuotas(["rateLimits":["primary":NSNull()]],now:now).isEmpty)
    }
    func testCompactQuotaWindowsAndFreshness() throws {
        let raw:[String:Any] = ["rateLimitsByLimitId":["codex":["primary":["usedPercent":7.0,"windowDurationMins":10080.0,"resetsAt":1_010_000.0]]]]
        let week=CodexReader.parseQuotas(raw,now:now)
        let summary=AgentQuotaCompactSummary(quotas:week,refreshing:false,now:now)
        XCTAssertEqual(summary.text(leading:true),"Codex")
        XCTAssertEqual(summary.text(leading:false),"周 93%")
        XCTAssertEqual(summary.accessibility(leading:false),"Codex 周额度剩余 93%")
        XCTAssertEqual(summary.windows.count,1)
        let other=AgentQuota(id:"spark/primary",label:"5小时额度",remainingPercent:3,resetsAt:nil,updatedAt:now)
        XCTAssertEqual(AgentQuotaCompactSummary(quotas:[other],refreshing:false,now:now).text(leading:false),"额度未知")
        let five=AgentQuota(id:"codex/primary",label:"5小时额度",remainingPercent:0,resetsAt:nil,updatedAt:now)
        var second=week[0];second.id="codex/secondary"
        let both=AgentQuotaCompactSummary(quotas:[five,second,other],refreshing:false,now:now)
        XCTAssertEqual(both.text(leading:true),"5h 0%")
        XCTAssertEqual(both.text(leading:false),"周 93%")
        XCTAssertEqual(AgentQuotaCompactSummary(quotas:week,refreshing:false,now:now+901).text(leading:false),"待刷新")
        XCTAssertEqual(AgentQuotaCompactSummary(quotas:[],refreshing:true,now:now).text(leading:false),"读取中")
        XCTAssertEqual(AgentQuotaCompactSummary(quotas:[],refreshing:false,now:now).text(leading:false),"额度未知")
        var old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(AgentPreferences())) as! [String:Any]
        old.removeValue(forKey:"quotaDisplayEnabled")
        let migrated=try JSONDecoder().decode(AgentPreferences.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertFalse(migrated.quotaDisplayEnabled)
        var enabled=migrated;enabled.quotaDisplayEnabled=true
        let reloaded=try JSONDecoder().decode(AgentPreferences.self,from:JSONEncoder().encode(enabled))
        XCTAssertTrue(reloaded.quotaDisplayEnabled);XCTAssertFalse(reloaded.enabled)
        XCTAssertEqual(reloaded.visibleIDs,migrated.visibleIDs)
    }
    func testClaudeContextUsageIsNotSubscriptionQuota() {
        XCTAssertTrue(AgentBridge.claudeQuotas(["context_window":["used_percentage":99]],now:now).isEmpty)
        let quotas = AgentBridge.claudeQuotas(["five_hour":["used_percentage":80.5,"resets_at":1_010_000]],now:now)
        XCTAssertEqual(quotas.first?.remainingPercent,19.5)
    }
    func testWorkBuddyUsesCreditGroupsWithoutDoubleCountingPackages() throws {
        let raw: [String:Any] = ["TotalCredits":"542.12","Packages":[["CycleTotalCapacity":"3231"]],"CreditGroups":[["CycleTotalCapacity":"500"],["CycleTotalCapacity":"2731"]]]
        let quotas = try WorkBuddyReader.parseQuotas(raw,now:now)
        XCTAssertEqual(quotas[0].totalUnits,3231)
        XCTAssertEqual(quotas[0].remainingUnits,542.12)
        XCTAssertEqual(quotas[0].remainingPercent,16.7787,accuracy:0.001)
    }
    func testWorkBuddyRejectsIncompleteOrZeroTotals() {
        XCTAssertThrowsError(try WorkBuddyReader.parseQuotas(["TotalCredits":"5","CreditGroups":[["CycleTotalCapacity":"unknown"]]],now:now))
        XCTAssertThrowsError(try WorkBuddyReader.parseQuotas(["TotalCredits":"0","CreditGroups":[]],now:now))
    }
    func testPreferencesValidatePrimaryAndIDs() {
        var preferences = AgentPreferences()
        XCTAssertNil(preferences.validationError)
        preferences.primaryID = "missing"; XCTAssertNotNil(preferences.validationError)
        XCTAssertFalse(AgentBridge.validID("../escape"))
        XCTAssertFalse(AgentBridge.validID("a/b"))
    }
    func testDisplayPreferencesMigrationAndSelection() throws {
        var original = AgentPreferences()
        original.revision = 17; original.primaryID = "workbuddy"; original.completionAlerts = false
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "visibleIDs")
        var migrated = try JSONDecoder().decode(AgentPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.visibleProfiles.count,3)
        XCTAssertEqual(migrated.primaryID,"workbuddy")
        XCTAssertEqual(migrated.revision,17); XCTAssertFalse(migrated.completionAlerts)
        migrated.setVisibleIDs(["codex"])
        XCTAssertEqual(migrated.primaryID,"codex"); XCTAssertEqual(migrated.profiles.count,3)
        XCTAssertEqual(migrated.visibleProfiles.map(\.id),["codex"]); XCTAssertNil(migrated.validationError)
        migrated.setVisibleIDs(["codex","workbuddy"])
        XCTAssertEqual(migrated.visibleProfiles.count,2)
        let restored = try JSONDecoder().decode(AgentPreferences.self,from:JSONEncoder().encode(migrated))
        XCTAssertEqual(restored.visibleIDs,["codex","workbuddy"])
        migrated.setVisibleIDs([]); XCTAssertNotNil(migrated.validationError)
        migrated.setVisibleIDs(["missing"]); XCTAssertNotNil(migrated.validationError)
        migrated.setVisibleIDs(["codex","codex"]); XCTAssertNotNil(migrated.validationError)
    }
    func testSkinPreferenceMigrationAndIndependence() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AgentPreferences())) as! [String: Any]
        legacy.removeValue(forKey: "skinID")
        var preferences = try JSONDecoder().decode(AgentPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(preferences.skinID, "auto")
        preferences.skinID = "workbuddy"
        preferences.setVisibleIDs(["codex"])
        XCTAssertEqual(preferences.primaryID, "codex")
        XCTAssertEqual(preferences.skinID, "workbuddy")
        XCTAssertNil(preferences.validationError)
        let restored = try JSONDecoder().decode(AgentPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.skinID, "workbuddy")
        XCTAssertEqual(restored.primaryID, "codex")
        preferences.skinID = "invalid"
        XCTAssertNotNil(preferences.validationError)
    }
    func testFourSkinAssetsAndReducedMotionMigration() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AgentPreferences())) as! [String: Any]
        legacy.removeValue(forKey: "effectsEnabled")
        let migrated = try JSONDecoder().decode(AgentPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(migrated.effectsEnabled)
        for skin in AgentSkin.allCases {
            var prefs = migrated; prefs.skinID = skin.rawValue; prefs.effectsEnabled = false
            prefs.primaryID = "workbuddy"
            XCTAssertNil(prefs.validationError)
            let restored = try JSONDecoder().decode(AgentPreferences.self, from: JSONEncoder().encode(prefs))
            XCTAssertEqual(restored.skinID,skin.rawValue); XCTAssertFalse(restored.effectsEnabled)
            XCTAssertEqual(restored.primaryID,"workbuddy")
            XCTAssertFalse(skin.definition.source.isEmpty)
        }
        XCTAssertEqual(SkinManifest.shared.skins.count,4)
        for id in ["codex","claude","workbuddy"] {
            let art = SkinManifest.shared.agents[id]!
            XCTAssertNotNil(SkinResources.images[art.portrait]); XCTAssertNotNil(SkinResources.images[art.avatar])
        }
        XCTAssertTrue(SkinResources.brandLanes.count>200)
        XCTAssertTrue(SkinResources.brandLanes.allSatisfy { $0.length>0 && $0.length.isFinite })
        // Away from the body, incompressibility survives the wall taper.
        for point in [CGPoint(x:0.1,y:0.3),CGPoint(x:0.72,y:0.2),CGPoint(x:0.5,y:0.4)] {
            let e=0.00001,x=Double(point.x),y=Double(point.y)
            let left=SkinFlowField.velocity(x:x-e,y:y,time:10,pointer:nil),right=SkinFlowField.velocity(x:x+e,y:y,time:10,pointer:nil)
            let up=SkinFlowField.velocity(x:x,y:y-e,time:10,pointer:nil),down=SkinFlowField.velocity(x:x,y:y+e,time:10,pointer:nil)
            XCTAssertEqual((right.x-left.x+down.y-up.y)/(2*e),0,accuracy:0.00001)
        }
        // The pointer is a regularized physical perturbation, including at its center.
        for x in stride(from:0.0,through:1.0,by:0.05) {
            for y in stride(from:0.0,through:0.7,by:0.05) {
                let v=SkinFlowField.velocity(x:x,y:y,time:100,pointer:CGPoint(x:x,y:y))
                XCTAssertTrue(v.x.isFinite && v.y.isFinite && abs(v.x)<1 && abs(v.y)<1)
            }
        }
    }
    func testWorkBuddyTaskDatabaseAndAccountIsolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-workbuddy-checks-\(UUID().uuidString)")
        let skeleton = root.appendingPathComponent("storage/skeleton")
        try FileManager.default.createDirectory(at:skeleton,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try Data("{\"primary\":{\"uid\":\"test-current\"}}".utf8).write(to:skeleton.appendingPathComponent("account-snapshot.json"))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("workbuddy.db").path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE sessions (id TEXT, user_id TEXT, status TEXT, updated_at REAL, deleted_at REAL);
        INSERT INTO sessions VALUES ('active','test-current','planning',1000000000,NULL),('old','test-current','completed',999999000,NULL),('other-user','someone-else','working',1000000000,NULL),('deleted','test-current','working',1000000000,1);
        """
        XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK)
        let active = try WorkBuddyReader.sessions(now:now,root:root)
        XCTAssertEqual(active.count,2); XCTAssertEqual(AgentSnapshot(sessions:active).state(now:now),.working)
        XCTAssertEqual(sqlite3_exec(db,"UPDATE sessions SET status='completed',updated_at=1000001000 WHERE id='active'",nil,nil,nil),SQLITE_OK)
        let completed = try WorkBuddyReader.sessions(now:now+1,root:root)
        XCTAssertEqual(AgentSnapshot(sessions:completed).state(now:now+1),.completed)
        var tracker = AgentAlertTracker(); _ = tracker.completions(active,now:now)
        XCTAssertEqual(tracker.completions(completed,now:now+1),1)
        XCTAssertEqual(sqlite3_exec(db,"UPDATE sessions SET status='terminated',updated_at=1000002000 WHERE id='active'",nil,nil,nil),SQLITE_OK)
        XCTAssertEqual(AgentSnapshot(sessions:try WorkBuddyReader.sessions(now:now+2,root:root)).state(now:now+2),.failed)
    }
    func testStartAlertsDoNotReplayHistory() {
        var tracker=AgentAlertTracker()
        XCTAssertEqual(tracker.starts([session("existing",.working,now)],now:now),0)
        XCTAssertEqual(tracker.starts([session("existing",.working,now),session("new",.working,now+1)],now:now+1),1)
        XCTAssertEqual(tracker.starts([session("existing",.working,now),session("new",.working,now+1)],now:now+2),0)
        XCTAssertEqual(tracker.starts([session("new",.waiting,now+3)],now:now+3),0)
        XCTAssertEqual(tracker.starts([session("new",.working,now+4)],now:now+4),1)
        XCTAssertEqual(tracker.starts([session("stale",.working,now-100)],now:now+5),0)
    }
    func testClaudeAndWorkBuddyPassiveLifecycle() throws {
        for provider in ["claude", "workbuddy"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("state40-"+UUID().uuidString)
            let folder=root.appendingPathComponent(provider)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var previous:AgentHookRecord?
            var tracker=AgentAlertTracker()
            _=tracker.completions([],now:now-1);_=tracker.attentionRequests([],now:now-1)
            for (offset,event,tool,expected,reason) in [
                (0.0,"UserPromptSubmit","",AgentState.working,nil as String?),
                (1.0,"PreToolUse","AskUserQuestion",.waiting,"input"),
                (2.0,"PostToolUse","AskUserQuestion",.working,nil),
                (3.0,"PermissionRequest","Bash",.waiting,"approval"),
                (4.0,"PostToolUse","Bash",.working,nil),
                (5.0,"Stop","",.completed,nil)
            ] {
                let input:[String:Any] = ["session_id":"synthetic-"+provider,"hook_event_name":event,"tool_name":tool,"prompt":"SECRET-PROMPT","tool_input":["password":"NEVER-SAVE"],"tool_response":"PRIVATE-RESULT","cwd":"/secret/path"]
                let record=AgentHookRecord.reduce(input,previous:previous,now:now+offset)!
                let encoded=try JSONEncoder().encode(record)
                try encoded.write(to:folder.appendingPathComponent(record.id+".json"))
                let sessions=AgentStatusConnection.sessions(provider:provider,now:now+offset,root:root)
                XCTAssertEqual(sessions.count,1);XCTAssertEqual(sessions[0].state,expected)
                XCTAssertEqual(sessions[0].attentionReason,reason)
                let attention=tracker.attentionRequests(sessions,now:now+offset)
                XCTAssertEqual(attention.count,expected == .waiting ? 1:0)
                XCTAssertTrue(tracker.attentionRequests(sessions,now:now+offset).isEmpty)
                XCTAssertEqual(tracker.completions(sessions,now:now+offset),expected == .completed ? 1:0)
                let text=String(decoding:encoded,as:UTF8.self)
                for excluded in ["SECRET-PROMPT","NEVER-SAVE","PRIVATE-RESULT","/secret/path","synthetic-"] { XCTAssertFalse(text.contains(excluded)) }
                previous=record
            }
            XCTAssertNil(AgentHookRecord.reduce(["session_id":"synthetic","hook_event_name":"Notification","notification_type":"idle_prompt"],previous:previous,now:now+6))
            XCTAssertNil(AgentHookRecord.reduce(["session_id":"synthetic","hook_event_name":"SessionEnd"],previous:previous,now:now+6))
            XCTAssertTrue(AgentStatusConnection.sessions(provider:provider,now:now+86410,root:root).isEmpty)
            let wait=AgentHookRecord.reduce(["session_id":"same","hook_event_name":"PermissionRequest"],previous:nil,now:now)!
            let repeatWait=AgentHookRecord.reduce(["session_id":"same","hook_event_name":"Notification","notification_type":"permission_prompt"],previous:wait,now:now+1)!
            XCTAssertEqual(wait.attentionID,repeatWait.attentionID)
            let a=AgentSession(id:wait.id,state:.working,updatedAt:now+1)
            let b=AgentSession(id:wait.id,state:.waiting,updatedAt:now,attentionID:wait.attentionID,attentionReason:"approval")
            XCTAssertEqual(AgentStatusConnection.merge(database:[a],events:[b],now:now+1).first?.state,.waiting)
            XCTAssertEqual(AgentStatusConnection.merge(database:[AgentSession(id:wait.id,state:.completed,updatedAt:now+2)],events:[b],now:now+3).first?.state,.completed)
        }
    }
    func testCodexInputAndApprovalTransitions() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("agent-control-fixture-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let log=root.appendingPathComponent("control.jsonl"),date=Date(),formatter=ISO8601DateFormatter()
        formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        FileManager.default.createFile(atPath:log.path,contents:nil)
        let handle=try FileHandle(forWritingTo:log);defer{try? handle.close()}
        let reader=CodexReader(root:root)
        func append(_ kind:String,_ payload:[String:Any],_ offset:Double) throws {
            var bytes=try JSONSerialization.data(withJSONObject:["type":kind,"timestamp":formatter.string(from:date.addingTimeInterval(offset)),"payload":payload]);bytes.append(10);try handle.write(contentsOf:bytes)
        }
        try append("event_msg",["type":"task_started","turn_id":"synthetic-turn"],0)
        var sessions=await reader.sessions(now:date)
        XCTAssertEqual(sessions.first?.state,.working)
        try append("response_item",["type":"function_call","name":"functions.request_user_input","call_id":"synthetic-input","arguments":"DO_NOT_RETAIN_QUESTION_OR_SECRET"],1)
        sessions=await reader.sessions(now:date.addingTimeInterval(1))
        XCTAssertEqual(sessions.first?.state,.waiting);XCTAssertEqual(sessions.first?.attentionReason,"input")
        var tracker=AgentAlertTracker()
        XCTAssertEqual(tracker.attentionRequests(sessions,now:date.timeIntervalSince1970+1).count,1)
        XCTAssertTrue(tracker.attentionRequests(sessions,now:date.timeIntervalSince1970+2).isEmpty)
        try append("response_item",["type":"function_call_output","call_id":"wrong-input","output":"DO_NOT_RETAIN_RESPONSE"],2)
        XCTAssertEqual(await reader.sessions(now:date.addingTimeInterval(2)).first?.state,.waiting)
        try append("response_item",["type":"function_call_output","call_id":"synthetic-input","output":"DO_NOT_RETAIN_RESPONSE"],3)
        XCTAssertEqual(await reader.sessions(now:date.addingTimeInterval(3)).first?.state,.working)
        try append("event_msg",["type":"exec_approval_request","call_id":"synthetic-approval","turn_id":"synthetic-turn"],4)
        sessions=await reader.sessions(now:date.addingTimeInterval(4))
        XCTAssertEqual(sessions.first?.state,.waiting);XCTAssertEqual(sessions.first?.attentionReason,"approval")
        XCTAssertEqual(tracker.attentionRequests(sessions,now:date.timeIntervalSince1970+4).count,1)
        try append("event_msg",["type":"exec_command_begin","call_id":"synthetic-approval","turn_id":"other-turn"],5)
        XCTAssertEqual(await reader.sessions(now:date.addingTimeInterval(5)).first?.state,.waiting)
        try append("event_msg",["type":"exec_command_begin","call_id":"synthetic-approval","turn_id":"synthetic-turn"],6)
        sessions=await reader.sessions(now:date.addingTimeInterval(6));XCTAssertEqual(sessions.first?.state,.working)
        _=tracker.completions(sessions,now:date.timeIntervalSince1970+6)
        try append("event_msg",["type":"task_complete","turn_id":"synthetic-turn"],7)
        sessions=await reader.sessions(now:date.addingTimeInterval(7))
        XCTAssertEqual(sessions.first?.state,.completed)
        XCTAssertEqual(tracker.completions(sessions,now:date.timeIntervalSince1970+7),1)
        XCTAssertEqual(tracker.completions(sessions,now:date.timeIntervalSince1970+8),0)
        let encoded=String(decoding:try JSONEncoder().encode(sessions),as:UTF8.self)
        XCTAssertFalse(encoded.contains("DO_NOT_RETAIN"))
        try append("event_msg",["type":"task_started","turn_id":"async-turn"],8)
        try append("response_item",["type":"function_call","name":"functions.request_user_input_async","call_id":"async-input"],9)
        try append("response_item",["type":"function_call_output","call_id":"async-input","output":"queued"],9.5)
        XCTAssertEqual(await reader.sessions(now:date.addingTimeInterval(10)).first?.state,.working)
        try append("event_msg",["type":"task_complete","turn_id":"async-turn"],11)
        sessions=await reader.sessions(now:date.addingTimeInterval(11))
        XCTAssertEqual(sessions.first?.state,.waiting);XCTAssertEqual(sessions.first?.attentionID,"async-input")
    }
    func testAgentIdentityAndActivePriority() {
        var prefs=AgentPreferences();prefs.enabled=true;prefs.visibleIDs=["codex","workbuddy"]
        let snapshots=["codex":AgentSnapshot(sessions:[session("c",.working,now)]),"workbuddy":AgentSnapshot(sessions:[session("w",.waiting,now)])]
        XCTAssertEqual(AgentActivityDisplay.activeAgent(snapshots:snapshots,preferences:prefs,fallback:"codex",now:now),"workbuddy")
        XCTAssertEqual(AgentActivityDisplay.activeAgent(snapshots:snapshots,preferences:prefs,fallback:"dot",now:now+901),"dot")
        prefs.enabled=false
        XCTAssertEqual(AgentActivityDisplay.activeAgent(snapshots:snapshots,preferences:prefs,fallback:"claude",now:now),"claude")
        let work=AgentQuotaCompactSummary(quotas:[quota(81)],refreshing:false,now:now,agentID:"workbuddy",state:.working)
        XCTAssertEqual(work.text(leading:true),"WorkBuddy");XCTAssertTrue(work.text(leading:false).contains("运行中"))
        let dot=AgentQuotaCompactSummary(quotas:[quota(81)],refreshing:false,now:now,agentID:"dot",state:.working)
        XCTAssertEqual(dot.text(leading:true),"Dot");XCTAssertEqual(dot.text(leading:false),"运行中");XCTAssertTrue(dot.windows.isEmpty)
        let waiting=AgentCompletionNotice(profileID:"codex",name:"Codex",count:1,stillWorking:false,attention:"input")
        XCTAssertEqual(waiting.status,"等你输入");XCTAssertFalse(waiting.message.contains("已完成"))
        var t=AgentAlertTracker();let old=AgentSession(id:"old",state:.waiting,updatedAt:now-120,attentionID:"old")
        XCTAssertTrue(t.attentionRequests([old],now:now).isEmpty)
        let first=AgentSession(id:"new",state:.waiting,updatedAt:now,attentionID:"request1")
        XCTAssertEqual(t.attentionRequests([first],now:now).count,1)
        var repeated=first;repeated.updatedAt=now+10
        XCTAssertTrue(t.attentionRequests([repeated],now:now+10).isEmpty)
        repeated.attentionID="request2"
        XCTAssertEqual(t.attentionRequests([repeated],now:now+10).count,1)
    }
    func testResumedOldCodexChatAndIncrementalCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-agent-checks-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("2020/01/01")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = directory.appendingPathComponent("resumed.jsonl")
        let date = Date(), formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func record(_ type: String, turn: String = "current", after: Double = 0) throws -> Data {
            var bytes = try JSONSerialization.data(withJSONObject: ["timestamp":formatter.string(from:date.addingTimeInterval(after)),"type":"event_msg","payload":["type":type,"turn_id":turn]])
            bytes.append(10); return bytes
        }
        try record("task_started").write(to:log)
        let reader = CodexReader(root:root)
        let started = await reader.sessions(now:date)
        XCTAssertEqual(started.count,1); XCTAssertEqual(started.first?.state,.working)
        let handle = try FileHandle(forWritingTo:log); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf:record("task_complete",turn:"previous",after:1))
        let unrelated = await reader.sessions(now:date.addingTimeInterval(1))
        XCTAssertEqual(unrelated.first?.state,.working)
        let complete = try record("task_complete",after:2)
        try handle.write(contentsOf:complete.dropLast())
        let partial = await reader.sessions(now:date.addingTimeInterval(2))
        XCTAssertEqual(partial.first?.state,.working)
        try handle.write(contentsOf:Data([10]))
        let completed = await reader.sessions(now:date.addingTimeInterval(3))
        XCTAssertEqual(completed.first?.state,.completed)
        var tracker = AgentAlertTracker()
        _ = tracker.completions(started,now:date.timeIntervalSince1970)
        XCTAssertEqual(tracker.completions(completed,now:date.timeIntervalSince1970+3),1)
    }
}

let tests = AgentTests()
tests.testConcurrentSessionsKeepWorking()
tests.testStaleRunningCannotTurnGreen()
tests.testMissingAndFutureDataAreUnknown()
tests.testCompletionRequiresObservedTransition()
tests.testFailureNeverCountsAsSuccess()
tests.testFastCompletionsBetweenPolls()
tests.testThresholdStrictlyBelowTwentyAndDeduplicated()
tests.testNonResetCreditPoolRearmsAfterRecovery()
tests.testExpiredAndInvalidQuotasNeverAlert()
tests.testCodexUsesActualDurationAndMultipleBuckets()
tests.testMissingCodexWindowsAreNotZero()
try tests.testCompactQuotaWindowsAndFreshness()
tests.testClaudeContextUsageIsNotSubscriptionQuota()
try tests.testWorkBuddyUsesCreditGroupsWithoutDoubleCountingPackages()
tests.testWorkBuddyRejectsIncompleteOrZeroTotals()
tests.testPreferencesValidatePrimaryAndIDs()
try tests.testDisplayPreferencesMigrationAndSelection()
try tests.testSkinPreferenceMigrationAndIndependence()
try tests.testFourSkinAssetsAndReducedMotionMigration()
try tests.testWorkBuddyTaskDatabaseAndAccountIsolation()
try tests.testClaudeAndWorkBuddyPassiveLifecycle()
tests.testStartAlertsDoNotReplayHistory()
try await tests.testCodexInputAndApprovalTransitions()
tests.testAgentIdentityAndActivePriority()
try await tests.testResumedOldCodexChatAndIncrementalCompletion()
print("\(assertionCount) Agent checks passed.")
if CommandLine.arguments.contains("--live-read") {
    let codex = CodexReader()
    let sessions = await codex.sessions(now: Date())
    let codexQuotas = try await CodexReader.quotas()
    let workQuotas = try WorkBuddyReader.quotas(now: Date().timeIntervalSince1970)
    let workSessions = try WorkBuddyReader.sessions(now: Date().timeIntervalSince1970)
    let result: [String: Any] = [
        "codex": ["sessionCount":sessions.count,"state":AgentSnapshot(sessions:sessions).state(now:Date().timeIntervalSince1970).rawValue,"quotas":try JSONSerialization.jsonObject(with: JSONEncoder().encode(codexQuotas))],
        "workbuddy":["sessionCount":workSessions.count,"state":AgentSnapshot(sessions:workSessions).state(now:Date().timeIntervalSince1970).rawValue,"quotas":try JSONSerialization.jsonObject(with: JSONEncoder().encode(workQuotas))],
        "claude":"no signed-in account; desktop integration incomplete"
    ]
    print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
}
