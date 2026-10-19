import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let clockOffset = Double(ProcessInfo.processInfo.environment["DANMU_TEST_CLOCK_OFFSET"] ?? "0") ?? 0
let reader = AccountReader(cli:root.appendingPathComponent("Tests/latency/fake-cli.py"), pollDelay:0.1, pageDelay:0.01, clock: ServerClock(probe: { .local(offset: clockOffset) }))
var deliveries = 0
var delays: [TimeInterval] = []
reader.onMessage = { _, _, created in
    deliveries += 1
    assert(created != nil)
    delays.append(reader.currentTime().timeIntervalSince(created!))
}
reader.start()
var deadline = Date().addingTimeInterval(9)
while deliveries < 2 && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
assert(deliveries == 2,"Cold-chat promotion was blocked by slow catalog")
assert(delays[0] < 4,"Fast delivery exceeded synthetic budget")
reader.stop()
RunLoop.current.run(until:Date().addingTimeInterval(0.2))
assert(deliveries == 2,"Stopped session delivered stale messages")
reader.start()
deadline = Date().addingTimeInterval(9)
while deliveries < 4 && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
reader.stop()
assert(deliveries == 4,"Restart should own a new dedupe and progress session")
assert(delays[2] < 4)
assert(delays[1] >= 4 && delays[3] >= 4,"Delayed-visibility fixture must exercise lookback")
let t = accountMessageDate("1789776042123")!
assert(abs(t.timeIntervalSince1970 - 1789776042.123) < 0.001)
let text:[String:Any] = ["msg_type":"text","body":["content":"{\"text\":\"你好\"}"]]
assert(accountMessageText(text) == "你好")
let post:[String:Any] = ["msg_type":"post","body":["content":"{\"zh_cn\":{\"title\":\"标题\",\"content\":[[{\"tag\":\"text\",\"text\":\"正文\"},{\"tag\":\"img\"}]]}}"]]
assert(accountMessageText(post) == "标题 正文[图片]")
assert(accountMessageText(["msg_type":"image","body":["content":"{\"image_key\":\"not-to-display\"}"]]) == "[图片]")
let card:[String:Any] = ["msg_type":"interactive","body":["content":"{\"header\":{\"title\":{\"content\":\"通知\"}},\"elements\":[{\"tag\":\"markdown\",\"content\":\"卡片正文\"}]}" ]]
assert(accountMessageText(card) == "通知 卡片正文")
print(String(format:"PASS: clock offset %+.0f seconds compensated, slow 12-second catalog isolated, cold chat received in %.2f/%.2f seconds (synthetic), late API visibility, startup history exclusion, restart cancellation, exact timestamps, text/post/media decoding",clockOffset,delays[0],delays[2]))
