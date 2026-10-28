@testable import IslandLegacyFixtures
import Foundation
@testable import IslandShell
extension FusionTests {
    func testDailyWorkBuddySchedulingAndRecovery() throws {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(secondsFromGMT:8*3600)!
        let base=ISO8601DateFormatter().date(from:"2026-10-25T01:09:59Z")!
        XCTAssertFalse(WorkBuddyCheckinSchedule.due(now:base,calendar:cal))
        XCTAssertTrue(WorkBuddyCheckinSchedule.due(now:base.addingTimeInterval(1),calendar:cal))
        XCTAssertTrue(WorkBuddyCheckinSchedule.due(now:base.addingTimeInterval(3600*12),calendar:cal))
        let date="2026-10-25", account="synthetic-account-A"
        var ledger:[WorkBuddyDailyFlow.Receipt]=[],clicks=0,verified=false,saves:[String]=[]
        func run(day:String=date,who:String=account,claimed:Bool=false,eligible:Bool=true,allow:Bool=true,storage:Bool=true)->String {
            WorkBuddyDailyFlow.run(day:day,account:who,claimed:claimed,eligible:eligible,allowClaim:allow,records:ledger,save:{state in
                guard storage else{return false};saves.append(state);ledger.removeAll{$0.day==day && $0.account==who};ledger.append(.init(day:day,account:who,state:state,checked:0));return true
            },press:{clicks+=1;XCTAssertEqual(saves.last,"attempted");return true},verify:{verified})
        }
        XCTAssertEqual(run(claimed:true),"already_claimed");XCTAssertEqual(clicks,0)
        XCTAssertEqual(run(eligible:false),"station_changed");XCTAssertEqual(clicks,0)
        XCTAssertEqual(run(allow:false),"not_claimed");XCTAssertEqual(clicks,0)
        XCTAssertEqual(run(storage:false),"storage_error");XCTAssertEqual(clicks,0)
        XCTAssertEqual(run(),"uncertain");XCTAssertEqual(clicks,1)
        XCTAssertEqual(run(),"uncertain");XCTAssertEqual(clicks,1) // restart must not repeat a press
        let encoded=try JSONEncoder().encode(ledger);ledger=try JSONDecoder().decode([WorkBuddyDailyFlow.Receipt].self,from:encoded)
        XCTAssertEqual(run(),"uncertain");XCTAssertEqual(clicks,1)
        verified=true;XCTAssertEqual(run(who:"synthetic-account-B"),"claimed");XCTAssertEqual(clicks,2)
        XCTAssertEqual(run(day:"2026-10-26"),"claimed");XCTAssertEqual(clicks,3)
        XCTAssertEqual(run(claimed:true),"already_claimed");XCTAssertEqual(clicks,3)
        XCTAssertEqual(ledger.first{$0.day==date && $0.account==account}?.state,"already_claimed")
        let suite="workbuddy-daily-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        let store=WorkBuddyCheckinStore(defaults:defaults);XCTAssertFalse(store.enabled)
        store.setEnabled(true);XCTAssertTrue(WorkBuddyCheckinStore(defaults:defaults).enabled)
        store.setEnabled(false);XCTAssertFalse(WorkBuddyCheckinStore(defaults:defaults).enabled)
        defaults.removePersistentDomain(forName:suite)
        let process=WorkBuddyCheckinProcess(),begin=Date()
        DispatchQueue.global().asyncAfter(deadline:.now()+0.1){process.cancel()}
        XCTAssertEqual(process.run(helper:URL(fileURLWithPath:"/bin/sleep"),arguments:["30"]),"cancelled")
        XCTAssertTrue(Date().timeIntervalSince(begin)<4)
        let never=WorkBuddyCheckinProcess();never.cancel()
        XCTAssertEqual(never.run(helper:URL(fileURLWithPath:"/bin/sleep"),arguments:["30"]),"cancelled")
    }
}
