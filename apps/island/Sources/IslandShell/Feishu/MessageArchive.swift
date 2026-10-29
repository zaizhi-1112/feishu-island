import Foundation

struct MessageRetention: Codable, Equatable {
    var days = 7
    var cleanupMinute = 3 * 60
    static let choices = [0, 1, 3, 7, 14, 30]
    var valid: Bool { Self.choices.contains(days) && (0..<1440).contains(cleanupMinute) }
    func cleanupSlot(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let candidate = calendar.date(byAdding: .minute, value: cleanupMinute, to: today)!
        return candidate <= now ? candidate : calendar.date(byAdding: .day, value: -1, to: candidate)!
    }
}

struct MessageArchiveSnapshot: Codable {
    var schema = 1
    var accountKey: String
    var startedAt: Date
    var messages: [FeishuMessage] = []
    var pending: Set<String> = []
    var checkpoints: [String: Date] = [:]
    var lastCleanup = Date.distantPast
    mutating func prune(days: Int, now: Date) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        messages.removeAll { $0.created < cutoff }
        pending.formIntersection(Set(messages.map(\.id)))
        checkpoints = checkpoints.mapValues { max($0, cutoff) }
        startedAt = max(startedAt, cutoff)
        lastCleanup = now
    }
}

/// User-requested local history. No API, credentials or diagnostic body logging.
/// The filename is an account hash; all files remain inside a private app directory.
final class MessageArchive {
    let key: String
    let file: URL
    init(root: URL, key: String) {
        precondition(key.count == 64 && key.allSatisfy { $0.isHexDigit })
        self.key = key; file = root.appendingPathComponent(key + ".json")
    }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeishuIsland/MessageHistory", isDirectory: true)
    }
    func load(days: Int, now: Date) throws -> MessageArchiveSnapshot {
        guard days > 0, FileManager.default.fileExists(atPath: file.path) else {
            return MessageArchiveSnapshot(accountKey: key, startedAt: now.addingTimeInterval(days > 0 ? -86400 : 0))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 100_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        var snapshot = try JSONDecoder().decode(MessageArchiveSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.schema == 1, snapshot.accountKey == key else { throw CocoaError(.fileReadCorruptFile) }
        snapshot.prune(days: days, now: now)
        return snapshot
    }
    static func expireAll(root: URL, days: Int, now: Date) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        guard try fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileReadCorruptFile) }
        for file in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            guard key.count == 64, key.allSatisfy({ $0.isHexDigit }) else { continue }
            let archive = MessageArchive(root: root, key: key)
            let snapshot = try archive.load(days: days, now: now)
            try archive.save(snapshot)
        }
    }
    func save(_ snapshot: MessageArchiveSnapshot) throws {
        guard snapshot.accountKey == key else { throw CocoaError(.fileWriteInvalidFileName) }
        let fm = FileManager.default, parent = file.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: file.path), try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType != .typeRegular { throw CocoaError(.fileWriteInvalidFileName) }
        let attrs = try fm.attributesOfItem(atPath: parent.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileWriteInvalidFileName) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        // Atomic replacement preserves the previous complete snapshot if writing fails.
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
