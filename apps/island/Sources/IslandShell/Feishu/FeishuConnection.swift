import Foundation

public struct FeishuConnection: Codable, Equatable, Sendable {
    public var cliPath: String
    public var profile: String
    public init(cliPath: String? = nil, profile: String = "feishu-island") {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lark-cli").path
        self.cliPath = cliPath ?? (FileManager.default.isExecutableFile(atPath: bundled) ? bundled : NSHomeDirectory() + "/.local/bin/lark-cli")
        self.profile = profile
    }
    public var valid: Bool {
        cliPath.hasPrefix("/") && cliPath.utf8.count <= 1024 && !cliPath.contains(where: { $0.isNewline || $0 == "\0" }) &&
        (profile.isEmpty || profile.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil)
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
