import Foundation
import Darwin

/// The executable owning Keychain access remains byte-identical across ordinary UI builds.
/// Grants stay in its private Keychain service; this process receives only cards/documents.
actor HubClient {
    private let transport = HubTransport()
    init() {}
    func begin(callback: String) async throws -> URL {
        guard let url = URL(string:callback), url.scheme == "http", url.host == "127.0.0.1", url.path == "/oauth/virxact/callback" else { throw WorkError.message("授权回调地址无效。") }
        let value = try await transport.request("begin",payload:["callback":callback])
        guard let raw = value["url"] as? String, let result = URL(string:raw), result.scheme == "https", result.host == "virxact.net" else { throw WorkError.message("中台授权地址无效。") }
        return result
    }
    func finish(query: [URLQueryItem]) async throws {
        guard Set(query.map(\.name)).count == query.count else { throw WorkError.message("授权校验未通过。") }
        _ = try await transport.request("finish",payload:["query":query.map{["name":$0.name,"value":$0.value ?? ""]}])
    }
    func disconnect() async { _ = try? await transport.request("disconnect") }
    func snapshot() async throws -> HubSnapshot {
        let value = try await transport.request("snapshot")
        return try JSONDecoder().decode(HubSnapshot.self,from:JSONSerialization.data(withJSONObject:value))
    }
    func document(_ link: String) async throws -> String {
        let value = try await transport.request("document",payload:["url":link])
        guard let text = value["text"] as? String else { throw WorkError.message("文档未读到。") }; return text
    }
    nonisolated static func readable(_ value: Any, depth: Int = 0) -> String { HubReadable.readable(value,depth:depth) }
}

final class HubTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label:"feishu-island.hub-helper")
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    deinit { try? input?.fileHandleForWriting.close(); if process?.isRunning == true { process?.terminate() } }
    func request(_ method: String, payload: [String:Any] = [:]) async throws -> [String:Any] {
        try await withCheckedThrowingContinuation { c in
            queue.async { [self] in
                do { c.resume(returning:try transact(method,payload:payload)) }
                catch { if !(error is HubRemoteError) { reset() }; c.resume(throwing:error) }
            }
        }
    }
    private func reset() {
        if process?.isRunning == true { process?.terminate() }
        try? input?.fileHandleForWriting.close(); try? input?.fileHandleForReading.close()
        try? output?.fileHandleForReading.close(); try? output?.fileHandleForWriting.close()
        process = nil; input = nil; output = nil; buffer = Data()
    }
    private func transact(_ method: String, payload: [String:Any]) throws -> [String:Any] {
        if process?.isRunning != true {
            reset()
            guard Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview",
                  let base = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent(), FileManager.default.isExecutableFile(atPath:base.appendingPathComponent("Helpers/feishu-hub-helper").path) else { throw WorkError.message("中台独立组件未安装；测试不会读取本人钥匙串。") }
            let p = Process(), i = Pipe(), o = Pipe()
            p.executableURL = base.appendingPathComponent("Helpers/feishu-hub-helper"); p.standardInput = i; p.standardOutput = o; p.standardError = FileHandle.nullDevice
            p.environment = ProcessInfo.processInfo.environment.filter { ["HOME","USER","LOGNAME","TMPDIR","LANG","LC_ALL","HTTPS_PROXY","HTTP_PROXY","ALL_PROXY","NO_PROXY"].contains($0.key) }
            try p.run(); process = p; input = i; output = o
        }
        guard let p = process, let input, let output else { throw WorkError.message("中台组件未就绪。") }
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline:.now()+130,execute:timeout); defer { timeout.cancel() }
        let bytes = try JSONSerialization.data(withJSONObject:["method":method,"payload":payload])
        try input.fileHandleForWriting.write(contentsOf:bytes+Data([10]))
        while buffer.firstIndex(of:10) == nil {
            var bytes = [UInt8](repeating:0,count:65536)
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor,&bytes,bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0, buffer.count+count <= 5_000_000 else { throw WorkError.message("中台组件中断或响应过大，请重试。") }
            buffer.append(contentsOf:bytes.prefix(count))
        }
        let end = buffer.firstIndex(of:10)!, line = buffer.prefix(upTo:end); buffer.removeSubrange(...end)
        guard let reply = try JSONSerialization.jsonObject(with:line) as? [String:Any] else { throw WorkError.message("中台组件响应无效。") }
        guard reply["ok"] as? Bool == true else { throw HubRemoteError(message:reply["error"] as? String ?? "中台读取未成功。") }
        return reply["value"] as? [String:Any] ?? [:]
    }
}

private struct HubRemoteError: LocalizedError { var message: String; var errorDescription: String? { message } }
