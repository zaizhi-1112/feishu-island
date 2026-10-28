import AppKit
import Foundation

struct FeishuScheduleEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var appLink: String?
    var status = "confirmed"
    var offsets: [Int] = [1440,15]
    var consumed: [Date] = []
    var active: Bool { status == "confirmed" }
    var reminderText: String { offsets.isEmpty ? "不提醒" : offsets.sorted(by:>).map(Self.offsetText).joined(separator:"、") }
    static func offsetText(_ value: Int) -> String {
        if value == 0 { return "开始时" }
        if value % 1440 == 0 { return "提前\(value/1440)天" }
        if value % 60 == 0 { return "提前\(value/60)小时" }
        return "提前\(value)分钟"
    }
    var timeText: String {
        if allDay { return start.formatted(date:.abbreviated,time:.omitted)+" · 全天" }
        return start.formatted(date:.abbreviated,time:.shortened)+" — "+end.formatted(date:Calendar.current.isDate(start,inSameDayAs:end) ? .omitted:.abbreviated,time:.shortened)
    }
    var reminderDates: [Date] { offsets.map { start.addingTimeInterval(-Double($0)*60) } }
}
struct FeishuScheduleState: Codable, Equatable {
    var accountKey: String
    var enabled = true
    var calendarID: String?
    var events: [FeishuScheduleEvent] = []
    var lastSync: Date?
    static func key(_ connection: FeishuConnection) -> String? {
        connection.localAccount.map { $0.appID+":"+$0.openID }
    }
    mutating func apply(_ remote: [FeishuScheduleEvent], calendarID: String, now: Date) {
        let existing=Dictionary(events.map { ($0.id,$0) },uniquingKeysWith: { a,_ in a })
        var result: [FeishuScheduleEvent] = []
        for var event in remote {
            if let old=existing[event.id] { event.offsets=old.offsets;event.consumed=old.consumed }
            // Import/reschedule never replays a reminder whose time has already passed.
            if existing[event.id]?.start != event.start { event.consumed=Array(Set(event.consumed+event.reminderDates.filter{$0<=now})).sorted() }
            result.append(event)
        }
        let ids=Set(remote.map(\.id))
        for var old in events where !ids.contains(old.id) && old.end > now {
            old.status="removed";result.append(old)
        }
        events=result.filter{$0.end>now}.sorted{$0.start<$1.start}
        self.calendarID=calendarID;lastSync=now
    }
}

/// Only reads the bound user's primary calendar. No event write endpoint exists here.
struct FeishuScheduleClient {
    let connection: FeishuConnection
    var requestOverride: ((String,String,[String:String]) async throws -> [String:Any])?
    init(localConnection: FeishuConnection) { connection=localConnection }
    func request(_ method: String, _ path: String, params: [String:String] = [:]) async throws -> [String:Any] {
        if let requestOverride { return try await requestOverride(method,path,params) }
        var args=["api",method,"/open-apis/calendar/v4/"+path,"--as","user"]
        if !params.isEmpty { args += ["--params",String(decoding:try JSONSerialization.data(withJSONObject:params),as:UTF8.self)] }
        let input=method=="POST" ? Data("{}".utf8):nil
        if input != nil {args += ["--data","-"]}
        let result=try await Task.detached { try LocalCLIJob.request(connection,purpose:.calendar,arguments:args,input:input) }.value
        guard result["ok"] as? Bool == true,result["identity"] as? String == "user",let data=result["data"] as? [String:Any] else { throw WorkError.message("日历返回身份或内容无效。") }
        return data
    }
    func primary() async throws -> String {
        guard let openID=connection.localAccount?.openID else {throw WorkError.message("请先核对日历账号。")}
        let data=try await request("POST","calendars/primary",params:["user_id_type":"open_id"])
        guard let rows=data["calendars"] as? [[String:Any]],
              let row=rows.first(where: { $0["user_id"] as? String == openID }),
              let calendar=row["calendar"] as? [String:Any],calendar["type"] as? String == "primary",
              let id=calendar["calendar_id"] as? String,!id.isEmpty else { throw WorkError.message("无法确认本人主日历。") }
        return id
    }
    func events(calendarID: String, from: Date, to: Date, depth: Int = 0) async throws -> [FeishuScheduleEvent] {
        guard let segment=calendarID.addingPercentEncoding(withAllowedCharacters:.alphanumerics),!segment.isEmpty else {throw WorkError.message("日历标识无效。")}
        let data=try await request("GET","calendars/"+segment+"/events/instance_view",params:["start_time":String(Int(from.timeIntervalSince1970)),"end_time":String(Int(to.timeIntervalSince1970)),"user_id_type":"open_id"])
        guard let rows=(data["items"] as? [[String:Any]]) ?? (data.isEmpty ? [] : nil) else {throw WorkError.message("未收到完整的日程列表，请重试。")}
        // View responses are bounded. Split dense intervals instead of treating a truncated list as deletions.
        if rows.count>=1000 {
            guard depth<12,to.timeIntervalSince(from)>120 else {throw WorkError.message("日程过于密集，本次同步未完成。")}
            let midpoint=from.addingTimeInterval(to.timeIntervalSince(from)/2)
            let left=try await events(calendarID:calendarID,from:from,to:midpoint,depth:depth+1)
            let right=try await events(calendarID:calendarID,from:midpoint,to:to,depth:depth+1)
            return Array(Dictionary((left+right).map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values)
        }
        var result: [FeishuScheduleEvent]=[]
        for row in rows {
            if row["status"] as? String == "cancelled" { continue } // Complete snapshot marks an existing occurrence removed.
            let value=try Self.parse(row)
            if value.end>from && value.start<to { result.append(value) }
        }
        return Array(Dictionary(result.map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values)
    }
    static func parse(_ row: [String:Any]) throws -> FeishuScheduleEvent {
        guard let id=row["event_id"] as? String,!id.isEmpty,id.count<1024,
              let start=row["start_time"] as? [String:Any],let end=row["end_time"] as? [String:Any] else {throw WorkError.message("某条日程缺少时间，本次同步未覆盖已有记录。")}
        let allDay=start["date"] as? String != nil
        func date(_ value: [String:Any], isEnd: Bool) throws -> Date {
            if let text=value["date"] as? String {
                let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone = .current;formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
                guard let date=formatter.date(from:text),formatter.string(from:date)==text else {throw WorkError.message("全天日程日期无效。")}
                return isEnd ? Calendar.current.date(byAdding:.day,value:1,to:date)! : date
            }
            guard let stamp=value["timestamp"] as? String,let seconds=Double(stamp),seconds.isFinite,seconds>0,seconds<253402300800 else {throw WorkError.message("日程时间无效。")}
            return Date(timeIntervalSince1970:seconds)
        }
        let first=try date(start,isEnd:false),last=try date(end,isEnd:true)
        guard last>=first else {throw WorkError.message("日程起止时间无效。")}
        let title=(row["summary"] as? String).flatMap{$0.isEmpty ? nil:$0} ?? "未命名日程"
        guard title.count<10000 else {throw WorkError.message("日程标题过长。")}
        return FeishuScheduleEvent(id:id,title:title,start:first,end:last,allDay:allDay,appLink:row["app_link"] as? String)
    }
}

@MainActor extension WorkspaceStore {
    var scheduleEvents: [FeishuScheduleEvent] { (disk.feishuSchedule?.events ?? []).filter{$0.end>Date()} }
    func activateFeishuSchedule(_ connection: FeishuConnection) -> Bool {
        guard let key=FeishuScheduleState.key(connection) else {return false}
        calendarVerifiedAt=nil
        return mutate { state in
            if state.feishuSchedule?.accountKey != key {state.feishuSchedule=FeishuScheduleState(accountKey:key)}
            state.feishuSchedule?.enabled=true
        }
    }
    func startFeishuScheduleSync() {
        calendarTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in Task{@MainActor in await self?.syncFeishuSchedule()}}
        for name in [NSWorkspace.didActivateApplicationNotification,NSWorkspace.didWakeNotification] {
            calendarObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in
                Task{@MainActor in
                    guard let self,Date().timeIntervalSince(self.calendarVerifiedAt ?? .distantPast)>5 else{return}
                    await self.syncFeishuSchedule()
                }
            })
        }
        Task{await syncFeishuSchedule()}
    }
    func connectFeishuSchedule() async {
        guard !calendarSyncing else{return}
        guard let connection=LocalFeishuService.shared.connection(.calendar) else {LocalFeishuService.shared.open(.calendar);return}
        guard activateFeishuSchedule(connection) else{return}
        await syncFeishuSchedule()
    }
    func syncFeishuSchedule() async {
        guard disk.feishuSchedule?.enabled == true,!calendarSyncing else{return}
        guard let connection=LocalFeishuService.shared.connection(.calendar),let key=FeishuScheduleState.key(connection),key==disk.feishuSchedule?.accountKey else {
            calendarVerifiedAt=nil;calendarStatus="账号连接已变化，请重新连接日历";return
        }
        calendarSyncing=true;calendarStatus="正在检查未来30天的日程…"
        defer{calendarSyncing=false}
        do {
            let now=Date(),end=Calendar.current.date(byAdding:.day,value:30,to:now)!
            let client=FeishuScheduleClient(localConnection:connection)
            let id=try await client.primary()
            let events=try await client.events(calendarID:id,from:now,to:end)
            _=try await Task.detached {try LocalCLIJob.verified(connection,purpose:.calendar)}.value
            guard LocalFeishuService.shared.connection(.calendar)==connection,disk.feishuSchedule?.enabled == true,disk.feishuSchedule?.accountKey==key else{return}
            guard mutate({$0.feishuSchedule?.apply(events,calendarID:id,now:Date())}) else{throw WorkError.message(error)}
            calendarVerifiedAt=Date();calendarStatus="已同步\(events.count)个日程 · "+Date().formatted(date:.omitted,time:.shortened)
        } catch {
            calendarVerifiedAt=nil;calendarStatus="同步未完成，提醒暂时暂停："+((error as? AccountFailure)?.detail ?? error.localizedDescription)
        }
    }
    func setScheduleReminders(_ id: String, offsets: [Int], now: Date = Date()) throws {
        guard offsets.count<=12,offsets.allSatisfy({(0...43200).contains($0)}) else{throw WorkError.message("最多12次提醒，时间可设为开始时至提前30天。")}
        guard mutate({state in
            guard let index=state.feishuSchedule?.events.firstIndex(where:{$0.id==id}) else{return}
            state.feishuSchedule!.events[index].offsets=Array(Set(offsets)).sorted(by:>)
            let dates=state.feishuSchedule!.events[index].reminderDates.filter{$0<=now}
            state.feishuSchedule!.events[index].consumed=Array(Set(state.feishuSchedule!.events[index].consumed+dates))
        }) else{throw WorkError.message(error)}
    }
    func tickFeishuSchedules(now: Date) {
        guard let snapshot=disk.feishuSchedule,snapshot.enabled,!remindersAreLocked(),!restSleeping else{return}
        if integrationEnabled {
            guard let verified=calendarVerifiedAt,now.timeIntervalSince(verified)<180,
                  let connection=LocalFeishuService.shared.connection(.calendar),FeishuScheduleState.key(connection)==snapshot.accountKey else{return}
        }
        let due=snapshot.events.filter{event in event.active && event.end>now && event.reminderDates.contains{$0<=now && !event.consumed.contains($0)}}
        guard !due.isEmpty else{return}
        guard mutate({state in
            for i in (state.feishuSchedule?.events ?? []).indices {
                let dates=state.feishuSchedule!.events[i].reminderDates.filter{$0<=now}
                state.feishuSchedule!.events[i].consumed=Array(Set(state.feishuSchedule!.events[i].consumed+dates))
            }
        }) else{return}
        // A reminder must never navigate away from an unsaved editor.
        hasUnviewedScheduleReminder = todoPage != "calendar"
        let title="日程提醒 · "+due[0].title+(due.count>1 ? " · 还有\(due.count-1)个日程":"")
        if let style=disk.defaultTodoScreen {
            do{presentScreenReminder(try screenReminderRequest(style:style,title:title))}catch{notify(title)}
        } else{notify(title)}
    }
    func openFeishuCalendar(event: FeishuScheduleEvent? = nil) {
        let fallback=URL(string:"https://applink.feishu.cn/client/calendar/open")!
        let link=event?.appLink.flatMap(URL.init(string:))
        let safe=link.flatMap{url -> URL? in
            guard url.scheme=="https",let host=url.host,["applink.feishu.cn","applink.larksuite.com","applink.larkoffice.com"].contains(host),url.path.hasPrefix("/client/calendar/") else{return nil};return url
        }
        if !NSWorkspace.shared.open(safe ?? fallback) {calendarStatus="未能打开飞书，请在飞书日历中查看或新建日程。"}
    }
}
