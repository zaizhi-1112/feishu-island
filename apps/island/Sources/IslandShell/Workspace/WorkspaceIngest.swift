import NookApp
import SwiftUI
import UniformTypeIdentifiers

/// Save-confirmation timing stays independent of the native drag session.
enum IngestMotion {
    static let duration: Double = 1.15
    static func progress(elapsed: Double) -> Double { min(1,max(0,elapsed / duration)) }
    static func fileRadius(_ p: Double) -> Double { 79 * pow(max(0,1 - min(1,max(0,p))/0.77),1.15) }
}

enum IngestPhase { case waiting, saving, receipt }

/// Uses OpenNook's real AppKit drag-session signal, before mouse-up. No extra window.
/// The original view stays mounted (including draft text and scroll position), but invisible.
/// Only the visible chrome shortens; OpenNook's native drag interceptor keeps its region.
struct WorkspaceDropSurface<Content: View>: View {
    @EnvironmentObject private var shell: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: WorkspaceStore
    @State private var textTarget = false
    private let content: Content
    init(store: WorkspaceStore, @ViewBuilder content: () -> Content) {
        self.store = store; self.content = content()
    }
    private var presenting: Bool { shell.isDragInFlight || textTarget || store.ingestSaving || store.ingestActive }
    private var phase: IngestPhase { store.ingestActive ? .receipt : store.ingestSaving ? .saving : .waiting }
    var body: some View {
        content
            .opacity(presenting ? 0 : 1)
            .allowsHitTesting(!presenting)
            .accessibilityHidden(presenting)
            .frame(height:presenting ? 164 : nil)
            .clipped()
            .overlay {
                if presenting {
                    Group {
                        if reduceMotion {
                            VStack(spacing:12) {
                                VirxactMark().fill(.white).frame(width:46,height:46)
                                Text(store.ingestActive ? "已收好" : store.ingestSaving ? "正在收纳" : "松手收纳").font(.system(size:13))
                            }
                        } else {
                            TimelineView(.animation(minimumInterval:1.0/45)) { timeline in
                                IngestPortalScene(phase:phase,elapsed:store.ingestActive ? timeline.date.timeIntervalSince(store.acceptedAt) : timeline.date.timeIntervalSinceReferenceDate)
                            }
                        }
                    }
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .allowsHitTesting(false)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(store.ingestActive ? "材料已收好" : "黑洞已张开，松手收纳材料")
                }
            }
            .contentShape(Rectangle())
            .onDrop(of:[UTType.fileURL.identifier,UTType.utf8PlainText.identifier,UTType.url.identifier],isTargeted:$textTarget) {
                WorkspaceDrop.accept($0,store:store)
            }
    }
}

/// Seeded trajectories are shared by drawing and geometry checks; no random frame flicker.
enum PortalFlow {
    static func unit(_ value: Double) -> Double { value - floor(value) }
    static func point(index: Int, time: Double, tail: Double = 0, collapse: Double = 0) -> CGPoint {
        let seed = Double(index)
        let depth = unit(seed * 0.61803398875)
        let travel = unit(time * (0.23 + depth * 0.19) + seed * 0.754877666)
        let age = max(0, travel - tail)
        let radius = (22 + 147 * pow(1-age, 1.65)) * pow(max(0,1-collapse), 1.25)
        let angle = seed * 2.399963 + age * (3.8 + depth * 3.2) + time * 0.22
        return CGPoint(x: cos(angle)*radius, y: sin(angle)*radius*(0.25+depth*0.22))
    }
}

/// The island itself is the void: dust, spiral streams and a lensed mouth, without a card.
struct IngestPortalScene: View {
    var phase: IngestPhase
    var elapsed: Double
    private var receipt: Double { phase == .receipt ? IngestMotion.progress(elapsed:elapsed) : 0 }
    private var opening: Double {
        phase == .receipt ? pow(1-receipt,0.7) : 0.92 + 0.08*sin(elapsed*2.4)
    }
    var body: some View {
        let mouth = opening
        let progress = receipt
        ZStack {
            Canvas { context,size in
                let center = CGPoint(x:size.width/2,y:size.height/2)
                // Soft light is confined to the event horizon, leaving the surrounding void black.
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius:9))
                    let rect = CGRect(x:center.x-83*mouth,y:center.y-23*mouth,width:166*mouth,height:46*mouth)
                    glow.stroke(Path(ellipseIn:rect),with:.color(.white.opacity(0.40*mouth)),lineWidth:7)
                }
                // Far dust twinkles slowly; every particle keeps its own stable orbit and depth.
                for i in 0..<76 {
                    let seed = Double(i)
                    let x = (PortalFlow.unit(seed*0.618034)*2-1)*166
                    let y = (PortalFlow.unit(seed*0.414214)*2-1)*73
                    let flicker = 0.12+0.20*pow((sin(elapsed*1.7+seed)+1)/2,3)
                    let radius = i.isMultiple(of:7) ? 1.1 : 0.55
                    let rect = CGRect(x:center.x+x*mouth,y:center.y+y*mouth,width:radius*2,height:radius*2)
                    context.fill(Path(ellipseIn:rect),with:.color(.white.opacity(flicker*mouth)))
                }
                // Inward travelling ripples make the mouth appear to pull the surrounding space.
                for i in 0..<5 {
                    let wave = PortalFlow.unit(elapsed*0.38+Double(i)/5)
                    let radius = (35+115*(1-wave))*mouth
                    let rect = CGRect(x:center.x-radius,y:center.y-radius*0.39,width:radius*2,height:radius*0.78)
                    context.stroke(Path(ellipseIn:rect),with:.color(.white.opacity(sin(wave * .pi)*0.13*mouth)),lineWidth:0.7)
                }
                // Curved segmented tails accelerate into the core, with bright heads and fading wakes.
                for i in 0..<144 {
                    let depth = PortalFlow.unit(Double(i)*0.61803398875)
                    let time = elapsed * (phase == .saving ? 1.35 : 1)
                    let collapse = phase == .receipt ? progress : 0
                    let alpha = (0.26+depth*0.66)*mouth
                    for segment in 0..<7 {
                        let tail = Double(segment)*0.009
                        let p = PortalFlow.point(index:i,time:time,tail:tail,collapse:collapse)
                        let q = PortalFlow.point(index:i,time:time,tail:tail+0.009,collapse:collapse)
                        var path = Path()
                        path.move(to:CGPoint(x:center.x+p.x,y:center.y+p.y))
                        path.addLine(to:CGPoint(x:center.x+q.x,y:center.y+q.y))
                        context.stroke(path,with:.color(.white.opacity(alpha*pow(1-Double(segment)/7,1.5))),style:StrokeStyle(lineWidth:0.45+depth*0.85,lineCap:.round))
                    }
                    let head = PortalFlow.point(index:i,time:time,collapse:collapse)
                    let radius = 0.6+depth*0.8
                    context.fill(Path(ellipseIn:CGRect(x:center.x+head.x-radius,y:center.y+head.y-radius,width:radius*2,height:radius*2)),with:.color(.white.opacity(alpha)))
                }
                // Broken near orbits counter-rotate around an opaque core, giving the disc depth.
                for ring in 0..<9 {
                    var c = context
                    c.translateBy(x:center.x,y:center.y)
                    c.scaleBy(x:1,y:0.41+0.025*sin(elapsed*1.8))
                    c.rotate(by:.radians(elapsed*(ring.isMultiple(of:2) ? 0.65 : -0.42)+Double(ring)*0.7))
                    let radius = (30+Double(ring)*4.9)*mouth
                    for arc in 0..<3 {
                        var path = Path()
                        let start = Double(arc)*120+Double(ring)*9
                        path.addArc(center:.zero,radius:radius,startAngle:.degrees(start),endAngle:.degrees(start+54),clockwise:false)
                        c.stroke(path,with:.color(.white.opacity((0.90-Double(ring)*0.08)*mouth)),style:StrokeStyle(lineWidth:ring == 0 ? 2.6 : 0.8,lineCap:.round))
                    }
                }
                context.fill(Path(ellipseIn:CGRect(x:center.x-28*mouth,y:center.y-16*mouth,width:56*mouth,height:32*mouth)),with:.color(.black))
                // A small recoil ring follows successful storage; never a full-island flash.
                if phase == .receipt {
                    let pulse = sin(progress * .pi)
                    let radius = 20+progress*58
                    context.stroke(Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius*0.35,width:radius*2,height:radius*0.7)),with:.color(.white.opacity(pulse*0.6)),lineWidth:1.4*(1-progress))
                }
            }
            ZStack {
                VirxactMark().fill(.white)
                    .mask(alignment:.top) { Rectangle().frame(height:23) }
                    .offset(y:-mouth*12)
                    .rotationEffect(.degrees(-mouth*7))
                VirxactMark().fill(.white)
                    .mask(alignment:.bottom) { Rectangle().frame(height:23) }
                    .offset(y:mouth*12)
                    .rotationEffect(.degrees(mouth*7))
            }.frame(width:46,height:46)
                .shadow(color:.white.opacity(0.28*mouth),radius:5)
        }.frame(width:348,height:164).clipped()
    }
}

/// Deterministic save-phase render used by the offline visual checks.
struct IngestBlackHole: View {
    var progress: Double
    var body: some View { IngestPortalScene(phase:.receipt,elapsed:progress*IngestMotion.duration) }
}
