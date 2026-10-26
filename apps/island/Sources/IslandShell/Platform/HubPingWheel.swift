import AppKit
import NookApp
import SwiftUI

/// Native port of LOLPingYourAI's eight-slice wheel. The interaction stays inside
/// the island: a click or a drag-and-release opens one destination, never a task.
@MainActor
struct HubPingWheel: View {
    let destinations: [HubPingDestination]
    var diameter: CGFloat = 320
    var activate: (HubPingDestination) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?
    @State private var dragging = false
    @State private var cancelledGesture = false
    @State private var pulse: Int?
    @State private var pulseID = UUID()

    static let icons = ["pingwheel_retreatrender", "push", "omw", "all_in", "assist_me", "need_vision", "enemy_missing", "pingwheel_enemyvisionrender"]
    static let colors: [Color] = [.red, .green, .blue, .orange, .green, .green, .yellow, .pink]
    private var scale: CGFloat { diameter / 320 }
    private var selection: HubPingDestination? { destinations.first { $0.id == hovered } }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.23), .black.opacity(0.04)], center: .center, startRadius: 70 * scale, endRadius: 160 * scale))
                ForEach(0..<8, id: \.self) { index in
                    let active = hovered == index
                    HubWheelSector(index: index, inner: 51 * scale, outer: (active ? 153 : 143) * scale)
                        .fill(active ? Self.colors[index].opacity(0.27) : Color.white.opacity(0.055))
                    HubWheelSector(index: index, inner: 51 * scale, outer: 143 * scale)
                        .stroke(Color(red: 0.69, green: 0.58, blue: 0.34).opacity(active ? 0.85 : 0.28), lineWidth: active ? 1.5 : 0.6)
                    icon(index)
                }
                Circle().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.28, blue: 0.29), Color(red: 0.04, green: 0.10, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 102 * scale, height: 102 * scale)
                    .overlay(Circle().stroke(Color(red: 0.78, green: 0.67, blue: 0.43), lineWidth: 1.5))
                VStack(spacing: 5) {
                    Image(systemName: "scope").font(.system(size: 21 * scale, weight: .light)).foregroundStyle(.cyan.opacity(0.9))
                    Text(dragging ? "移回取消" : "快捷信号").font(.system(size: 11 * scale, weight: .semibold)).foregroundStyle(.white)
                    Text("中台").font(.system(size: 9 * scale)).foregroundStyle(.white.opacity(0.55))
                }.allowsHitTesting(false)
                if let pulse {
                    Circle().stroke(Self.colors[pulse].opacity(0.8), lineWidth: 2)
                        .frame(width: 288 * scale, height: 288 * scale)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.65).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .onContinuousHover { phase in
                guard !dragging else { return }
                switch phase {
                case .active(let point): hovered = pick(point)
                case .ended: hovered = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !dragging { cancelledGesture = false }
                    dragging = true
                    if !cancelledGesture { hovered = pick(value.location) }
                }
                .onEnded { value in
                    let choice = pick(value.location)
                    dragging = false; hovered = nil
                    guard !cancelledGesture else { cancelledGesture = false; return }
                    if let choice, let destination = destinations.first(where: { $0.id == choice }) { launch(destination) }
                })
            .onExitCommand { hovered = nil; cancelledGesture = true }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("中台八方向快捷轮盘")
            .accessibilityChildren {
                ForEach(destinations) { destination in
                    Button(destination.title) { launch(destination) }.disabled(!destination.available)
                }
            }
            .task(id: pulseID) {
                guard pulse != nil else { return }
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { pulse = nil }
            }
            Text(selection.map { $0.available ? $0.title : "\($0.title) · 在设置中配置" } ?? "点击信号打开 · 按住拖向信号后松手也可以")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 30).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("island.platform.pingWheel")
    }

    private func pick(_ point: CGPoint) -> Int? {
        HubPingGeometry.slice(dx: Double(point.x - diameter / 2), dy: Double(point.y - diameter / 2), deadZone: Double(51 * scale), outerLimit: Double(diameter / 2))
    }
    private func launch(_ destination: HubPingDestination) {
        guard destination.available, activate(destination) else { return }
        pulseID = UUID()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.25)) { pulse = destination.id }
    }
    private func icon(_ index: Int) -> some View {
        let angle = (Double(index) * 45 - 90) * .pi / 180
        let destination = destinations.first { $0.id == index }
        let active = hovered == index
        return VStack(spacing: 4) {
            Group {
                if let image = HubPingAsset.image(Self.icons[index]) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Image(systemName: "scope").resizable().scaledToFit() }
            }
            .frame(width: 29 * scale, height: 29 * scale)
            .saturation(active ? 1 : 0.35)
            .scaleEffect(active && !reduceMotion ? 1.12 : 1)
            Text(destination?.title ?? "空位").font(.system(size: 10 * scale, weight: active ? .semibold : .regular))
                .foregroundStyle(.white.opacity(destination?.available == true ? 0.95 : 0.38))
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 63 * scale, height: 26 * scale)
        }
        .frame(width: 66 * scale, height: 62 * scale)
        .opacity(destination?.available == true ? 1 : 0.44)
        .offset(x: CGFloat(cos(angle)) * 101 * scale, y: CGFloat(sin(angle)) * 101 * scale)
        .allowsHitTesting(false)
    }
}

private struct HubWheelSector: Shape {
    var index: Int
    var inner: CGFloat
    var outer: CGFloat
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle.degrees(Double(index) * 45 - 112.5)
        let end = Angle.degrees(Double(index) * 45 - 67.5)
        var path = Path()
        path.move(to: CGPoint(x: center.x + inner * cos(start.radians), y: center.y + inner * sin(start.radians)))
        path.addLine(to: CGPoint(x: center.x + outer * cos(start.radians), y: center.y + outer * sin(start.radians)))
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addLine(to: CGPoint(x: center.x + inner * cos(end.radians), y: center.y + inner * sin(end.radians)))
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

@MainActor
enum HubPingAsset {
    private static var images: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let root = Bundle.main.resourceURL,
              let image = NSImage(contentsOf: root.appendingPathComponent("LOLPing/\(name).png")) else { return nil }
        images[name] = image; return image
    }
}
