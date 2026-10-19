import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let reader = AccountReader(cli: root.appendingPathComponent("Tests/account/fake-cli.py"), pollDelay: 0.01, pageDelay: 0, concurrency: 3, clock: ServerClock(probe: { .local() }))
var received: [(String, Bool)] = []
var cycles = 0
var failures = 0
reader.setRules(gray: ["chat3"], hidden: ["chat4"])
reader.onMessage = { received.append(($0, $1)); _ = $2 }
reader.onStatus = { status in
    if status.contains("账号接收中") { cycles += 1 }
    if status.contains("读取失败") || status.contains("补读重试") { failures += 1 }
}
reader.start()
let deadline = Date().addingTimeInterval(60)
while (cycles < 20 || received.count < 6) && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
reader.stop()
let count = received.count
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
assert(received.count == count, "Stopped reader emitted late callbacks")
assert(cycles >= 20, "Polling failed to finish test cycles")
assert(received.count == 6, "Expected six unique incoming messages across pagination, retries, and full coverage, got \(received.count)")
assert(received.filter { $0.1 }.count == 1, "Muted allowlist must be gray")
assert(failures >= 1, "Page failure was not surfaced")
let path = ProcessInfo.processInfo.environment["DANMU_TEST_STATE"]!
let state = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
let read = Set(state["read"] as! [String])
assert(read.contains("oc_104"), "Last chat was omitted")
assert(!read.contains("oc_2"), "Muted chat was read")
assert(!read.contains("oc_4"), "Blocked chat was read")
assert((state["bad"] as! [String]).isEmpty)
print("PASS: user identity, p2p/group polling, 105-chat coverage, mute allowlist, block precedence, own/deleted skip, page failure retry, dedupe, cancellation")
