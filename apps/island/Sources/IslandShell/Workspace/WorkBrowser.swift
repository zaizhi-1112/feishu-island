import Foundation

protocol WorkRunning: AnyObject, Sendable {
    func run(input: String, instruction: String, images: [URL]) throws -> String
    func cancel()
}

final class WorkBrowser: WorkRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var safeAbort = true
    private var receivedURL: String?
    var knownNotSubmitted: Bool { lock.lock(); defer { lock.unlock() }; return safeAbort }
    var taskURL: String? { lock.lock(); defer { lock.unlock() }; return receivedURL }
    var expectedAccount = ""
    var taskID = UUID().uuidString
    var resumeURL: String?
    var onSubmitting: (@Sendable ()->Void)?
    var onURL: (@Sendable (String)->Void)?
    static var executable: String? { [NSHomeDirectory()+"/.local/bin/ego-browser","/opt/homebrew/bin/ego-browser"].first { FileManager.default.isExecutableFile(atPath:$0) } }
    func cancel() {
        lock.lock(); stopped = true; let p = process; lock.unlock()
        if p?.isRunning == true { p?.terminate() }
    }
    func run(input: String, instruction: String, images: [URL] = []) throws -> String {
        guard Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", let exe = Self.executable, let scriptURL = Bundle.main.resourceURL?.appendingPathComponent("BrowserBridge/doubao-work.js"), let script = try? String(contentsOf:scriptURL,encoding:.utf8) else { throw WorkError.message("本机豆包网页连接组件未安装。") }
        var request: [String:Any] = ["input":input,"instruction":instruction,"images":images.map(\.path),"taskID":taskID,"expectedAccount":expectedAccount]
        if let resumeURL { request["resumeURL"] = resumeURL }
        if let raw = ProcessInfo.processInfo.environment["ISLAND_BROWSER_TASKSPACE"], let space = Int(raw) { request["spaceId"] = space }
        let payload = try JSONSerialization.data(withJSONObject:request).base64EncodedString()
        let program = "const workRequest=JSON.parse(Buffer.from(\""+payload+"\",\"base64\").toString(\"utf8\"));\n"+script
        let p = Process(), stdout = Pipe(), stdin = Pipe()
        p.executableURL = URL(fileURLWithPath:exe); p.arguments = ["nodejs"]
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stdout // Ego CLI emits its script console events on stderr; parse both streams without logging materials.
        var env = ProcessInfo.processInfo.environment.filter { ["HOME","USER","LOGNAME","TMPDIR","LANG","LC_ALL","HTTPS_PROXY","HTTP_PROXY","ALL_PROXY","NO_PROXY"].contains($0.key) }
        env["PATH"] = NSHomeDirectory()+"/.local/bin:"+NSHomeDirectory()+"/.local/node/bin:/opt/homebrew/bin:/usr/bin:/bin"
        p.environment = env
        lock.lock(); if stopped { lock.unlock(); throw WorkError.message("已停止本机等候。") }; process = p; lock.unlock()
        defer { try? stdin.fileHandleForWriting.close(); try? stdin.fileHandleForReading.close(); try? stdout.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close(); lock.lock(); process = nil; lock.unlock() }
        try p.run()
        lock.lock(); safeAbort = false; lock.unlock()
        DispatchQueue.global().async { try? stdin.fileHandleForWriting.write(contentsOf:Data(program.utf8)); try? stdin.fileHandleForWriting.close() }
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline:.now()+420,execute:timeout); defer { timeout.cancel() }
        var buffer = Data(), result: String?, failure = "豆包连接未返回结果，请打开原任务核对。", url = resumeURL ?? ""
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            guard buffer.count <= 2_000_000 else { cancel(); throw WorkError.message("网页连接响应过大，已停止本机等候。") }
            while let end = buffer.firstIndex(of:10) {
                let raw = String(decoding:buffer.prefix(upTo:end),as:UTF8.self); buffer.removeSubrange(...end)
                guard let event = Self.event(raw) else { continue }
                if event["kind"] as? String == "submitting" { onSubmitting?() }
                if let link = event["url"] as? String, Self.validTask(link) { url = link; lock.lock(); receivedURL = link; lock.unlock(); onURL?(link) }
                if event["kind"] as? String == "result", let text = event["text"] as? String {
                    let links = (event["links"] as? [String] ?? []).filter(Self.validDocument)
                    result = text+(links.isEmpty ? "" : "\n\n飞书文档：\n"+links.joined(separator:"\n"))
                }
                if event["kind"] as? String == "error" {
                    if event["submissionAttempted"] as? Bool == false { lock.lock(); safeAbort = true; lock.unlock() }
                    let code = event["code"] as? String ?? ""
                    failure = code == "ACCOUNT_MISMATCH" ? "豆包网页账号与本机飞书账号不同，未提交材料。" : code == "ACCOUNT_UNKNOWN" ? "先连接本人飞书账号，再核对豆包身份。" : "豆包网页连接需要检查（"+(event["stage"] as? String ?? "未知阶段")+"）。登录或验证需在原网页完成。"
                }
            }
        }
        p.waitUntilExit()
        lock.lock(); let cancelled = stopped; lock.unlock()
        if cancelled { throw WorkError.message("已停止本机等候；云端任务可能继续，状态请查看原任务。"+(url.isEmpty ? "" : "\n"+url)) }
        guard let result, p.terminationStatus == 0 else { throw WorkError.message(failure+(url.isEmpty ? "" : "\n"+url)) }
        return result+"\n\n豆包原任务："+url
    }
    static func event(_ raw: String) -> [String:Any]? {
        guard raw.hasPrefix("ISLAND_EVENT "), let data = String(raw.dropFirst(13)).data(using:.utf8),
              let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              ["submitting","created","result","error"].contains(event["kind"] as? String ?? "") else { return nil }
        return event
    }
    static func validTask(_ value: String) -> Bool { value.range(of:#"^https://aily\.feishu\.cn/tasks/[0-9]+$"#,options:.regularExpression) != nil }
    static func documentLinks(in text: String) -> [String] {
        let pattern = #"https://[A-Za-z0-9.-]+\.feishu\.cn/(?:docx|wiki)/[A-Za-z0-9]+"#
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern:pattern) else { return [] }
        return Array(Set(regex.matches(in:text,range:NSRange(location:0,length:ns.length)).map { ns.substring(with:$0.range) }.filter(validDocument))).sorted()
    }
    static func validDocument(_ value: String) -> Bool {
        guard let u = URL(string:value), u.scheme == "https", let host=u.host, host.hasSuffix(".feishu.cn") else { return false }
        return u.path.hasPrefix("/docx/") || u.path.hasPrefix("/wiki/")
    }
}
