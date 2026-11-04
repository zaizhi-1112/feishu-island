import Foundation

// Only the reader's collaborators are substituted. AccountReader itself is
// compiled from the production source and the fake CLI never uses an account.
struct LocalFeishuAccount {
    static func validateBinding(_ value: [String: Any], expected: Self) throws {}
    static func verified(_ value: [String: Any], expected: Self) throws -> Self { expected }
    static func environment(_ inherited: [String: String]) -> [String: String] { inherited }
}

struct SyntheticCredential {
    let openID = "synthetic"
    let userName = "synthetic"
    func environment(_ inherited: [String: String]) -> [String: String] { inherited }
}

final class CompanyConnection {
    static let shared = CompanyConnection()
    static let profile = "company"
    enum Purpose { case receive }
    func credential(_ purpose: Purpose) throws -> SyntheticCredential? { nil }
}

struct MessageArchiveSnapshot {
    let startedAt: Date
    let checkpoints: [String: Date]
}

final class MessageArchive {
    let file = URL(fileURLWithPath: "/nonexistent/synthetic")
    static func expireAll(root: URL, days: Int, now: Date) throws {}
    func load(days: Int, now: Date) throws -> MessageArchiveSnapshot {
        MessageArchiveSnapshot(startedAt: now, checkpoints: [:])
    }
}

struct FeishuMessage {
    init(raw: [String: Any], chatID: String, chatName: String, chatKind: String, ownID: String) {}
}

final class ServerClock {
    func refreshIfNeeded() throws {}
    func now() -> Date { Date() }
    var offset: TimeInterval { 0 }
}
