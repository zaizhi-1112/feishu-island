#!/usr/bin/env python3
"""Exercise the shipped helper against an owned, off-screen native UI fixture.
Only this test build substitutes the exact bundle/title/receipt root. No test
selectors, target override, or synthetic success are added to the product.
"""
import json, os, pathlib, plistlib, signal, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
SDK = os.environ.get('ISLAND_SDK', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.4.sdk')
folder = pathlib.Path(tempfile.mkdtemp(prefix='workbuddy-native-checkin-'))
app = folder/'SyntheticCheckin.app'
binary = app/'Contents/MacOS/SyntheticCheckin'
binary.parent.mkdir(parents=True)
bundle = 'local.zaizhi.synthetic-checkin.' + folder.name.rsplit('-', 1)[-1]
title = 'Synthetic WorkBuddy Checkin'
status = folder/'fixture.json'
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle, 'CFBundleExecutable':'SyntheticCheckin','CFBundleName':'SyntheticCheckin', 'CFBundlePackageType':'APPL','LSUIElement':True}))
fixture = r'''
import AppKit
let status=URL(fileURLWithPath:__STATUS__)
let mode=CommandLine.arguments.last ?? "normal"
final class Group:NSView {override func isAccessibilityElement()->Bool{true};override func accessibilityRole()->NSAccessibility.Role?{.group}}
final class Delegate:NSObject,NSApplicationDelegate {
 var window:NSWindow!;var clicks=0;var claim:NSButton!
 func save(){try? JSONSerialization.data(withJSONObject:["pid":ProcessInfo.processInfo.processIdentifier,"clicks":clicks]).write(to:status,options:.atomic)}
 func applicationDidFinishLaunching(_ n:Notification){
  window=NSWindow(contentRect:NSRect(x:-5000,y:-5000,width:300,height:180),styleMask:[.titled],backing:.buffered,defer:false);window.title=__TITLE__
  let outer=Group(frame:NSRect(x:0,y:0,width:300,height:180));window.contentView=outer
  let station=Group(frame:NSRect(x:0,y:40,width:300,height:140));outer.addSubview(station)
  let anchor=NSButton(title:"展开 Buddy 加油站详情",target:nil,action:nil);anchor.frame=NSRect(x:0,y:90,width:240,height:25);station.addSubview(anchor)
  let free=NSTextField(labelWithString:"Buddy加油站 今日可领100积分");free.frame=NSRect(x:0,y:55,width:270,height:25);station.addSubview(free)
  claim=NSButton(title:mode=="purchase" ? "购买积分" : "立即领取 →",target:self,action:#selector(tap));claim.frame=NSRect(x:0,y:20,width:150,height:25);station.addSubview(claim)
  let avatar=NSPopUpButton(frame:NSRect(x:0,y:0,width:220,height:30));avatar.addItem(withTitle:"Synthetic Account");avatar.setAccessibilityLabel("Synthetic Account");outer.addSubview(avatar)
  window.orderBack(nil);save();Timer.scheduledTimer(withTimeInterval:45,repeats:false){_ in NSApp.terminate(nil)}
 }
 @objc func tap(){clicks+=1;if mode != "uncertain" {claim.title="今日已领";claim.isEnabled=false};save()}
}
let application=NSApplication.shared;application.setActivationPolicy(.accessory);let delegate=Delegate();application.delegate=delegate;application.run()
'''.replace('__STATUS__',json.dumps(str(status))).replace('__TITLE__',json.dumps(title))
source=folder/'fixture.swift';source.write_text(fixture)
subprocess.run(['swiftc','-sdk',SDK,str(source),'-o',str(binary)],check=True)
subprocess.run(['codesign','--sign','-',str(app)],check=True,capture_output=True)
helper_src=(ROOT/'scripts/workbuddy-checkin-helper.swift').read_text().replace('com.workbuddy.workbuddy',bundle).replace('=="WorkBuddy"','=='+json.dumps(title)).replace('fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/WorkBuddyCheckin")','URL(fileURLWithPath:'+json.dumps(str(folder/'receipts'))+')')
helper_main=folder/'main.swift';helper_main.write_text(helper_src)
helper=folder/'helper'
subprocess.run(['swiftc','-sdk',SDK,str(ROOT/'Sources/IslandShell/Agents/WorkBuddyDailyFlow.swift'),str(helper_main),'-o',str(helper)],check=True)
results=[]
for mode in ['normal','uncertain','purchase']:
 receipt=folder/'receipts/receipts.json'
 if receipt.exists():receipt.rename(folder/(mode+'-previous-receipt.json'))
 if status.exists():status.rename(folder/(mode+'-previous-status.json'))
 subprocess.run(['open','-n','-g',str(app),'--args',mode],check=True)
 deadline=time.monotonic()+6
 while not status.exists() and time.monotonic()<deadline:time.sleep(.1)
 assert status.exists(),'fixture failed to start'
 pid=json.loads(status.read_text())['pid']
 try:
  def call():return json.loads(subprocess.check_output([str(helper),'--check'],timeout=20))['state']
  first=call();second=call();count=json.loads(status.read_text())['clicks']
  expected={'normal':('claimed','already_claimed',1),'uncertain':('uncertain','uncertain',1),'purchase':('station_changed','station_changed',0)}[mode]
  assert (first,second,count)==expected,(mode,first,second,count)
  results.append({'scenario':mode,'first':first,'second':second,'clicks':count})
 finally:os.kill(pid,signal.SIGTERM)
print(json.dumps({'passed':True,'offscreenOnly':True,'cases':results,'fixtureRoot':str(folder)}))
