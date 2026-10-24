import AppKit
import NookApp
import SwiftUI

enum IslandRuntime {
    static var isTodoPreview: Bool {
        Bundle.main.bundleIdentifier == "local.youzi.island.todo-preview" || ProcessInfo.processInfo.arguments.contains("--todo-preview")
    }
    static var isSkinPreview: Bool {
        isTodoPreview || Bundle.main.bundleIdentifier == "local.youzi.island.skin-preview" || ProcessInfo.processInfo.arguments.contains("--skin-preview")
    }
}

struct SkinPalette: Decodable {
    let bg, surface, sidebar, well, ink, secondary, muted, border, line, accent, accentInk, accentSoft, onAccent, glow: String
}
struct SkinDefinition: Decodable {
    let id, title, subtitle, mood, pet, source: String
    let dark, light: SkinPalette
}
struct AgentArtwork: Decodable { let portrait, avatar, source: String }
struct BrandGeometry: Decodable { let aspect: Double; let paths: [[[Double]]] }
struct BrandStreamline: Decodable { let points: [[Double]]; let length, speed: Double }
struct BrandFlowAsset: Decodable { let aspect: Double; let lanes: [BrandStreamline] }
struct BrandFlowLane {
    let points: [[Double]]
    let distances: [Double]
    let length, speed: Double
    init(_ line: BrandStreamline, aspect: Double) {
        points = line.points; speed = line.speed
        var d = [0.0]
        for i in 1..<points.count { d.append(d.last! + hypot(points[i][0]-points[i-1][0], (points[i][1]-points[i-1][1])/aspect)) }
        distances = d; length = d.last!
    }
    func point(at distance: Double) -> CGPoint {
        let d = min(length, max(0, distance))
        var low = 1, high = distances.count - 1
        while low < high { let mid = (low+high)/2; if distances[mid] < d { low = mid+1 } else { high = mid } }
        let f = (d-distances[low-1])/max(0.000001,distances[low]-distances[low-1])
        return CGPoint(x:points[low-1][0]+(points[low][0]-points[low-1][0])*f,y:points[low-1][1]+(points[low][1]-points[low-1][1])*f)
    }
}
struct SkinManifest: Decodable {
    let version: Int
    let skins: [SkinDefinition]
    let agents: [String: AgentArtwork]
    static let shared: SkinManifest = {
        guard let url = SkinResources.url("skins.json"), let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data), manifest.skins.count == 4 else {
            preconditionFailure("The bundled skins.json is missing or invalid")
        }
        return manifest
    }()
}
enum SkinResources {
    static func url(_ name: String) -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("SettingsWeb/\(name)")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        // SwiftPM checks run outside an app bundle; read exactly the same source manifest.
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SettingsWeb/dist/\(name)")
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }
    static let geometry: BrandGeometry = {
        let geometryURL = SkinResources.url("brand-geometry.json")!
        return try! JSONDecoder().decode(BrandGeometry.self, from: Data(contentsOf: geometryURL))
    }()
    static let brandLanes: [BrandFlowLane] = {
        let asset = try! JSONDecoder().decode(BrandFlowAsset.self, from: Data(contentsOf: SkinResources.url("brand-flow.json")!))
        return asset.lanes.enumerated().filter { $0.offset % 3 == 0 }.map { BrandFlowLane($0.element, aspect:asset.aspect) }
    }()
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["pet-codex.png","pet-claude.png","pet-workbuddy.png","avatar-codex.png","avatar-claude.png","avatar-workbuddy.png","avatar-virxact.png","virxact-logo.png"] {
            if let url = SkinResources.url(name), let image = NSImage(contentsOf: url) { result[name] = image }
        }
        return result
    }()
}

enum AgentSkin: String, CaseIterable {
    case codex, claude, workbuddy, virxact
    init(agentID: String) { self = Self(rawValue: agentID) ?? .codex }
    var definition: SkinDefinition { SkinManifest.shared.skins.first { $0.id == rawValue }! }
    var title: String { definition.title }
    var accentHex: String { definition.dark.accent }
    var accent: Color { Color(skinHex: accentHex) }
    func palette(dark: Bool) -> SkinPalette { dark ? definition.dark : definition.light }
    var theme: NookTheme {
        let dark = definition.dark, light = definition.light
        var theme = IslandDesign.chrome
        func adaptive(_ d: String, _ l: String) -> NookColorValue {
            .adaptive(.init(dark: .hex(NookRGBA(hex: d)!), light: .hex(NookRGBA(hex: l)!)))
        }
        theme.name = "柚子岛 · \(title)"; theme.allowsUserAccent = false
        theme.accent = adaptive(dark.accent, light.accent)
        theme.tokens[.fillSubtle] = adaptive(dark.surface, light.surface)
        theme.tokens[.strokeSubtle] = adaptive(dark.border, light.border)
        theme.tokens[.labelPrimary] = adaptive(dark.ink, light.ink)
        theme.tokens[.labelSecondary] = adaptive(dark.secondary, light.secondary)
        theme.tokens[.labelTertiary] = adaptive(dark.muted, light.muted)
        theme.tokens[.iconInactive] = adaptive(dark.secondary, light.secondary)
        return theme
    }
    func greeting(state: AgentState, enabled: Bool) -> String {
        guard enabled else { return "安静陪你，监测已暂停" }
        switch state {
        case .working: return "正在忙，陪你一起专心"
        case .completed: return "这轮做好啦，来看看吧"
        case .waiting: return "有件事等你确认"
        case .failed: return "遇到一点问题，看看详情吧"
        case .unknown: return "我在这里，等一个新消息"
        }
    }
}
extension Color {
    init(skinHex: String) {
        let digits = String(skinHex.dropFirst()); let number = UInt64(digits, radix: 16) ?? 0
        let rgba = digits.count == 8 ? number : (number << 8) | 255
        self.init(.sRGB, red: Double((rgba >> 24) & 255) / 255, green: Double((rgba >> 16) & 255) / 255, blue: Double((rgba >> 8) & 255) / 255, opacity: Double(rgba & 255) / 255)
    }
}

/// Identity always comes from the Agent, never the selected theme.
struct AgentPortrait: View {
    let id: String
    var size: CGFloat = 64
    var avatar = false
    var state: AgentState = .unknown
    var motion = true
    // Embedded in an expand/switch control, the parent owns clicks; hover stays local.
    var tapFeedback = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nookResolvedTheme) private var theme
    @State private var hovering = false
    @State private var greeting = false
    @ViewBuilder
    var body: some View {
        if tapFeedback {
            portrait.onTapGesture { greeting = true }
        } else {
            portrait
        }
    }
    @ViewBuilder
    private var portrait: some View {
        let name = id == "virxact" ? "avatar-virxact.png" : (avatar ? "avatar-\(id).png" : "pet-\(id).png")
        Group {
            if let image = SkinResources.images[name] {
                if id == "virxact" {
                    Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).scaledToFit().foregroundStyle(theme.primaryLabel)
                } else { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            } else { Image(systemName: "sparkles").resizable().scaledToFit() }
        }
        .frame(width: size, height: size)
        .scaleEffect(!reduceMotion && motion && greeting ? 1.06 : 1)
        .rotationEffect(.degrees(!reduceMotion && motion && hovering ? -3 : 0))
        .offset(y: !reduceMotion && motion && greeting ? -3 : 0)
        .overlay(alignment: .topTrailing) {
            if greeting { Image(systemName: "sparkle").font(.system(size: max(9,size / 5))).foregroundStyle(AgentSkin(agentID: id).accent).accessibilityHidden(true) }
        }
        .contentShape(Rectangle()).onHover {
            hovering = $0
            if ProcessInfo.processInfo.environment["YU_ISLAND_TRACE"] == "1" {
                let message = "[portrait] id=\(id) hover=\($0) motion=\(motion) reduceMotion=\(reduceMotion) tapFeedback=\(tapFeedback)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
        }
        .task(id: greeting) {
            guard greeting else { return }
            do { try await Task.sleep(for: .milliseconds(900)); greeting = false } catch { }
        }
        .animation(reduceMotion || !motion ? nil : .spring(response: 0.4, dampingFraction: 0.65), value: greeting)
        .animation(reduceMotion || !motion ? nil : .easeOut(duration: 0.25), value: hovering)
        .accessibilityIdentifier("agent.portrait.\(id)")
        .accessibilityLabel(id == "virxact" ? "虚实传媒品牌标志" : "\(id)官方角色")
    }
}
struct AgentCompanionGlyph: View {
    @ObservedObject var store: AgentStore
    var body: some View {
        AgentPortrait(id: store.primary.id, size: 25, avatar: true, state: store.state, motion: store.preferences.effectsEnabled, tapFeedback: false)
            .overlay(alignment: .bottomTrailing) { Circle().fill(store.state.color).frame(width: 5, height: 5) }
            .accessibilityLabel("\(store.primary.name)，\(store.preferences.enabled ? store.state.label : "监测已暂停")")
    }
}
struct IslandSkinSettings: View {
    @ObservedObject var store: AgentStore
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AgentPortrait(id: store.selectedSkin.rawValue, size: 54, motion: store.preferences.effectsEnabled)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedSkin.title).font(.system(size: 13, weight: .semibold))
                    Text("胶囊、功能页和设置一起换肤").font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 6) {
                ForEach(AgentSkin.allCases, id: \.rawValue) { skin in
                    Button(skin.title.components(separatedBy: " · ").first ?? skin.title) { store.selectSkin(skin.rawValue) }
                        .buttonStyle(IslandButtonStyle(prominent: skin.rawValue == store.preferences.skinID))
                }
            }
            HStack {
                Button { store.selectSkin("auto") } label: { Label("跟随主用Agent", systemImage: store.preferences.skinID == "auto" ? "checkmark.circle.fill" : "circle") }
                    .buttonStyle(IslandButtonStyle(prominent: store.preferences.skinID == "auto"))
                Button { store.setEffectsEnabled(!store.preferences.effectsEnabled) } label: { Label("动态",systemImage:store.preferences.effectsEnabled ? "sparkles" : "pause.fill") }
                    .buttonStyle(IslandButtonStyle(prominent: store.preferences.effectsEnabled))
            }
            Text("皮肤与Agent独立选择，点选即保存。")
                .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
        }
    }
}
struct AgentNotificationPeek: View {
    let profileID: String
    let message: String
    let motion: Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        HStack(spacing: 10) {
            AgentPortrait(id: profileID, size: 30, avatar: true, motion: motion, tapFeedback: false)
            Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.primaryLabel)
        }.padding(12)
    }
}
