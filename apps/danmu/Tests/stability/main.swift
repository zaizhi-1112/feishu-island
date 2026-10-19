import Foundation
import Darwin
func descriptors() -> Int { (0..<10240).reduce(0) { $0 + (fcntl(Int32($1), F_GETFD) >= 0 ? 1 : 0) } }
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let reader = AccountReader(cli: root.appendingPathComponent("Tests/stability/fake-cli.py"), pollDelay:0.01, pageDelay:0.01, catalogInterval:2, clock:ServerClock(probe:{ .local() }))
var cycles = 0; var deliveries = 0; var initialFD = 0; var failures = 0
reader.onMessage = { _,_,_ in deliveries += 1 }
reader.onStatus = { status in
    if status.contains("账号接收中") { cycles += 1; if cycles == 10 { initialFD = descriptors() } }
    if status.contains("失败") || status.contains("异常") || status.contains("暂缓") { failures += 1 }
}
reader.start()
let deadline = Date().addingTimeInterval(60)
while (cycles < 180 || deliveries < 20) && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
let finalFD = descriptors()
reader.stop()
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
assert(cycles >= 180,"Continuous polling did not recover")
assert(deliveries == 20,"Sustained messages lost or duplicated: \(deliveries)")
assert(failures > 0,"Injected empty response not surfaced")
assert(finalFD <= initialFD + 24,"Subprocess descriptors leaked: \(initialFD) -> \(finalFD)")
print("PASS: \(cycles) polling cycles, 20 sequential messages, empty-response recovery, descriptor count \(initialFD) -> \(finalFD)")
