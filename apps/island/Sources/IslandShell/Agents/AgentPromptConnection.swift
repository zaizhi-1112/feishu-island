import AppKit
import Foundation

/// A user-created local handoff. No network listener or direct preferences editing is needed.
struct AgentPromptConnection: Identifiable {
    let id: UUID
    let folder: URL
    var manifestURL: URL { folder.appendingPathComponent("connection.json") }
    var statusURL: URL { folder.appendingPathComponent("status.json") }

    init(root: URL? = nil) throws {
        id=UUID()
        let root=root ?? (IslandRuntime.isSkinPreview ? FileManager.default.temporaryDirectory.appendingPathComponent("island-preview-connections") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/AgentConnections"))
        folder=root.appendingPathComponent(id.uuidString.lowercased(),isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }

    var prompt: String {
        """
        请把你自己接入这台Mac的“一切在岛”，让我看到你的真实工作状态与可取得的额度。请直接完成本机配置，不要求我手填路径或修改应用设置。

        此提示词适用于任意Agent。先确认你能访问这台Mac的本机文件；如果只能网页聊天、没有本机文件能力，请明确说明无法自动接入，不要伪造接入成功，也不要让我提供密码或密钥。
        只处理本次接入：保留已有配置和其他Agent；不要改“一切在岛”的偏好文件，不新增付费服务、系统权限或网络开放端口。

        本次专属目录：\(folder.path)
        接入结果文件：\(manifestURL.path)
        自定义状态文件：\(statusURL.path)
        保持“一切在岛”的接入窗口打开，文件准备好后它会自动读取并接入。目录或文件已存在时先读取，避免覆盖其他内容。写入用同目录临时文件加原子替换，目录权限0700，文件0600。

        如果你是Codex、Claude Code或WorkBuddy：本应用已有本机读取器，不必另写脚本或修改你的hooks。将connection.json写为：
        {"version":1,"name":"你的工具名称","builtinID":"对应的codex、claude或workbuddy"}
        builtinID只允许上述三个值，且必须与你实际所在的工具一致。Claude网页聊天不属于Claude Code。

        如果你是其他Agent：先写status.json，最后再写connection.json。
        connection.json格式：{"version":1,"name":"你的真实工具名称"}。name为1至40字；可选applicationPath为此Mac实际安装的.app绝对路径，或launchURL为不含账号、查询参数或令牌的HTTPS工具入口。不要填builtinID。
        status.json初始格式：{"sessions":[],"quotas":[],"metrics":[],"source":"你的工具名称","detail":"说明已经接入哪些真实数据，以及后续状态如何更新"}。
        请利用你实际支持的本机事件或hook持续更新状态：工作开始写working，需要人确认写waiting，结束写completed或failed。每个会话使用稳定且不泄露正文的id、updatedAt为真实Unix秒；完成附唯一completionID，重试写同一ID。等待人时可附attentionID与attentionReason（input或approval）。运行中如有心跳至少每分钟更新；不要用盲目定时写working冒充真实运行。
        sessions条目格式为id、state、updatedAt，可选completionID、attentionID、attentionReason；state仅working/waiting/completed/failed/unknown。
        quotas仅在来源提供可靠总量或剩余百分比时填写id、label、remainingPercent（0至100的剩余百分比）、updatedAt，可选resetsAt（Unix秒）、remainingUnits、totalUnits。只有剩余积分、没有总量时用metrics：id、label、value、unit、updatedAt，不能编造百分比。
        拿不到的数据留空；如果无法持续更新，请在detail和回复中明确“只能报告本次会话”或“暂不支持自动状态”，不能承诺以后自动监测。状态和额度超过15分钟会显示待更新。文件不超过256KB，sessions最多200条、quotas和metrics各最多30条；只写状态和数值，不写聊天正文、文件内容或登录凭据。

        最后读取并验证JSON，告诉我：已配置的来源、能获取与不能获取的数据、能否持续更新。写好文件代表准备完成；只有“一切在岛”显示已接入才算连接成功。
        """
    }

    @MainActor func connect(to store: AgentStore) throws -> String? {
        guard FileManager.default.fileExists(atPath:manifestURL.path) else {return nil}
        struct Manifest: Decodable { let version:Int;let name:String;var builtinID:String?;var applicationPath:String?;var launchURL:String? }
        let attrs=try FileManager.default.attributesOfItem(atPath:manifestURL.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 8192 else {throw AgentReadError.unavailable("接入结果须为8KB以内的普通JSON文件。")}
        let bytes=try Data(contentsOf:manifestURL)
        guard bytes.count<=8192 else{throw AgentReadError.unavailable("接入结果过大。")}
        let result=try JSONDecoder().decode(Manifest.self,from:bytes)
        let name=result.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard result.version==1,!name.isEmpty,name.count<=40,!name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else {throw AgentReadError.unavailable("请让Agent检查接入版本与工具名称。")}
        var p=store.preferences
        let profile: AgentProfile
        if let builtin=result.builtinID {
            guard ["codex","claude","workbuddy"].contains(builtin),let existing=p.profiles.first(where:{$0.id==builtin}) else {throw AgentReadError.unavailable("内置工具标识无效；其他Agent请使用自定义状态文件。")}
            profile=existing
        } else {
            let existing=p.profiles.first{$0.name.caseInsensitiveCompare(name) == .orderedSame}
            guard existing == nil || existing?.kind == "file" || existing?.kind == "launcher" else {throw AgentReadError.unavailable("此名称已有内置接入，请使用对应builtinID。")}
            var custom=AgentProfile(id:existing?.id ?? "custom-"+id.uuidString.lowercased(),name:name,kind:"file",dataPath:statusURL.path)
            custom.applicationPath=result.applicationPath ?? existing?.applicationPath
            custom.launchURL=result.launchURL ?? existing?.launchURL
            if let path=custom.applicationPath, Bundle(url:URL(fileURLWithPath:path))?.bundleIdentifier == nil {throw AgentReadError.unavailable("客户端路径无效；可以省略后重新接入。")}
            _=try CustomAgentReader.read(custom)
            profile=custom
        }
        if let index=p.profiles.firstIndex(where:{$0.id==profile.id}) {p.profiles[index]=profile} else {p.profiles.append(profile)}
        if !p.activeMonitorIDs.contains(profile.id) {p.monitoredIDs=p.activeMonitorIDs+[profile.id]}
        if !p.visibleIDs.contains(profile.id),p.visibleIDs.count<3 {p.visibleIDs.append(profile.id)}
        p.enabled=true
        try store.update(p)
        return profile.name
    }
}
