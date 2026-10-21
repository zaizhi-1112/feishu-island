import Foundation

struct HubCard: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var kind: String
    var text: String
    var href: String?
}
struct HubSnapshot: Codable, Sendable {
    var connected = false
    var name = ""
    var cards: [HubCard] = []
    var readAt: Date?
    var error = ""
}
enum HubReadable {
    /// Readable safe text; keep all rows, no clipping disguised as a complete result.
    static func readable(_ value: Any, depth: Int = 0) -> String {
        guard depth < 20 else { return "内容层级过深，请打开中台查看。" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if value is NSNull { return "—" }
        if let a = value as? [Any] { return a.map{readable($0,depth:depth+1)}.joined(separator:"\n") }
        if let d = value as? [String:Any] {
            if d["auth"] != nil { return "需要本人飞书授权，请打开中台完成。" }
            if d["forbidden"] != nil { return "本人没有此来源的读取权限。" }
            if d["error"] != nil { return "来源读取失败，请打开中台查看详情。" }
            if d["type"] as? String == "report" {
                let parser=ISO8601DateFormatter();parser.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
                let raw=d["committedAt"] as? String ?? ""
                let stamp=parser.date(from:raw)?.formatted(date:.abbreviated,time:.shortened) ?? raw
                let items=(d["items"] as? [[String:Any]] ?? []).map { ($0["name"] as? String ?? "原汇报项目")+"\n"+($0["value"] as? String ?? "—") }.joined(separator:"\n\n")
                return (d["rule"] as? String ?? "本人汇报") + (stamp.isEmpty ? "" : " · 提交于 "+stamp) + (items.isEmpty ? "\n暂无填写内容，以原汇报为准。" : "\n\n"+items)
            }
            if let text = d["text"] as? String { return text }
            if let props = d["props"] { return readable(props,depth:depth+1) }
            let skip: Set<String> = ["type","view","format","limit","id","recordId","record_id","userId","user_id","appToken","tableId","avatar","url"]
            return d.keys.sorted().filter{!skip.contains($0)}.map { key in
                let label = ["text":"内容","title":"标题","name":"名称","value":"数值","items":"条目","columns":"内容","props":"详情","state":"读取状态","cycle":"周期","url":"来源","today":"日期","progress":"进度","label":"名称","rows":"明细","cards":"事项","tag":"状态","owner":"负责人","results":"关键结果","current":"当前","target":"目标","expected":"预期","standing":"状态","submittedAt":"提交时间","submitted_at":"提交时间","fields":"原文项目","period":"周期"][key] ?? key
                return "\(label)：\(readable(d[key]!,depth:depth+1))"
            }.joined(separator:"\n")
        }
        return ""
    }
}
