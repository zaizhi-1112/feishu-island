import AppKit
import Network

let bridgePort: UInt16 = 48763
let webOrigin = "https://feishu-danmu.virxact.net"

func color(_ raw: Any?) -> NSColor? {
    guard let text = raw as? String, text.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
          let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 0.94)
}

final class DesktopBridge {
    let overlay = Overlay()
    let nonce = UUID().uuidString + UUID().uuidString
    let instance = UUID().uuidString
    var listener: NWListener?
    var accepted = 0, displayed = 0
    var knownIDs = Set<String>(), order: [String] = []
    var paused = false, locked = false
    var lastContact = ProcessInfo.processInfo.systemUptime
    var lastPID: pid_t?
    var observers: [NSObjectProtocol] = []
    var cleanupTimer: Timer?
    let agent = AppearanceMCP()
    let testing: Bool
    init(testing: Bool = false) {
        self.testing = testing
        overlay.window.title = "飞书弹幕 · 透明桌面层"
        overlay.window.setAccessibilityElement(true)
        agent.onChange = { [weak self] a in self?.applyAppearance(a) }
        overlay.onPresented = { [weak self] _ in self?.displayed += 1 }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: bridgePort)!)
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .userInitiated))
                self?.read(connection, buffer: Data())
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch { fputs("desktop bridge unavailable\n", stderr) }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastContact > 120 { self.overlay.clear(); self.agent.revoke() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.openFor(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.electron.lark" { self?.lastPID = nil }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.agent.revoke(); self?.locked = true; self?.overlay.paused = true; self?.overlay.clear()
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.locked = false; self.overlay.paused = self.paused
        })
        if !testing { for app in NSWorkspace.shared.runningApplications { openFor(app) } }
    }
    func openFor(_ app: NSRunningApplication) {
        guard app.bundleIdentifier == "com.electron.lark", app.processIdentifier != lastPID else { return }
        lastPID = app.processIdentifier
        NSWorkspace.shared.open(URL(string: webOrigin + "/?desktop=1")!)
    }
    func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] bytes, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var data = buffer; if let bytes { data.append(bytes) }
            guard data.count <= 1024*1024 else { connection.cancel(); return }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
                if !complete { self.read(connection, buffer: data) } else { connection.cancel() }; return
            }
            let lines = head.components(separatedBy: "\r\n")
            let request = (lines.first ?? "").split(separator: " ").map(String.init)
            guard request.count == 3 else { connection.cancel(); return }
            var headers: [String:String] = [:]
            for line in lines.dropFirst() { if let split = line.firstIndex(of: ":") { headers[String(line[..<split]).lowercased()] = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces) } }
            let length = Int(headers["content-length"] ?? "0") ?? -1
            guard length >= 0, length <= 900000, headers["transfer-encoding"] == nil else { connection.cancel(); return }
            if data.count < boundary.upperBound + length { if !complete { self.read(connection, buffer: data) } else { connection.cancel() }; return }
            let body = Data(data[boundary.upperBound..<(boundary.upperBound + length)])
            DispatchQueue.main.async { self.handle(connection, method: request[0], path: request[1], headers: headers, body: body) }
        }
    }
    func reply(_ connection: NWConnection, _ status: Int, _ object: [String:Any], origin: String) {
        let body = status == 202 ? Data() : ((try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
        let head = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: content-type,x-danmu-token\r\nAccess-Control-Allow-Private-Network: true\r\nVary: Origin\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    func handle(_ connection: NWConnection, method: String, path: String, headers: [String:String], body: Data) {
        let origin = headers["origin"] ?? ""
        if path == "/mcp" {
            guard origin.isEmpty, headers["host"] == "127.0.0.1:\(bridgePort)", agent.active,
                  headers["authorization"] == "Bearer " + (agent.token ?? ""), !locked,
                  ProcessInfo.processInfo.systemUptime - lastContact < 120 else { reply(connection,403,["error":"appearance capability required"],origin:"null"); return }
            guard method == "POST" else { reply(connection,405,[:],origin:"null"); return }
            guard (headers["content-type"] ?? "").hasPrefix("application/json"), let object = (try? JSONSerialization.jsonObject(with:body)) as? [String:Any] else { reply(connection,400,[:],origin:"null"); return }
            if let response = agent.rpc(object) { reply(connection,200,response,origin:"null") }
            else { reply(connection,202,[:],origin:"null") }
            return
        }
        let trusted = origin == webOrigin || (testing && origin == "http://127.0.0.1:8768")
        guard trusted, headers["host"] == "127.0.0.1:\(bridgePort)" else { reply(connection,403,["error":"origin refused"],origin: "null"); return }
        guard method == "GET" || method == "POST" || method == "OPTIONS" else { reply(connection,405,[:],origin: origin); return }
        if method == "OPTIONS" { reply(connection,200,[:],origin: origin); return }
        if method == "GET" && (path == "/handshake" || path == "/status") {
            var status: [String:Any] = ["version":"0.7.1","instance":instance,"accepted":accepted,"displayed":displayed,"visible":overlay.flying.count,"queued":overlay.queue.count,"paused":overlay.paused,"mousePassThrough":overlay.window.ignoresMouseEvents,"canBecomeKey":overlay.window.canBecomeKey,"screenWidth":overlay.window.frame.width,"overlayWindowID":overlay.window.windowNumber]
            if path == "/handshake" { status["token"] = nonce }
            status["frames"] = overlay.flying.map { ["x":$0.frame.minX,"y":$0.frame.minY,"width":$0.frame.width,"height":$0.frame.height] }
            reply(connection,200,status,origin: origin); return
        }
        guard method == "POST", headers["x-danmu-token"] == nonce,
              (headers["content-type"] ?? "").hasPrefix("application/json"),
              let object = (try? JSONSerialization.jsonObject(with: body)) as? [String:Any] else { reply(connection,403,["error":"unauthorized"],origin: origin); return }
        lastContact = ProcessInfo.processInfo.systemUptime
        if path == "/present" {
            guard let text = object["text"] as? String, !text.isEmpty, text.utf8.count <= 800000 else { reply(connection,400,["error":"invalid message"],origin: origin); return }
            guard !locked else { reply(connection,409,["error":"screen locked"],origin:origin); return }
            let demo = object["demo"] as? Bool ?? false
            let id = object["id"] as? String ?? ""
            if !demo {
                guard id.range(of: "^om_[a-zA-Z0-9]+$", options: .regularExpression) != nil else { reply(connection,400,[:],origin:origin); return }
                if knownIDs.contains(id) { reply(connection,200,["duplicate":true],origin: origin); return }
                knownIDs.insert(id); order.append(id)
                if order.count > 1000 { knownIDs.remove(order.removeFirst()) }
                overlay.queue.removeAll { $0.demo }
                for view in overlay.flying where view.content.string.hasPrefix("[演示]") { view.removeFromSuperview() }
                overlay.flying.removeAll { $0.superview == nil }
            }
            overlay.enqueue(text, demo: demo); accepted += 1
        } else if path == "/appearance" {
            guard let a = AppearanceMCP.validate(object) else { reply(connection,400,["error":"invalid appearance"],origin:origin); return }
            // A browser refresh cannot overwrite an Agent update waiting to be saved.
            if agent.revision == agent.savedRevision { agent.appearance = a; applyAppearance(a) }
        } else if path == "/agent/connect" {
            guard agent.revision == agent.savedRevision else { reply(connection,409,["error":"appearance save pending"],origin:origin); return }
            reply(connection,200,["token":agent.authorize(),"endpoint":"http://127.0.0.1:48763/mcp"],origin:origin); return
        } else if path == "/agent/state" {
            reply(connection,200,agent.state(),origin:origin); return
        } else if path == "/agent/ack" {
            if let revision = object["revision"] as? Int, revision == agent.revision { agent.savedRevision = revision }
        } else if path == "/control" {
            if let value = object["paused"] as? Bool { paused = value; overlay.paused = value || locked }
            if object["clear"] as? Bool == true { overlay.clear() }
        } else if path != "/heartbeat" { reply(connection,404,[:],origin:origin); return }
        reply(connection,200,["ok":true,"accepted":accepted,"displayed":displayed],origin:origin)
    }
    func applyAppearance(_ a:[String:Any]) {
        overlay.fontSize = CGFloat((a["fontSize"] as? NSNumber)?.doubleValue ?? 28)
        overlay.skinForeground = color(a["foreground"]); overlay.skinBackground = color(a["background"])
        overlay.skinCorner = CGFloat((a["corner"] as? NSNumber)?.doubleValue ?? 12)
        overlay.preferStatic = a["motion"] as? String == "static"
    }

}

@main struct Launcher {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let testing = CommandLine.arguments.contains("--test-mode") || CommandLine.arguments.contains("--render-check")
        let bridge = DesktopBridge(testing: testing)
        if CommandLine.arguments.contains("--render-check") {
            bridge.overlay.enqueue("桌面弹幕试播",demo:true)
            let start = bridge.overlay.window.frame.width
            DispatchQueue.main.asyncAfter(deadline:.now()+2) {
                let view = bridge.overlay.flying.first
                let ok = view != nil && view!.frame.minX < start && bridge.overlay.window.ignoresMouseEvents && !bridge.overlay.window.canBecomeKey
                let result:[String:Any] = ["pass":ok,"visible":bridge.overlay.window.isVisible,"mousePassThrough":bridge.overlay.window.ignoresMouseEvents,"canBecomeKey":bridge.overlay.window.canBecomeKey,"x":view?.frame.minX ?? -1,"screenWidth":start]
                if let data = try? JSONSerialization.data(withJSONObject:result), let text = String(data:data,encoding:.utf8) { print(text) }
                exit(ok ? 0 : 1)
            }
        }
        app.run(); withExtendedLifetime(bridge) {}
    }
}
