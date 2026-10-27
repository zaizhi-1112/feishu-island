import AppKit
import Foundation

struct TodoCalendarFields: Codable, Equatable {
    var title: String
    var content: String
    var deadline: Date
    init(_ item: WorkItem) throws {
        guard let date=item.deadline else { throw WorkError.message("请先设置截止日期。") }
        title=item.title; content=item.input
        deadline=Date(timeIntervalSince1970:floor(date.timeIntervalSince1970))
    }
    init(title:String,content:String,deadline:Date) { self.title=title; self.content=content; self.deadline=deadline }
}
struct TodoCalendarLink: Codable, Equatable {
    var openID: String
    var userID: String
    var calendarID: String
    var eventID: String?
    var creationKey = UUID().uuidString
    var attemptedAt: Date?
    var baseline: TodoCalendarFields?
}
enum TodoCalendarMerge: Equatable {
    case unchanged, upload, download, conflict
    static func resolve(local:TodoCalendarFields,remote:TodoCalendarFields,baseline:TodoCalendarFields?) -> Self {
        if local == remote { return .unchanged }
        guard let baseline else { return .conflict }
        if local == baseline { return .download }
        if remote == baseline { return .upload }
        return .conflict
    }
}

/// Only documented Feishu calendar endpoints. No general proxy, attendees or deletes.
struct TodoCalendarClient {
    let credential: CompanyConnection.Credential
    var transport:(URLRequest) async throws -> (Data,URLResponse) = { try await URLSession.shared.data(for:$0) }
    private func segment(_ value:String) throws -> String {
        guard !value.isEmpty,value.count<512,let result=value.addingPercentEncoding(withAllowedCharacters:.alphanumerics) else {throw WorkError.message("日历标识无效。")}
        return result
    }
    func request(_ method:String,_ path:String,body:[String:Any]?=nil) async throws -> [String:Any] {
        let url=URL(string:"https://open.feishu.cn/open-apis/calendar/v4/"+path)!
        var request=URLRequest(url:url,timeoutInterval:20)
        request.httpMethod=method
        request.setValue("Bearer "+credential.access,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let body { request.httpBody=try JSONSerialization.data(withJSONObject:body) }
        let (data,response)=try await transport(request)
        guard data.count<=2_000_000,let http=response as? HTTPURLResponse else {throw WorkError.message("日历响应无效。")}
        guard (200...299).contains(http.statusCode),let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["code"] as? Int == 0,let value=root["data"] as? [String:Any] else {
            throw WorkError.message("日历请求未成功（HTTP \(http.statusCode)），请检查日历授权后重试。")
        }
        return value
    }
    func primary() async throws -> String {
        let value=try await request("POST","calendars/primary?user_id_type=open_id",body:[:])
        guard let rows=value["calendars"] as? [[String:Any]],
              let row=rows.first(where:{ ($0["user_id"] as? String)==credential.openID }),
              let calendar=row["calendar"] as? [String:Any],calendar["type"] as? String == "primary",
              ["owner","writer"].contains(calendar["role"] as? String ?? ""),
              let id=calendar["calendar_id"] as? String else {throw WorkError.message("无法确认本人可写的主日历。")}
        return id
    }
    func event(_ link:TodoCalendarLink) async throws -> [String:Any] {
        guard let id=link.eventID else {throw WorkError.message("日程尚未建立关联。")}
        let response=try await request("GET","calendars/"+segment(link.calendarID)+"/events/"+segment(id))
        guard let event=response["event"] as? [String:Any] else {throw WorkError.message("日程内容无效。")}
        return event
    }
    static func fields(_ event:[String:Any]) throws -> TodoCalendarFields {
        guard event["status"] as? String != "cancelled", (event["recurrence"] as? String ?? "").isEmpty,
              let title=event["summary"] as? String,!title.isEmpty,title.count<=160,
              let start=event["start_time"] as? [String:Any],let stamp=start["timestamp"] as? String,
              let seconds=Double(stamp),seconds.isFinite,seconds>0,seconds<253402300800 else {
            throw WorkError.message("日程已取消、改为全天/重复日程或内容不受支持；已停止覆盖，请在飞书中核对。")
        }
        let content=(event["description"] as? String) ?? ""
        guard content.utf8.count<=200_000 else {throw WorkError.message("日程说明过长，未写入待办。")}
        return .init(title:title,content:content.isEmpty ? title:content,deadline:Date(timeIntervalSince1970:seconds))
    }
    func write(_ fields:TodoCalendarFields,link:TodoCalendarLink,duration:Double=60) async throws -> (String,TodoCalendarFields) {
        let path="calendars/"+(try segment(link.calendarID))+"/events"
        let suffix=try link.eventID.map { "/" + (try segment($0)) } ?? "?idempotency_key="+link.creationKey
        let start=Int(fields.deadline.timeIntervalSince1970)
        let body:[String:Any]=["summary":fields.title,"description":fields.content,
            "start_time":["timestamp":String(start),"timezone":TimeZone.current.identifier],
            "end_time":["timestamp":String(start+Int(max(60,min(duration,86400*366)))),"timezone":TimeZone.current.identifier],
            "need_notification":false]
        let response=try await request(link.eventID == nil ? "POST":"PATCH",path+suffix,body:body)
        guard let event=response["event"] as? [String:Any],let id=event["event_id"] as? String else {throw WorkError.message("日程写入结果不明，保留关联重试信息。")}
        return (id,try Self.fields(event))
    }
}

@MainActor extension WorkspaceStore {
    func startTodoCalendarSync() {
        // Native deadline edits should appear within a minute, not the server's 10-minute polling default.
        calendarTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in
            Task { @MainActor in await self?.syncTodoCalendar() }
        }
        Task { await syncTodoCalendar() }
    }
    func connectTodoCalendar() async {
        guard !calendarSyncing else {return}
        calendarSyncing=true; calendarStatus="正在检查日历授权…"
        defer { calendarSyncing=false }
        do {
            let credential=try await Task.detached { try CompanyConnection.shared.prepare(.calendar) }.value
            let client=TodoCalendarClient(credential:credential)
            _=try await client.primary()
            try CompanyConnection.shared.activate(credential,purpose:.calendar)
            guard mutate({$0.calendarSyncEnabled=true}) else {throw WorkError.message(error)}
            calendarStatus="已连接 · 仅双向同步勾选的待办"
        } catch { calendarStatus="日历未连接："+((error as? AccountFailure)?.detail ?? error.localizedDescription); CompanyConnection.shared.open() }
    }
    func syncTodoCalendar() async {
        guard disk.calendarSyncEnabled == true,CompanyConnection.shared.isEnabled(.calendar),!calendarSyncing else {return}
        calendarSyncing=true
        defer {calendarSyncing=false}
        do {
            let credential=try await Task.detached { try CompanyConnection.shared.credential(.calendar) }.value
            let client=TodoCalendarClient(credential:credential)
            let eligible=disk.items.filter{$0.calendarSync == true && $0.archivedAt == nil && $0.deadline != nil}
            guard !eligible.isEmpty else {calendarStatus="已连接 · 在待办中选择需要同步的事项";return}
            var failures=0
            let count=min(20,eligible.count)
            for offset in 0..<count {
                guard disk.calendarSyncEnabled == true,CompanyConnection.shared.isEnabled(.calendar) else {break}
                let item=eligible[(calendarCursor+offset)%eligible.count]
                do { try await syncCalendarItem(item,client:client) }
                catch {
                    failures+=1
                    _=mutate { state in if let i=state.items.firstIndex(where:{$0.id==item.id}) {state.items[i].calendarError=error.localizedDescription} }
                }
            }
            calendarCursor=(calendarCursor+count)%eligible.count
            calendarStatus=failures == 0 ? "已同步 · "+Date().formatted(date:.omitted,time:.shortened):"\(failures) 项需要处理，展开对应待办查看"
        } catch {calendarStatus="日历同步暂停，请检查连接或重新授权。"}
    }
    private func syncCalendarItem(_ item:WorkItem,client:TodoCalendarClient) async throws {
        var link:TodoCalendarLink
        if let existing=item.calendarLink { link=existing }
        else {
            link=TodoCalendarLink(openID:client.credential.openID,userID:client.credential.userID,calendarID:try await client.primary())
            guard mutate({state in if let i=state.items.firstIndex(where:{$0.id==item.id}) {state.items[i].calendarLink=link}}) else {throw WorkError.message(error)}
        }
        guard link.userID==client.credential.userID,link.openID==client.credential.openID else {throw WorkError.message("该待办关联的是其他账号，已停止同步。")}
        var remote:[String:Any]?
        if link.eventID != nil {remote=try await client.event(link)}
        guard disk.calendarSyncEnabled == true,CompanyConnection.shared.isEnabled(.calendar),
              let current=disk.items.first(where:{$0.id==item.id}),current.calendarSync == true,current.archivedAt == nil else {return}
        let local=try TodoCalendarFields(current)
        if let remote {
            let fields=try TodoCalendarClient.fields(remote)
            switch TodoCalendarMerge.resolve(local:local,remote:fields,baseline:link.baseline) {
            case .conflict: throw WorkError.message("两边都修改了此待办。请先将其中一边改成你希望保留的相同内容，再同步；不会自动覆盖。")
            case .download:
                guard mutate({state in if let i=state.items.firstIndex(where:{$0.id==item.id}) {
                    state.items[i].title=fields.title;state.items[i].input=fields.content;state.items[i].deadline=fields.deadline
                    state.items[i].calendarLink?.baseline=fields;state.items[i].calendarError=nil
                }}) else {throw WorkError.message(error)}
                return
            case .unchanged:
                _=mutate {state in if let i=state.items.firstIndex(where:{$0.id==item.id}) {state.items[i].calendarLink?.baseline=fields;state.items[i].calendarError=nil}}
                return
            case .upload: break
            }
        } else {
            // Keep the same idempotency key across failures; never blindly recreate after an old unknown result.
            if let attempted=link.attemptedAt,Date().timeIntervalSince(attempted)>3600 {
                throw WorkError.message("此前创建结果不明且已超过一小时。请先在飞书核对，暂停自动重建以免重复。")
            }
            link.attemptedAt=link.attemptedAt ?? Date()
            guard mutate({state in if let i=state.items.firstIndex(where:{$0.id==item.id}) {state.items[i].calendarLink=link}}) else {throw WorkError.message(error)}
        }
        let start=(remote?["start_time"] as? [String:Any])?["timestamp"] as? String
        let end=(remote?["end_time"] as? [String:Any])?["timestamp"] as? String
        let duration=(end.flatMap(Double.init) ?? 60)-(start.flatMap(Double.init) ?? 0)
        let (eventID,baseline)=try await client.write(local,link:link,duration:duration)
        link.eventID=eventID;link.baseline=baseline
        guard mutate({state in if let i=state.items.firstIndex(where:{$0.id==item.id}) {state.items[i].calendarLink=link;state.items[i].calendarError=nil}}) else {throw WorkError.message(error)}
    }
}
