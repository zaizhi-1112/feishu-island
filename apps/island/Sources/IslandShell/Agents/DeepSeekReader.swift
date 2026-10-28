import AppKit
import Foundation

enum DeepSeekReader {
    static var application: URL? {
        for directory in [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            let app = directory.appendingPathComponent("DeepSeek Harness.app")
            if Bundle(url: app)?.bundleIdentifier == "com.deepseek.dsh" { return app }
        }
        return nil
    }
    static func snapshot() throws -> AgentSnapshot {
        guard let app = application else { throw AgentReadError.unavailable("请先安装并登录 DeepSeek Harness。") }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("deepseek-balance.cjs")
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/deepseek-balance.cjs")
        let script = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? development
        guard FileManager.default.fileExists(atPath: script.path) else { throw AgentReadError.unavailable("余额组件缺失，请重新安装一切在岛。") }
        let process = Process(), pipe = Pipe()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/DeepSeek Harness")
        process.arguments = [script.path]
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin", "ELECTRON_RUN_AS_NODE": "1"]
        process.standardInput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardOutput = pipe
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
        defer { timeout.cancel(); try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        do { try process.run() } catch { throw AgentReadError.unavailable("暂时无法读取 DeepSeek Harness 余额。") }
        try? pipe.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 65536 { process.terminate(); throw AgentReadError.unavailable("余额返回格式不受支持。") }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AgentReadError.unavailable("暂时无法读取余额，请稍后刷新。") }
        return try parse(data)
    }
    static func parse(_ data: Data) throws -> AgentSnapshot {
        struct Reply: Decodable { let ok: Bool; let metrics: [AgentMetric]?; let error: String? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AgentReadError.unavailable("余额返回格式不受支持。") }
        guard reply.ok, let metrics = reply.metrics, !metrics.isEmpty else {
            let message: String
            switch reply.error {
            case "login", "changed": message = "请打开 DeepSeek Harness 登录，再刷新余额。"
            case "storage": message = "暂时无法读取 Harness 登录状态，请打开客户端确认已登录。"
            case "protocol": message = "Harness 余额接口已变化，请更新一切在岛。"
            default: message = "余额暂时无法刷新，请稍后重试。"
            }
            throw AgentReadError.unavailable(message)
        }
        let result = AgentSnapshot(metrics: metrics, source: "DeepSeek Harness 账户余额", detail: "每3分钟刷新余额。")
        guard result.validationError == nil, metrics.count <= 4 else { throw AgentReadError.unavailable("余额返回格式不受支持。") }
        return result
    }
}
