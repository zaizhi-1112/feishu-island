import Foundation

struct HubCard: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var kind: String
    var text: String
    var href: String?
    var sections: [HubContentSection]?
}
struct HubSnapshot: Codable, Sendable {
    var connected = false
    var name = ""
    var cards: [HubCard] = []
    var readAt: Date?
    var error = ""
    var applications: [HubHomeApplication]?
    var applicationsError: String?
}

struct HubHomeApplication: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var url: String
    var frequent: Bool

    static func decode(_ value: [String: Any]) -> [Self] {
        let top = value["top"] as? [[String: Any]] ?? []
        let all = value["all"] as? [[String: Any]] ?? []
        let favorites = Set(top.compactMap { $0["key"] as? String })
        var seen = Set<String>()
        return (top + all).compactMap { row in
            guard let id = row["key"] as? String, !id.isEmpty, id.count <= 512,
                  let name = row["name"] as? String, !name.isEmpty, name.count <= 100,
                  let raw = row["url"] as? String, raw.count <= 2048,
                  let url = URLComponents(string: raw), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, seen.insert(id).inserted else { return nil }
            return Self(id: id, name: name, url: raw, frequent: favorites.contains(id))
        }
    }
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

struct HubContentSection: Codable, Equatable, Sendable {
    var title: String = ""
    var text: String = ""
    var children: [HubContentSection] = []
}

enum HubStructured {
    private static let metadata: Set<String> = ["id","key","href","url","view","type","kind","kindLabel","live","editedAt","updatedAt","createdAt","created_at","createdBy","ownerAvatar","avatar","ownerId","recordId","record_id","userId","user_id","appToken","tableId","format","limit","committedAt","submittedAt","submitted_at","color","icon","source","schema","version"]
    private static let labels = ["name":"名称","title":"标题","label":"名称","contract":"签约方式","level":"等级","platforms":"平台","followers":"粉丝","tags":"标签","status":"状态","state":"状态","count":"数量","total":"合计","value":"数值","current":"当前","target":"目标","expected":"预期","progress":"进度","owner":"负责人","date":"日期","start":"开始","end":"结束","period":"周期","cycle":"周期","standing":"状态","results":"关键结果","description":"说明","summary":"摘要","content":"内容","text":"内容","unit":"单位","rule":"项目","due":"截止时间","trend":"趋势"]
    private static let containers: Set<String> = ["props","items","rows","entries","cards","data","fields","columns","list","records"]
    static func sections(_ value: Any, depth: Int = 0) -> [HubContentSection] {
        guard depth < 20 else { return [.init(text: "内容层级过深，请在中台查看完整内容。")] }
        if let rows = value as? [Any] { return rows.flatMap { sections($0, depth: depth + 1) } }
        if let text = value as? String {
            let cleaned = clean(text)
            return cleaned.isEmpty ? [] : [.init(text: cleaned)]
        }
        if let number = value as? NSNumber { return [.init(text: number.stringValue)] }
        guard let row = value as? [String: Any] else { return [] }
        if row["auth"] != nil { return [.init(text: "请在中台完成本人授权。")] }
        if row["forbidden"] != nil { return [.init(text: "你没有此来源的读取权限。")] }
        if row["error"] != nil { return [.init(text: "来源读取失败，请稍后刷新。")] }
        let nameKey = ["name","title","label"].first { row[$0] is String }
        let title = nameKey.flatMap { row[$0] as? String }.map(clean) ?? ""
        var children: [HubContentSection] = []
        let priority = ["contract","level","tags","status","state","value","current","target","progress","followers","platforms"]
        let keys = row.keys.sorted { a,b in
            let x = priority.firstIndex(of:a) ?? 999, y = priority.firstIndex(of:b) ?? 999
            return x == y ? a < b : x < y
        }
        for key in keys where key != nameKey && !metadata.contains(key) && !key.lowercased().hasSuffix("token") && !key.lowercased().hasSuffix("avatar") && !key.lowercased().hasSuffix("url") && !key.lowercased().hasSuffix("id") {
            guard let value = row[key] else { continue }
            var parts = sections(value, depth: depth + 1)
            guard !parts.isEmpty else { continue }
            if containers.contains(key) { children += parts; continue }
            let label = labels[key] ?? (key.unicodeScalars.contains { $0.value > 127 } ? key : "补充信息")
            if parts.count == 1, parts[0].title.isEmpty, parts[0].children.isEmpty {
                var text = parts[0].text
                if key == "followers", let n = Double(text), n >= 10000 { text = String(format: "%.1f 万", n / 10000).replacingOccurrences(of: ".0 万", with: " 万") }
                parts[0].title = label; parts[0].text = text; children += parts
            } else { children.append(.init(title: label, children: parts)) }
        }
        return title.isEmpty ? children : [.init(title: title, children: children)]
    }
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
