import AppKit
import CoreImage
import NookApp
import SwiftUI

/// Native port of LOLPingYourAI's eight-slice wheel. The interaction stays inside
/// a transparent circular panel: click or drag-and-release opens a destination.
@MainActor
struct HubPingWheel: View {
    let destinations: [HubPingDestination]
    var diameter: CGFloat = 320
    var activate: (HubPingDestination) -> Bool
    var cancel: () -> Void = {}
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
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color(red: 0.14, green: 0.17, blue: 0.20).opacity(0.72))
                    .frame(width: 316 * scale, height: 316 * scale)
                ForEach(0..<8, id: \.self) { index in
                    let active = hovered == index
                    HubWheelSector(index: index, inner: 75 * scale, outer: 158 * scale)
                        .fill(active ? Color.white.opacity(0.19) : Color.clear)
                    HubWheelSector(index: index, inner: 75 * scale, outer: 158 * scale)
                        .stroke(Color(red: 0.69, green: 0.58, blue: 0.34).opacity(active ? 0.85 : 0.28), lineWidth: active ? 1.5 : 0.6)
                    icon(index)
                }
                Circle().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.28, blue: 0.29), Color(red: 0.04, green: 0.10, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 146 * scale, height: 146 * scale)
                    .overlay(Circle().stroke(Color(red: 0.78, green: 0.67, blue: 0.43), lineWidth: 2.8))
                    .overlay(Circle().stroke(Color(red: 0.78, green: 0.67, blue: 0.43).opacity(0.65), lineWidth: 0.8).padding(6 * scale))
                VStack(spacing: 5) {
                    if let image = HubPingAsset.image("generic_ping") {
                        Image(nsImage:image).resizable().scaledToFit().frame(width:34 * scale,height:34 * scale)
                    }
                    Text("PING").font(.system(size: 15 * scale, weight: .bold)).foregroundStyle(.cyan)
                    Label(dragging ? "移回取消" : "关闭", systemImage: "computermouse")
                        .font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.55)).padding(.top, 6 * scale)
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
                    if let choice, let destination = destinations.first(where: { $0.id == choice }) { launch(destination) } else { cancel() }
                })
            .onExitCommand { hovered = nil; cancelledGesture = true; cancel() }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("中台八方向快捷轮盘")
            .accessibilityChildren {
                Button("关闭轮盘", action: cancel)
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

        }
        .accessibilityIdentifier("island.platform.pingWheel")
    }

    private func pick(_ point: CGPoint) -> Int? {
        HubPingGeometry.slice(dx: Double(point.x - diameter / 2), dy: Double(point.y - diameter / 2), deadZone: Double(75 * scale), outerLimit: Double(diameter / 2))
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
                if let image = HubPingAsset.image(Self.icons[index], gold: true) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Image(systemName: "scope").resizable().scaledToFit() }
            }
            .frame(width: 29 * scale, height: 29 * scale)
            .shadow(color:.black.opacity(0.5),radius:1,y:1)
            .scaleEffect(active && !reduceMotion ? 1.12 : 1)
            Text(destination?.title ?? "空位").font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(destination?.available == true ? 0.95 : 0.38))
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 76 * scale, height: 30 * scale)
        }
        .frame(width: 78 * scale, height: 65 * scale)
        .opacity(destination?.available == true ? 1 : 0.44)
        .offset(x: CGFloat(cos(angle)) * 116 * scale, y: CGFloat(sin(angle)) * 116 * scale)
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
    private static let context = CIContext()
    static func image(_ name: String, gold: Bool = false) -> NSImage? {
        let key = name + (gold ? ":gold" : "")
        if let image = images[key] { return image }
        var candidates = [Bundle.main.resourceURL?.appendingPathComponent("LOLPing/\(name).png")].compactMap { $0 }
        if IslandRuntime.isSkinPreview {
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<4 { root.deleteLastPathComponent() }
            candidates.append(root.appendingPathComponent("Resources/LOLPing/\(name).png"))
        }
        guard var image = candidates.lazy.compactMap({ NSImage(contentsOf: $0) }).first else { return nil }
        if gold, let source = image.cgImage(forProposedRect:nil,context:nil,hints:nil) {
            let tone = CIImage(cgImage:source)
                .applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputBrightnessKey:0.08])
                .applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:1,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.87,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:0.53,w:0)])
            if let output = context.createCGImage(tone,from:tone.extent) { image = NSImage(cgImage:output,size:image.size) }
        }
        images[key] = image; return image
    }
}
