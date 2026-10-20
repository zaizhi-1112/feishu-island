import SwiftUI

/// A save receipt, never a processing indicator. Elapsed time survives view replacement.
enum IngestMotion {
    static let duration: Double = 1.65
    static func progress(elapsed: Double) -> Double { min(1,max(0,elapsed / duration)) }
    static func fileRadius(_ p: Double) -> Double { 79 * pow(max(0,1 - min(1,max(0,p))/0.77),1.15) }
}

struct WorkspaceIngestFeedback: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if store.ingestActive {
            Group {
                if reduceMotion {
                    Label("材料已收好 · 仅存本机",systemImage:"checkmark.circle.fill")
                        .font(.system(size:13,weight:.medium)).padding(18)
                } else {
                    TimelineView(.animation(minimumInterval:1.0/45)) { timeline in
                        IngestBlackHole(progress:IngestMotion.progress(elapsed:timeline.date.timeIntervalSince(store.acceptedAt)))
                    }
                }
            }
            .background(.black.opacity(0.97),in:RoundedRectangle(cornerRadius:18))
            .overlay { RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.24),lineWidth:0.5) }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("材料已收好，仅保存在本机")
        }
    }
}

/// Entire visual is bounded to the island. No separate window, event capture or desktop mask.
struct IngestBlackHole: View {
    var progress: Double
    var body: some View {
        let p = min(1,max(0,progress))
        let envelope = min(1,p/0.10) * min(1,(1-p)/0.18)
        let radius = IngestMotion.fileRadius(p)
        let angle = -0.65 + p * 9.5
        VStack(spacing:0) {
            ZStack {
                Canvas { context,size in
                    let center = CGPoint(x:size.width/2,y:size.height/2)
                    let growth = 0.45 + 0.55 * min(1,p/0.18)
                    // Black gaps between white arcs give the official mark's virtual/real rhythm.
                    for ring in 0..<6 {
                        var c = context
                        c.translateBy(x:center.x,y:center.y)
                        c.rotate(by:.radians(-0.16))
                        c.scaleBy(x:1,y:0.40 + Double(ring)*0.025)
                        c.rotate(by:.radians(p * (ring.isMultiple(of:2) ? 7 : -5) + Double(ring)*0.9))
                        let r = (25 + Double(ring)*5.8) * growth
                        let rect = CGRect(x:-r,y:-r,width:r*2,height:r*2)
                        c.stroke(Path(ellipseIn:rect),with:.color(.white.opacity(0.055 * envelope)),lineWidth:3)
                        for arc in 0..<3 {
                            var path = Path()
                            let start = Double(arc)*120 + Double(ring)*11
                            path.addArc(center:.zero,radius:r,startAngle:.degrees(start),endAngle:.degrees(start+58),clockwise:false)
                            c.stroke(path,with:.color(.white.opacity((0.92-Double(ring)*0.105)*envelope)),style:StrokeStyle(lineWidth:ring == 0 ? 2.3 : 1.2,lineCap:.round))
                        }
                    }
                    // Inward particle paths; fixed seed and bounded count, no random frame jitter.
                    for i in 0..<18 {
                        let phase = (p * 1.35 + Double(i)/18).truncatingRemainder(dividingBy:1)
                        let a = Double(i)*2.399 + p*4.2
                        let r = (26 + (1-phase)*58) * growth
                        let x = center.x + cos(a)*r
                        let y = center.y + sin(a)*r*0.39
                        context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:1.3,height:1.3)),with:.color(.white.opacity((0.25+0.6*phase)*envelope)))
                    }
                    context.fill(Path(ellipseIn:CGRect(x:center.x-22,y:center.y-16,width:44,height:32)),with:.color(.black))
                }.frame(width:228,height:78)
                VirxactMark().fill(.white).frame(width:25,height:25)
                    .rotationEffect(.degrees(-sin(p*Double.pi)*90))
                    .scaleEffect(0.94 + 0.06*cos(p*Double.pi*2))
                if p < 0.79 {
                    Image(systemName:"doc.fill").font(.system(size:21,weight:.medium)).foregroundStyle(.white)
                        .scaleEffect(max(0.01,1-pow(p/0.79,1.7)))
                        .rotationEffect(.degrees(p*590))
                        .offset(x:cos(angle)*radius,y:sin(angle)*radius*0.44)
                        .opacity(min(1,(0.79-p)/0.14))
                }
            }.frame(width:228,height:78).clipped()
            Text(p < 0.77 ? "正在收纳" : "已收好 · 仅存本机")
                .font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.8))
                .frame(height:22)
        }.padding(.horizontal,6).padding(.vertical,5)
            .frame(width:240,height:110).clipped()
    }
}
