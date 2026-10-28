import AppKit
import Combine
import Foundation
import Carbon
import NookApp

struct HubPingShortcut: Codable, Equatable {
    enum Source: String, Codable, CaseIterable { case automatic, card, custom, empty }
    var source: Source = .automatic
    var cardID = ""
    var title = ""
    var address = ""
}

struct HubPingPreferences: Codable, Equatable {
    var version = 1
    var showInMainBar = true
    var soundEnabled = false
    var slots = Array(repeating: HubPingShortcut(), count: 8)
    var hotkey: NookHotkey?
}

struct HubPingDestination: Identifiable, Equatable {
    let id: Int
    let title: String
    let url: URL?
    var available: Bool { url != nil }
}

enum HubPingGeometry {
    /// Ported from LOLPingYourAI: north is zero; clockwise 45-degree sectors.
    static func slice(dx: Double, dy: Double, deadZone: Double = 55, outerLimit: Double = .infinity) -> Int? {
        guard dx.isFinite, dy.isFinite, deadZone.isFinite, deadZone >= 0 else { return nil }
        let radius = hypot(dx, dy)
        guard radius >= deadZone, radius <= outerLimit else { return nil }
        let angle = (atan2(dy, dx) * 180 / .pi + 90 + 22.5 + 360).truncatingRemainder(dividingBy: 360)
        return Int(floor(angle / 45)) % 8
    }

    static func safeURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 2048,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              !(parts.queryItems ?? []).contains(where: {
                  ["token", "access_token", "refresh_token", "password", "secret", "api_key", "authorization", "code"].contains($0.name.lowercased())
              }) else { return nil }
        return parts.url
    }
}

/// Stores only launcher preferences. Hub cards and account grants retain their
/// existing owners, so hiding the module cannot reset a connection or card list.
@MainActor
final class UnifiedPlatformStore: ObservableObject {
    static let shared = UnifiedPlatformStore()
    @Published private(set) var preferences = HubPingPreferences()
    @Published private(set) var error = ""
    @Published private(set) var lastOpened = ""
    var showInMainBar: Bool { preferences.showInMainBar }
    static let defaultHotkey = NookHotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey), keySymbol: "Space")
    var hotkey: NookHotkey { preferences.hotkey ?? Self.defaultHotkey }
    var registerHotkey: ((NookHotkey) -> Bool)?
    private let root: URL
    private var writable = true
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var playSound: () -> Void = {
        guard let file = Bundle.main.resourceURL?.appendingPathComponent("LOLPing/Base.wav"),
              let sound = NSSound(contentsOf: file, byReference: true) else { return }
        sound.volume = 0.25; sound.play()
    }

    init(root: URL? = nil) {
        let production = Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" &&
            !ProcessInfo.processInfo.arguments.contains(where: { ["--self-test", "--skin-preview", "--todo-preview", "--unified-preview"].contains($0) })
        self.root = root ?? (production
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/Platform")
            : FileManager.default.temporaryDirectory.appendingPathComponent("feibao-platform-fixture-\(ProcessInfo.processInfo.processIdentifier)"))
        let file = self.root.appendingPathComponent("preferences.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let value = try JSONDecoder().decode(HubPingPreferences.self, from: Data(contentsOf: file))
            guard value.version == 1, value.slots.count == 8,
                  value.slots.allSatisfy(Self.valid), value.hotkey.map(Self.validHotkey) ?? true else { throw WorkError.message("设置格式不受支持") }
            preferences = value
        } catch {
            writable = false
            self.error = "中台快捷设置无法读取，原文件已保留；暂不覆盖。"
        }
    }

    func reportShortcutError() { error="快捷键\(hotkey.display)未能注册，可能已被其他应用占用。请更换组合键。" }

    static func validHotkey(_ value: NookHotkey) -> Bool {
        let modifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        return value.keyCode < 128 && value.carbonModifiers & UInt32(controlKey | optionKey | cmdKey) != 0
            && value.carbonModifiers & ~modifiers == 0 && !value.keySymbol.isEmpty && value.keySymbol.count <= 16
            && !value.keySymbol.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    @discardableResult func setHotkey(_ value: NookHotkey) -> Bool {
        guard Self.validHotkey(value) else { error = "请使用包含⌘、⌥或⌃的组合键。"; return false }
        let previous = hotkey
        guard registerHotkey?(value) != false else { error = "这个快捷键未能注册，已保留原设置。请换一个组合键。"; return false }
        var next = preferences; next.hotkey = value
        if persist(next) { return true }
        _ = registerHotkey?(previous)
        return false
    }

    @discardableResult func setMainBar(_ shown: Bool) -> Bool {
        var next = preferences; next.showInMainBar = shown; return persist(next)
    }
    @discardableResult func setSound(_ enabled: Bool) -> Bool {
        var next = preferences; next.soundEnabled = enabled; return persist(next)
    }
    @discardableResult func setSlot(_ index: Int, _ shortcut: HubPingShortcut) -> Bool {
        guard preferences.slots.indices.contains(index), Self.valid(shortcut) else {
            error = "名称最多40字；自定义入口请填写不含凭据的 HTTPS 地址。"; return false
        }
        var next = preferences; next.slots[index] = shortcut; return persist(next)
    }

    func destinations(cards: [HubCard], selectedIDs: [String]) -> [HubPingDestination] {
        let ordered = selectedIDs.compactMap { id in cards.first { $0.id == id } } + cards.filter { !selectedIDs.contains($0.id) }
        let linked = ordered.filter { $0.href.flatMap(HubPingGeometry.safeURL) != nil }
        return preferences.slots.enumerated().map { index, shortcut in
            switch shortcut.source {
            case .automatic:
                if index == 0 { return .init(id: index, title: "中台首页", url: URL(string: "https://virxact.net/")) }
                guard linked.indices.contains(index - 1) else { return .init(id: index, title: "待设置", url: nil) }
                let card = linked[index - 1]
                return .init(id: index, title: card.title, url: card.href.flatMap(HubPingGeometry.safeURL))
            case .card:
                guard let card = cards.first(where: { $0.id == shortcut.cardID }) else {
                    return .init(id: index, title: "卡片暂不可用", url: nil)
                }
                return .init(id: index, title: card.title, url: card.href.flatMap(HubPingGeometry.safeURL))
            case .custom:
                return .init(id: index, title: shortcut.title, url: HubPingGeometry.safeURL(shortcut.address))
            case .empty:
                return .init(id: index, title: "空位", url: nil)
            }
        }
    }

    @discardableResult func activate(_ destination: HubPingDestination) -> Bool {
        guard let url = destination.url, HubPingGeometry.safeURL(url.absoluteString) != nil else {
            error = "这个位置尚无可打开的链接，请在中台设置中选择卡片或填写入口。"; return false
        }
        guard openURL(url) else { error = "未能打开入口，请检查默认浏览器。"; return false }
        error = ""; lastOpened = destination.title
        if preferences.soundEnabled { playSound() }
        return true
    }

    private static func valid(_ value: HubPingShortcut) -> Bool {
        guard value.cardID.count <= 512, value.title.count <= 40,
              !value.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        switch value.source {
        case .custom: return !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && HubPingGeometry.safeURL(value.address) != nil
        case .card: return !value.cardID.isEmpty && value.address.isEmpty
        case .automatic, .empty: return value.address.isEmpty && value.cardID.isEmpty
        }
    }

    private func persist(_ value: HubPingPreferences) -> Bool {
        guard writable else { error = "原设置未能读取，已停止覆盖。"; return false }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let file = root.appendingPathComponent("preferences.json")
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            preferences = value; error = ""; return true
        } catch { self.error = "中台快捷设置未保存：" + error.localizedDescription; return false }
    }
}
