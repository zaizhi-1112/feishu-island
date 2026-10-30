import Foundation

struct DanmuMessage {
    let text: String
    let receivedAt: Date
    let demo: Bool
    var gray: Bool = false
    var createdAt: Date? = nil
    var enqueuedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    var identity = UUID()
    var messageID: String? = nil
    var segment = 0
    var segments: [String] = []
    var sourceMessage: FeishuMessage? = nil
}

// No message is persisted. Dedupe by notification element identity, not body:
// identical messages from different notifications are legitimate.
struct NotificationTracker {
    private var visible = Set<String>()
    private var initialized = false
    mutating func update(_ ids: Set<String>) -> Set<String> {
        defer { visible = ids; initialized = true }
        return initialized ? ids.subtracting(visible) : []
    }
    mutating func reset() { visible = []; initialized = false }
}

func cleanMessage(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

func isCardMessage(_ text: String) -> Bool {
    let body = text.firstIndex(of: "：").map { String(text[text.index(after: $0)...]) } ?? text
    return body.count > 10
}
func cardReadingDuration(_ characters: Int) -> TimeInterval {
    max(12, min(45, 4 + Double(characters) / 4))
}
