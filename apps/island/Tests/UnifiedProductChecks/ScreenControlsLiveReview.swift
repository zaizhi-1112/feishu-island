import AppKit
@testable import IslandShell

/// Explicit synthetic UI verification; it never opens an account or real task.
@MainActor func showScreenControlsLiveReview() throws {
    let packaged=Bundle.main.bundleIdentifier=="local.youzi.island.skin-preview"
        && Bundle.main.object(forInfoDictionaryKey:"ScreenControlsReview") as? Bool == true
    let argument=CommandLine.arguments.firstIndex(of:"--screen-controls-review").flatMap{index in
        CommandLine.arguments.indices.contains(index+1) ? CommandLine.arguments[index+1]:nil
    }
    guard IslandRuntime.isSkinPreview,packaged || CommandLine.arguments.contains("--interactive"),
          let path=argument ?? (packaged ? Bundle.main.object(forInfoDictionaryKey:"ReviewOutputDirectory") as? String:nil)
    else {fatalError("Explicit synthetic review required")}
    NSApplication.shared.setActivationPolicy(.accessory)
    let folder=URL(fileURLWithPath:path)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let presenter=ScreenReminderPresenter(sessionIsLocked:{false})
    let material=ScreenReminderMaterial.builtins.first{$0.id=="cat"}!
    try presenter.present(.init(title:"冲屏倒计时 · 合成点验",style:.init(durationSeconds:12),material:material,
                                videoURL:ScreenReminderMedia.bundledURL("cat"),isRest:true))
    let started=ProcessInfo.processInfo.systemUptime
    var samples=[presenter.remainingSeconds]
    let timer=Timer(timeInterval:0.1,repeats:true){timer in
        MainActor.assumeIsolated {
            if samples.last != presenter.remainingSeconds {samples.append(presenter.remainingSeconds)}
            let ended = !presenter.isPresenting
            let timedOut=ProcessInfo.processInfo.systemUptime-started>16
            let value:[String:Any]=[
                "synthetic":true,"samples":samples,"remainingSeconds":presenter.remainingSeconds,
                "visible":presenter.isPresenting,"windowCount":presenter.verificationWindows.count,
                "passed":ended && samples.first==12 && samples.contains(1) && samples.last==0,
                "elapsed":ProcessInfo.processInfo.systemUptime-started
            ]
            if let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]) {
                try? data.write(to:folder.appendingPathComponent("countdown-state.json"),options:.atomic)
            }
            if ended || timedOut {timer.invalidate();presenter.dismissAll();NSApp.terminate(nil)}
        }
    }
    RunLoop.main.add(timer,forMode:.common)
}
