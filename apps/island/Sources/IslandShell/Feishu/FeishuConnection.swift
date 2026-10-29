import Foundation

public struct FeishuConnection: Codable, Equatable, Sendable {
    public var cliPath: String
    public var profile: String
    public var localAccount: LocalFeishuAccount?
    public init(cliPath: String? = nil, profile: String = "feishu-island", localAccount: LocalFeishuAccount? = nil) {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lark-cli").path
        self.cliPath = cliPath ?? (FileManager.default.isExecutableFile(atPath: bundled) ? bundled : NSHomeDirectory() + "/.local/bin/lark-cli")
        self.profile = profile
        self.localAccount = localAccount
    }
    public var valid: Bool {
        cliPath.hasPrefix("/") && cliPath.utf8.count <= 1024 && !cliPath.contains(where: { $0.isNewline || $0 == "\0" }) &&
        (profile.isEmpty || profile.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil) &&
        (localAccount == nil || !profile.isEmpty && profile != "company" && localAccount!.valid)
    }
    public var authArguments: [String] { (profile.isEmpty ? [] : ["--profile",profile]) + ["auth","login"] }
}

func legacyDanmuConflict(_ executablePaths:[String]) -> Bool {
    executablePaths.contains { $0.hasSuffix("/FeishuDanmuWeb/launcher") || $0.hasSuffix("/Contents/MacOS/FeishuDanmu") || $0.hasSuffix("/飞书弹幕.app/Contents/MacOS/飞书弹幕") }
}

/// Kept pure so installing the product never tests a real account by accident.
enum FeishuConnectionBootPolicy {
    static func needsAuthorization(_ status: String) -> Bool {
        ["公司登录或飞书授权已失效", "公司登录未就绪", "公司登录已过期"].contains { status.contains($0) }
    }
    static func shouldOffer(savedEnabled: Bool?, hasConnection: Bool) -> Bool {
        savedEnabled == nil && !hasConnection
    }
}

/// Non-secret identity binding. Credentials remain in the official local CLI.
public struct LocalFeishuAccount: Codable, Equatable, Sendable {
    public let appID: String
    public let openID: String
    public let userName: String
    var valid: Bool { appID.hasPrefix("cli_") && appID.count < 128 && openID.hasPrefix("ou_") && openID.count < 200 && !userName.isEmpty && userName.count < 200 }
    static let requiredScopes = Set("auth:user.id:read im:chat:read im:chat.user_setting:read im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user im:message:readonly offline_access".split(separator: " ").map(String.init))
    static func verified(_ json: [String: Any], expected: LocalFeishuAccount? = nil, required: Set<String> = requiredScopes) throws -> LocalFeishuAccount {
        guard json["verified"] as? Bool == true,
              let app = json["appId"] as? String,
              let identities = json["identities"] as? [String: Any],
              let user = identities["user"] as? [String: Any], user["available"] as? Bool == true,
              user["verified"] as? Bool == true, let open = user["openId"] as? String,
              let name = user["userName"] as? String else {
            throw AccountFailure(detail: "本机飞书账号尚未通过验证，请先完成本机CLI登录。")
        }
        let account = LocalFeishuAccount(appID: app, openID: open, userName: name)
        guard account.valid else { throw AccountFailure(detail: "本机飞书账号信息不完整。") }
        if let expected, expected.appID != app || expected.openID != open {
            throw AccountFailure(detail: "本机CLI账号已变化，已停止消息连接。请核对账号后重新绑定。")
        }
        let scopes = Set((user["scope"] as? String ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
        guard required.isSubset(of: scopes) else {
            throw AccountFailure(detail: "本机账号缺少所选用途的权限，请先授权：" + required.subtracting(scopes).sorted().joined(separator: "、"))
        }
        return account
    }
    static func validateBinding(_ json: [String: Any], expected: LocalFeishuAccount) throws {
        guard json["appId"] as? String == expected.appID,
              let identities = json["identities"] as? [String:Any], let user = identities["user"] as? [String:Any],
              user["available"] as? Bool == true, user["openId"] as? String == expected.openID else {
            throw AccountFailure(detail: "本机CLI账号已变化，已停止读取。请核对账号后重新连接。")
        }
    }
    static func environment(_ original: [String: String]) -> [String: String] {
        // The selected local profile must not be overridden by a launcher's
        // injected token, proxy, config directory or application credentials.
        var env = original.filter { !$0.key.hasPrefix("LARKSUITE_CLI_") }
        env["LARKSUITE_CLI_DEFAULT_AS"] = "user"
        env["LARKSUITE_CLI_STRICT_MODE"] = "user"
        env["LARKSUITE_CLI_NO_UPDATE_NOTIFIER"] = "1"
        env["LARKSUITE_CLI_NO_SKILLS_NOTIFIER"] = "1"
        return env
    }
    static func inspect(_ connection: FeishuConnection) throws -> LocalFeishuAccount {
        guard connection.valid, connection.profile != "company", !connection.profile.isEmpty else {
            throw AccountFailure(detail: "请选择明确的本机飞书账号配置。")
        }
        return try LocalCLIJob.verified(connection, purpose: .receive)
    }
}
