import NookApp
import SwiftUI
import UniformTypeIdentifiers

/// Save-confirmation timing stays independent of the native drag session.
enum IngestMotion {
    static let duration: Double = 0.85
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

/// The island's own black surface is the void. No card, border, fake document or thumbnail.
struct IngestPortalScene: View {
    var phase: IngestPhase
    var elapsed: Double
    private var receipt: Double { phase == .receipt ? IngestMotion.progress(elapsed:elapsed) : 0 }
    private var opening: Double {
        phase == .receipt ? pow(1-receipt,0.7) : 0.88 + 0.12*sin(elapsed*2.4)
    }
    var body: some View {
        let mouth = opening
        ZStack {
            Canvas { context,size in
                let center = CGPoint(x:size.width/2,y:size.height/2)
                // Horizontal accretion disc: alternating brilliant and absent segments.
                for ring in 0..<8 {
                    var c = context
                    c.translateBy(x:center.x,y:center.y)
                    c.rotate(by:.radians(-0.10))
                    c.scaleBy(x:1,y:0.30 + mouth*0.28)
                    c.rotate(by:.radians(elapsed * (ring.isMultiple(of:2) ? 0.85 : -0.65) + Double(ring)*0.7))
                    let r = (33 + Double(ring)*7.5) * (0.45+mouth*0.55)
                    for arc in 0..<3 {
                        var path = Path()
                        let start = Double(arc)*120+Double(ring)*9
                        path.addArc(center:.zero,radius:r,startAngle:.degrees(start),endAngle:.degrees(start+72),clockwise:false)
                        c.stroke(path,with:.color(.white.opacity((0.96-Double(ring)*0.10)*mouth)),style:StrokeStyle(lineWidth:ring == 0 ? 3.5 : 1.5,lineCap:.round))
                    }
                }
                // Streams point into the mouth; no facsimile of the file being dragged.
                for i in 0..<28 {
                    let cycle = (elapsed*0.48+Double(i)/28).truncatingRemainder(dividingBy:1)
                    let angle = Double(i)*2.399+elapsed*0.35
                    let r = (40+(1-cycle)*108)*mouth
                    let point = CGPoint(x:center.x+cos(angle)*r,y:center.y+sin(angle)*r*0.45)
                    let end = CGPoint(x:center.x+cos(angle)*(r+5+cycle*8),y:center.y+sin(angle)*(r+5+cycle*8)*0.45)
                    var trail = Path(); trail.move(to:point); trail.addLine(to:end)
                    context.stroke(trail,with:.color(.white.opacity((0.1+cycle*0.5)*mouth)),lineWidth:0.7)
                }
                context.fill(Path(ellipseIn:CGRect(x:center.x-43*mouth,y:center.y-28*mouth,width:86*mouth,height:56*mouth)),with:.color(.black))
            }
            // Two halves of the real brand mark open like jaws, then close into the logo.
            ZStack {
                VirxactMark().fill(.white)
                    .mask(alignment:.top) { Rectangle().frame(height:23) }
                    .offset(y:-mouth*9)
                VirxactMark().fill(.white)
                    .mask(alignment:.bottom) { Rectangle().frame(height:23) }
                    .offset(y:mouth*9)
            }.frame(width:46,height:46)
        }.frame(width:348,height:164).clipped()
    }
}

/// Deterministic save-phase render used by the offline visual checks.
struct IngestBlackHole: View {
    var progress: Double
    var body: some View { IngestPortalScene(phase:.receipt,elapsed:progress*IngestMotion.duration) }
}
