import AppKit
import ApplicationServices
import CryptoKit
import Darwin

// Deliberately UI-only: no WorkBuddy files, cloud APIs, cookies or login credentials.
typealias Receipt = WorkBuddyDailyFlow.Receipt
let fm=FileManager.default
let root=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/WorkBuddyCheckin")
func output(_ state:String) -> Never {
    let bytes=(try? JSONSerialization.data(withJSONObject:["state":state])) ?? Data()
    FileHandle.standardOutput.write(bytes);exit(0)
}
func attr(_ e:AXUIElement,_ key:String) -> CFTypeRef? { var v:CFTypeRef?; guard AXUIElementCopyAttributeValue(e,key as CFString,&v) == .success else{return nil};return v }
func children(_ e:AXUIElement) -> [AXUIElement] { attr(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ e:AXUIElement)->String { attr(e,kAXRoleAttribute) as? String ?? "" }
func label(_ e:AXUIElement)->String {
    Array(Set([kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap{attr(e,$0) as? String}.filter{!$0.isEmpty})).sorted().joined(separator:" ")
}
func parent(_ e:AXUIElement)->AXUIElement? { guard let x=attr(e,kAXParentAttribute), CFGetTypeID(x)==AXUIElementGetTypeID() else{return nil};return (x as! AXUIElement) }
func find(_ start:AXUIElement, budget:Int=600, test:(AXUIElement)->Bool)->AXUIElement? {
    var stack:[(AXUIElement,Int)]=[(start,0)], visited=0
    while let (e,depth)=stack.popLast(),visited<budget {
        visited+=1;if test(e){return e}
        if depth<20 {stack.append(contentsOf:children(e).prefix(64).reversed().map{($0,depth+1)})}
    }
    return nil
}
func enabled(_ e:AXUIElement)->Bool { (attr(e,kAXEnabledAttribute) as? Bool) == true }
func press(_ e:AXUIElement)->Bool { AXUIElementPerformAction(e,kAXPressAction as CFString) == .success }
let args=CommandLine.arguments
if args.contains("--authorize") {
    let ok=AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
    output(ok ? "ready" : "permission_required")
}
guard AXIsProcessTrusted() else{output("permission_required")}
try? fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
let fd=open(root.appendingPathComponent("runner.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
guard fd>=0,flock(fd,LOCK_EX|LOCK_NB)==0 else{output("busy")}
defer {flock(fd,LOCK_UN);close(fd)}
guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.workbuddy.workbuddy").first else{output("client_closed")}
let appAX=AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(appAX,1)
_ = AXUIElementSetAttributeValue(appAX,"AXManualAccessibility" as CFString,kCFBooleanTrue)
guard let windows=attr(appAX,kAXWindowsAttribute) as? [AXUIElement],let window=windows.first(where:{(attr($0,kAXTitleAttribute) as? String)=="WorkBuddy"}) else{output("client_unavailable")}
// This anchor belongs to the free points promotion, never a task or a chat action.
var anchor=find(window){role($0)==kAXButtonRole && label($0).contains("展开 Buddy 加油站详情")}
if anchor == nil,args.contains("--check") {
    // Reopen a dismissed bubble only via an explicit daily-signin action.
    // Never follow an invitation, payment, recharge or external promotion.
    if let avatar=find(window,budget:400,test:{role($0)==kAXPopUpButtonRole && !label($0).isEmpty && !label($0).contains("消息中心") && !label($0).contains("小程序")}),press(avatar) {
        Thread.sleep(forTimeInterval:0.3)
        let menu=find(window,budget:600){role($0)==kAXMenuRole}
        if let menu {
            if let action=find(menu,budget:100,test:{
                let s=label($0);return role($0)==kAXButtonRole && s.contains("Buddy加油站") && (s.contains("去签到") || s.contains("今日领取")) && !["邀约","邀请","购买","充值"].contains(where:{s.contains($0)})
            }) {_ = press(action);Thread.sleep(forTimeInterval:0.3)}
            else {_ = AXUIElementPerformAction(menu,kAXCancelAction as CFString)}
        }
        anchor=find(window){role($0)==kAXButtonRole && label($0).contains("展开 Buddy 加油站详情")}
    }
}
guard let anchor,let station=parent(anchor),let sidebar=parent(station) else{output("station_unavailable")}
let controls=children(station)
let stationTexts=controls.filter{role($0)==kAXStaticTextRole}.compactMap{attr($0,kAXValueAttribute) as? String}.joined(separator:" ")
var avatar:AXUIElement?, accountGroup:AXUIElement?=sidebar
for _ in 0..<4 {
    guard let group=accountGroup else{break}
    avatar=children(group).first{role($0)==kAXPopUpButtonRole && !label($0).contains("消息中心") && !label($0).contains("小程序")}
    if avatar != nil {break};accountGroup=parent(group)
}
guard let avatar,!label(avatar).isEmpty else{output("login_required")}
let account=SHA256.hash(data:Data(label(avatar).utf8)).map{String(format:"%02x",$0)}.joined()
var calendar=Calendar(identifier:.gregorian);calendar.timeZone = .current
let c=calendar.dateComponents([.year,.month,.day],from:Date())
let day=String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
let file=root.appendingPathComponent("receipts.json")
var records:[Receipt]=[]
if fm.fileExists(atPath:file.path) {
    var info=stat()
    guard lstat(file.path,&info)==0,info.st_uid==getuid(),info.st_mode & S_IFMT==S_IFREG,info.st_size<131072,
          let bytes=try? Data(contentsOf:file),let saved=try? JSONDecoder().decode([Receipt].self,from:bytes) else{output("storage_error")}
    records=saved
}
func record(_ state:String) -> Bool {
    records.removeAll{$0.day==day && $0.account==account}
    records.append(Receipt(day:day,account:account,state:state,checked:Date().timeIntervalSince1970))
    records=Array(records.suffix(90))
    do{try JSONEncoder().encode(records).write(to:file,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path);return true}catch{return false}
}
func isClaimed()->Bool {
    children(station).contains{role($0)==kAXButtonRole && label($0).contains("今日已领") && !enabled($0)}
}
let eligible = stationTexts.contains("今日可领") && stationTexts.contains("积分") && !["购买","充值","邀请","支付"].contains(where:{stationTexts.contains($0)})
let buttons=controls.filter{ e in
    var s=label(e).replacingOccurrences(of:" ",with:"")
    if s.hasSuffix("→"){s.removeLast()}
    return role(e)==kAXButtonRole && enabled(e) && s.range(of:"^(立即领取|免费领取|今日领取|领取)([0-9]+积分)?$",options:.regularExpression) != nil
}
let state=WorkBuddyDailyFlow.run(day:day,account:account,claimed:isClaimed(),eligible:eligible && buttons.count==1,allowClaim:args.contains("--check"),records:records,save:record,press:{press(buttons[0])},verify:{
    for _ in 0..<16 {Thread.sleep(forTimeInterval:0.5);if isClaimed(){return true}}
    return false
})
output(state)
