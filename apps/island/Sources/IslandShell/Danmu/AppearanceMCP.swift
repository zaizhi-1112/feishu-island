import Foundation
import CoreFoundation

// The Agent gets this appearance-only capability, never the browser bridge nonce.
final class AppearanceMCP {
    static let defaults: [String:Any] = ["version":1,"name":"中台默认","background":NSNull(),"foreground":NSNull(),"border":NSNull(),"fontSize":28,"corner":12,"motion":"scroll","speed":100,"bubble":"none","backgroundEnabled":true,"borderEnabled":true]
    var appearance = defaults
    var revision = 0, savedRevision = 0
    var token: String?
    var expires: TimeInterval = 0
    var onChange: (([String:Any]) -> Void)?
    var active: Bool { token != nil && ProcessInfo.processInfo.systemUptime < expires }
    func authorize() -> String { let key = UUID().uuidString + UUID().uuidString; token = key; expires = ProcessInfo.processInfo.systemUptime + 1800; return key }
    func revoke() { token = nil; expires = 0 }
    func state() -> [String:Any] { ["appearance":appearance,"revision":revision,"saved":savedRevision == revision] }
    static func validate(_ input: [String:Any]) -> [String:Any]? {
        guard input.keys.allSatisfy({ defaults[$0] != nil }) else { return nil }
        let a = defaults.merging(input) { _,new in new }
        func integer(_ key: String, _ range: ClosedRange<Int>) -> Bool {
            guard let n = a[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
            return n.doubleValue == Double(n.intValue) && range.contains(n.intValue)
        }
        guard integer("version",1...1), integer("fontSize",22...44), integer("corner",0...24), integer("speed",40...240),
              let bubble = a["bubble"] as? String, ["none","dark","light","custom"].contains(bubble),
              let name = a["name"] as? String, !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.utf16.count <= 40,
              let motion = a["motion"] as? String, ["scroll","static"].contains(motion) else { return nil }
        for key in ["backgroundEnabled", "borderEnabled"] {
            guard let flag = a[key] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return nil }
        }
        for key in ["background","foreground","border"] {
            if a[key] is NSNull { continue }
            guard let s = a[key] as? String, s.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil else { return nil }
        }
        guard (a["background"] is NSNull) == (a["foreground"] is NSNull) else { return nil }
        if bubble != "none", a["backgroundEnabled"] as? Bool != false, let bg = a["background"] as? String, let fg = a["foreground"] as? String {
            func luminance(_ s:String) -> Double {
                let rgb = UInt32(s.dropFirst(),radix:16)!
                let c = [16,8,0].map { shift -> Double in let x = Double((rgb >> shift) & 255)/255; return x <= 0.04045 ? x/12.92 : pow((x+0.055)/1.055,2.4) }
                return c[0]*0.2126+c[1]*0.7152+c[2]*0.0722
            }
            let x = luminance(bg), y = luminance(fg)
            guard (max(x,y)+0.05)/(min(x,y)+0.05) >= 4.5 else { return nil }
        }
        return a
    }
    func rpc(_ request: [String:Any]) -> [String:Any]? {
        guard let id = request["id"] else { return nil }
        func result(_ value:[String:Any]) -> [String:Any] { ["jsonrpc":"2.0","id":id,"result":value] }
        func error(_ code:Int,_ message:String) -> [String:Any] { ["jsonrpc":"2.0","id":id,"error":["code":code,"message":message]] }
        guard request["jsonrpc"] as? String == "2.0" else { return error(-32600,"Invalid request") }
        switch request["method"] as? String {
        case "initialize": return result(["protocolVersion":"2025-03-26","capabilities":["tools":[:]],"serverInfo":["name":"feishu-island-appearance","version":"0.6.0"],"instructions":"Only personal appearance is available. After update, poll read_appearance until saved=true. No messages, credentials or core settings are exposed."])
        case "ping": return result([:])
        case "tools/list": return result(["tools":[
            ["name":"read_appearance","description":"Read current personal appearance and local-save status. Keep the signed-in webpage open.","inputSchema":["type":"object","properties":[:],"additionalProperties":false]],
            ["name":"update_appearance","description":"Patch personal appearance only. fontSize integer 22-44, speed integer 40-240 pixels/second, bubble none/dark/light/custom, corner 0-24, backgroundEnabled/borderEnabled booleans, colors #RRGGBB or null (foreground/background together, visible background contrast >=4.5); motion scroll/static, name 1-40 chars. Core settings are forbidden.","inputSchema":["type":"object","properties":["patch":["type":"object","properties":["name":["type":"string","minLength":1,"maxLength":40],"version":["const":1],"fontSize":["type":"integer","minimum":22,"maximum":44],"corner":["type":"integer","minimum":0,"maximum":24],"speed":["type":"integer","minimum":40,"maximum":240],"bubble":["enum":["none","dark","light","custom"]],"backgroundEnabled":["type":"boolean"],"borderEnabled":["type":"boolean"],"background":["type":["string","null"]],"foreground":["type":["string","null"]],"border":["type":["string","null"]],"motion":["enum":["scroll","static"]]],"additionalProperties":false]],"required":["patch"],"additionalProperties":false]]
        ]])
        case "tools/call":
            let params = request["params"] as? [String:Any] ?? [:]
            let args = params["arguments"] as? [String:Any] ?? [:]
            switch params["name"] as? String {
            case "read_appearance": guard args.isEmpty else { return error(-32602,"No arguments allowed") }
            case "update_appearance":
                guard Set(args.keys) == ["patch"], let patch = args["patch"] as? [String:Any], let a = Self.validate(appearance.merging(patch) { _,new in new }) else { return error(-32602,"Invalid appearance: unknown fields, invalid values or insufficient color contrast") }
                appearance = a; revision += 1; onChange?(a)
            default: return error(-32602,"Unknown appearance tool")
            }
            let data = try! JSONSerialization.data(withJSONObject:state(),options:.sortedKeys)
            return result(["content":[["type":"text","text":String(data:data,encoding:.utf8)!]]])
        default: return error(-32601,"Method not found")
        }
    }
}
