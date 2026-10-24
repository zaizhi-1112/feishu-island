// Adapted from the user-supplied FeishuDanmu source archive.
import Foundation

struct ServerClockSample {
    let serverTime: Date
    let localTime: Date
    let uptime: TimeInterval
    let roundTrip: TimeInterval

    static func local(offset: TimeInterval = 0) -> ServerClockSample {
        let local = Date()
        return ServerClockSample(serverTime: local.addingTimeInterval(offset), localTime: local,
                                 uptime: ProcessInfo.processInfo.systemUptime, roundTrip: 0)
    }
}

// Query boundaries, startup filtering and receive latency use the same server
// timebase. Monotonic progression isolates running sessions from wall-clock jumps.
final class ServerClock {
    private let lock = NSLock()
    private let probeLock = NSLock()
    private let probe: () throws -> ServerClockSample
    private var sample: ServerClockSample?

    init(probe: @escaping () throws -> ServerClockSample = ServerClock.feishuSample) {
        self.probe = probe
    }
    func refreshIfNeeded(maxAge: TimeInterval = 300) throws {
        probeLock.lock(); defer { probeLock.unlock() }
        lock.lock(); let previous = sample; lock.unlock()
        if let previous {
            let elapsed = ProcessInfo.processInfo.systemUptime - previous.uptime
            let wallElapsed = Date().timeIntervalSince(previous.localTime)
            if elapsed >= 0 && elapsed < maxAge && abs(wallElapsed - elapsed) < 2 { return }
        }
        let next = try probe()
        lock.lock(); sample = next; lock.unlock()
    }
    func now() -> Date {
        lock.lock(); let current = sample; lock.unlock()
        guard let current else { return Date() }
        return current.serverTime.addingTimeInterval(max(0, ProcessInfo.processInfo.systemUptime - current.uptime))
    }
    var offset: TimeInterval { now().timeIntervalSinceNow }
    var isCalibrated: Bool { lock.lock(); defer { lock.unlock() }; return sample != nil }

    private static func fallbackSample() throws -> ServerClockSample {
        guard let ip = FeishuTransport.shared.resolvedIP() else { throw AccountFailure(detail:"无法读取飞书安全时间，请检查网络。") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/curl")
        process.arguments = ["--silent","--show-error","--head","--max-time","5","--noproxy","open.feishu.cn","--resolve","open.feishu.cn:443:"+ip,"https://open.feishu.cn/open-apis/im/v1/messages?danmu_clock_probe="+UUID().uuidString]
        process.standardInput = FileHandle.nullDevice;process.standardOutput = pipe;process.standardError = FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close();try? pipe.fileHandleForWriting.close() }
        let began = ProcessInfo.processInfo.systemUptime, local = Date()
        try process.run();let bytes = pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        let ended = ProcessInfo.processInfo.systemUptime, received = Date(), rtt = ended-began
        guard process.terminationStatus == 0, bytes.count < 65536, rtt <= 5, abs(received.timeIntervalSince(local)-rtt) < 1,
              let line = String(decoding:bytes,as:UTF8.self).components(separatedBy:"\n").last(where:{$0.lowercased().hasPrefix("date:")}) else { throw AccountFailure(detail:"飞书安全连接失败，稍后自动重试。") }
        let format = DateFormatter();format.locale = Locale(identifier:"en_US_POSIX");format.timeZone = TimeZone(secondsFromGMT:0);format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = format.date(from:String(line.dropFirst(5)).trimmingCharacters(in:.whitespacesAndNewlines)) else { throw AccountFailure(detail:"飞书没有返回有效时间。") }
        return ServerClockSample(serverTime:date.addingTimeInterval(0.5+rtt/2),localTime:received,uptime:ended,roundTrip:rtt)
    }
    static func feishuSample() throws -> ServerClockSample {
        // Unauthenticated dynamic endpoint: only its HTTPS Date header is used.
        // No account token, message content or personal identifier is sent here.
        var components = URLComponents(string: "https://open.feishu.cn/open-apis/im/v1/messages")!
        components.queryItems = [URLQueryItem(name: "danmu_clock_probe", value: UUID().uuidString)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let began = ProcessInfo.processInfo.systemUptime
        let localBegan = Date()
        let result = ClockProbeResult()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, response, _ in
            defer { done.signal() }
            let ended = ProcessInfo.processInfo.systemUptime
            let localEnded = Date()
            let rtt = ended - began
            guard rtt >= 0, rtt <= 3,
                  abs(localEnded.timeIntervalSince(localBegan) - rtt) < 1,
                  let response = response as? HTTPURLResponse,
                  response.url?.scheme == "https", response.url?.host == "open.feishu.cn",
                  let header = response.value(forHTTPHeaderField: "Date") else { return }
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(secondsFromGMT: 0)
            format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            guard let serverDate = format.date(from: header) else { return }
            // HTTP Date has one-second resolution. Midpoint of that second plus
            // half RTT estimates the server time at response receipt (about ±1s).
            let value = ServerClockSample(serverTime: serverDate.addingTimeInterval(0.5 + rtt / 2),
                                          localTime: localEnded, uptime: ended, roundTrip: rtt)
            result.lock.lock(); result.sample = value; result.lock.unlock()
        }
        task.resume()
        guard done.wait(timeout: .now() + 4) == .success else {
            task.cancel(); return try fallbackSample()
        }
        result.lock.lock(); let value = result.sample; result.lock.unlock()
        guard let value else { return try fallbackSample() }
        return value
    }
}
private final class ClockProbeResult {
    let lock = NSLock()
    var sample: ServerClockSample?
}
