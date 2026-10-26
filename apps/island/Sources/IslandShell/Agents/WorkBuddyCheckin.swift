import AppKit
import Darwin
import SwiftUI

struct WorkBuddyCheckinSchedule {
    static func due(now:Date,calendar:Calendar = .current)->Bool {
        let c=calendar.dateComponents([.hour,.minute],from:now);return (c.hour ?? 0)*60+(c.minute ?? 0)>=550
    }
    static func delay(state:String)->TimeInterval {
        switch state {case "claimed","already_claimed":return 3600;case "permission_required","login_required","uncertain","station_changed","station_unavailable":return 21600;default:return 900}
    }
    static func message(_ state:String)->String {
        switch state {
        case "claimed":return "今日免费积分已领取"
        case "already_claimed":return "今日已领，无需重复领取"
        case "permission_required":return "需要一次 macOS 辅助功能许可"
        case "client_closed":return "WorkBuddy尚未就绪，稍后自动补查"
        case "client_not_installed":return "请先安装WorkBuddy并登录自己的账号"
        case "login_required":return "请先在WorkBuddy登录自己的账号"
        case "uncertain":return "领取尚未确认，已避免重复点击；请到WorkBuddy核对"
        case "station_changed","station_unavailable":return "未找到已知免费领取入口，未点击其他按钮"
        case "storage_error":return "签到记录保存失败，已停止领取"
        case "checking":return "正在检查本人WorkBuddy的免费积分…"
        case "ready":return "权限已就绪，可检查今日积分"
        default:return "等待检查，每天9:10；睡眠或退出后下次运行补查"
        }
    }
}
final class WorkBuddyCheckinProcess:@unchecked Sendable {
    private let lock=NSLock();private var process:Process?;private var stopped=false
    private var cancellation:URL?;private var pidFile:URL?;private var helperApp:URL?
    func cancel(){
        lock.lock();stopped=true;let p=process, marker=cancellation, pidURL=pidFile, helper=helperApp;lock.unlock()
        if let marker {try? Data().write(to:marker,options:.atomic)}
        if let helper,let pidURL,let raw=try? String(contentsOf:pidURL,encoding:.utf8),let pid=Int32(raw),
           let app=NSRunningApplication(processIdentifier:pid),app.bundleURL?.standardizedFileURL==helper.standardizedFileURL {app.terminate()}
        if let p,p.isRunning {p.terminate();DispatchQueue.global().asyncAfter(deadline:.now()+2){if p.isRunning{Darwin.kill(p.processIdentifier,SIGKILL)}}}
    }
    func run(helper:URL,arguments:[String])->String {
        let p=Process(),pipe=Pipe()
        var reply:URL?
        if helper.pathExtension=="app" {
            let id=UUID().uuidString,folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/WorkBuddyCheckin/requests")
            do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}catch{return "storage_error"}
            reply=folder.appendingPathComponent(id+".json")
            lock.lock();cancellation=folder.appendingPathComponent(id+".cancel");pidFile=folder.appendingPathComponent(id+".pid");helperApp=helper;lock.unlock()
            p.executableURL=URL(fileURLWithPath:"/usr/bin/open");p.arguments=["-n","-g","-W",helper.path,"--args"]+arguments+["--request",id]
        } else {p.executableURL=helper;p.arguments=arguments}
        p.standardOutput=pipe;p.standardError=FileHandle.nullDevice;p.standardInput=FileHandle.nullDevice
        defer {try? pipe.fileHandleForReading.close();try? pipe.fileHandleForWriting.close();lock.lock();process=nil;lock.unlock()}
        lock.lock();guard !stopped else{lock.unlock();return "cancelled"};process=p
        do{try p.run();lock.unlock()}catch{lock.unlock();return "client_unavailable"}
        let timeout=DispatchWorkItem{[weak self] in self?.cancel()};DispatchQueue.global().asyncAfter(deadline:.now()+25,execute:timeout);defer{timeout.cancel()}
        let stdout=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
        let data=reply.flatMap{try? Data(contentsOf:$0)} ?? stdout
        lock.lock();let cancelled=stopped;lock.unlock()
        guard !cancelled else{return "cancelled"}
        guard p.terminationStatus==0,data.count<4096,let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:String] else{return "client_unavailable"}
        return json["state"] ?? "client_unavailable"
    }
}
@MainActor final class WorkBuddyCheckinStore:ObservableObject {
    static let shared=WorkBuddyCheckinStore()
    @Published private(set) var enabled:Bool
    @Published private(set) var state:String
    @Published private(set) var busy=false
    private let defaults:UserDefaults
    private var timer:Timer?
    private var observers:[NSObjectProtocol]=[]
    private var nextCheck:Date
    private var started=false
    private var unlocked=true
    private var task:Task<Void,Never>?
    private var runner:WorkBuddyCheckinProcess?
    private var request:UUID?
    init(defaults:UserDefaults = UserDefaults(suiteName:"local.zaizhi.island.workbuddy-checkin")!) {
        self.defaults=defaults;enabled=defaults.bool(forKey:"enabled");state=defaults.string(forKey:"state") ?? "idle"
        nextCheck=defaults.object(forKey:"nextCheck") as? Date ?? .distantPast
    }
    func start(){
        guard !started,!IslandRuntime.isSkinPreview,Bundle.main.bundleIdentifier=="local.zaizhi.feishu-island.preview" else{return};started=true
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self]_ in Task{@MainActor in self?.tick()}}
        let center=NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.tick(forceTime:true)}})
        observers.append(center.addObserver(forName:NSWorkspace.didLaunchApplicationNotification,object:nil,queue:.main){[weak self] n in
            guard (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier=="com.workbuddy.workbuddy" else{return}
            Task{@MainActor in self?.tick(forceTime:true)}
        })
        observers.append(center.addObserver(forName:NSWorkspace.sessionDidResignActiveNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.unlocked=false;self?.stopRunning()}})
        observers.append(center.addObserver(forName:NSWorkspace.sessionDidBecomeActiveNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.unlocked=true;self?.tick(forceTime:true)}})
        tick()
    }
    private func stopRunning(){task?.cancel();runner?.cancel();task=nil;runner=nil;request=nil;busy=false}
    func setEnabled(_ value:Bool){enabled=value;defaults.set(value,forKey:"enabled");nextCheck = .distantPast;if value {check()}else{stopRunning();state="idle"}}

    func tick(now:Date=Date(),forceTime:Bool=false){
        guard enabled,unlocked,!busy,WorkBuddyCheckinSchedule.due(now:now),now>=nextCheck || forceTime else{return};check()
    }
    func authorize(){invoke(authorize:true)}
    func check(){guard enabled else{return};invoke(authorize:false)}
    private func invoke(authorize:Bool){
        guard unlocked,!busy,Bundle.main.bundleIdentifier=="local.zaizhi.feishu-island.preview",!IslandRuntime.isSkinPreview else{return}
        busy=true;state="checking"
        let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/WorkBuddyCheckin.app")
        let id=UUID();request=id
        task=Task {
            if !authorize,NSRunningApplication.runningApplications(withBundleIdentifier:"com.workbuddy.workbuddy").isEmpty {
                if let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.workbuddy.workbuddy") {
                    let config=NSWorkspace.OpenConfiguration();config.activates=false;config.hides=true
                    _ = try? await NSWorkspace.shared.openApplication(at:app,configuration:config)
                    try? await Task.sleep(for:.seconds(5))
                } else {busy=false;state="client_not_installed";nextCheck=Date().addingTimeInterval(3600);return}
            }
            guard !Task.isCancelled,request==id,unlocked,(enabled || authorize) else{return}
            let current=WorkBuddyCheckinProcess();runner=current
            let result=await Task.detached {current.run(helper:helper,arguments:[authorize ? "--authorize" : "--check"])}.value
            guard request==id else{return};runner=nil;task=nil;request=nil
            busy=false;state=result;defaults.set(result,forKey:"state");nextCheck=Date().addingTimeInterval(WorkBuddyCheckinSchedule.delay(state:result));defaults.set(nextCheck,forKey:"nextCheck")
        }
    }
}
struct WorkBuddyCheckinSettings:View {
    @ObservedObject var store=WorkBuddyCheckinStore.shared
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Toggle("每天自动领取 WorkBuddy 免费积分",isOn:Binding(get:{store.enabled},set:{store.setEnabled($0)})).accessibilityIdentifier("workbuddy.daily.enabled")
            Text("每天9:10用本机WorkBuddy已登录账号领取。你的飞包运行即可，无需Codex；睡眠或退出期间不执行，下次运行补查。每位同事自行开启和授权。").font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(WorkBuddyCheckinSchedule.message(store.state)).font(.system(size:13)).accessibilityIdentifier("workbuddy.daily.state")
            HStack{
                Button("检查今日积分"){store.check()}.disabled(!store.enabled || store.busy)
                if store.state=="permission_required" {
                    Button("允许签到组件控制WorkBuddy"){store.authorize()}
                    Button("打开辅助功能设置"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
                }
            }
            Text("仅操作Buddy加油站免费领取并核对“今日已领”；不购买、不操作聊天。只保存日期、账号显示名摘要和领取状态，不保存凭据。无法确认时停止重复点击。").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(16).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
}
