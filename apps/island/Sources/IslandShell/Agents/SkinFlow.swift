import NookApp
import SwiftUI

/// Potential flow around a cylinder plus a divergence-free curl perturbation.
/// Coordinates use the width of the surface, preserving circles on tall/short panels.
struct SkinFlowField {
    static func velocity(x: Double, y: Double, time: Double, pointer: CGPoint?) -> CGPoint {
        let a = 0.13, angle = -Double.pi / 4, c = cos(angle), s = sin(angle)
        let px = x - 0.57, py = y - 0.15
        let qx = px*c + py*s, qy = -px*s + py*c
        let r2 = max(qx*qx + qy*qy, a*a*1.02), r4 = r2*r2
        let u = 0.055 * (1 - a*a*(qx*qx-qy*qy)/r4)
        let v = -0.11*a*a*qx*qy/r4
        var vx=u*c-v*s, vy=u*s+v*c
        let radius=max(0.0001,hypot(px,py)), q=min(1,max(0,(radius/a-1.05)/0.35))
        let damping=q*q*(3-2*q), derivative=q>0 && q<1 ? 6*q*(1-q)/(a*0.35):0
        let k=11.0,sx=sin(k*x+time*0.13),sy=sin(k*y-time*0.11)
        let psi=0.006/k*sx*sy
        // Curl of the tapered stream function, including its taper derivative.
        vx += 0.006*damping*sx*cos(k*y-time*0.11)+psi*derivative*py/radius
        vy -= 0.006*damping*cos(k*x+time*0.13)*sy+psi*derivative*px/radius
        if let pointer {
            let dx=x-pointer.x, dy=y-pointer.y, d2=max(0.0025,dx*dx+dy*dy)
            let strength=0.00012*exp(-d2/0.05)
            vx += strength*(dy*dy-dx*dx)/(d2*d2)
            vy -= strength*2*dx*dy/(d2*d2)
        }
        return CGPoint(x:vx,y:vy)
    }
}
private struct FlowDot { var x:Double; var y:Double; var old:CGPoint; var life:Double; var phase:Double }
final class SkinFlowSimulation: ObservableObject {
    private var dots:[FlowDot]=[]
    private var previousTime:Double?
    private var aspect=0.0
    private var seed:UInt64=42
    private var brandPath=Path()
    private var brandImage:CGImage?
    private var brandRect=CGRect.zero
    private func random()->Double { seed=seed &* 6364136223846793005 &+ 1; return Double(seed >> 32)/Double(UInt32.max) }
    private func spawn(_ aspect:Double)->FlowDot {
        let x=random(), y=random()*aspect
        return FlowDot(x:x,y:y,old:CGPoint(x:x,y:y),life:4+random()*14,phase:random())
    }
    func draw(context:inout GraphicsContext,size:CGSize,time:Double,color:Color,strong:Bool,compact:Bool,pointer:CGPoint?,moving:Bool) {
        let ratio=Double(size.height/max(1,size.width))
        if abs(ratio-aspect)>0.03 || dots.isEmpty { aspect=ratio; dots=(0..<(compact ? 28:strong ? 210:100)).map{_ in spawn(ratio)}; previousTime=nil }
        let dt=moving ? min(0.05,max(0,time-(previousTime ?? time))) : 0
        previousTime=time
        var air=(0..<8).map { _ in Path() }
        for i in dots.indices {
            var p=dots[i];let old=CGPoint(x:p.x,y:p.y)
            let v=SkinFlowField.velocity(x:p.x,y:p.y,time:time,pointer:pointer)
            let mid=SkinFlowField.velocity(x:p.x+v.x*dt*0.5,y:p.y+v.y*dt*0.5,time:time,pointer:pointer)
            p.x += mid.x*dt;p.y += mid.y*dt;p.life -= dt
            if p.x < -0.05 || p.x>1.05 || p.y < -0.1 || p.y>ratio+0.1 || p.life<0 { p=spawn(ratio) }
            let alpha=(strong ? 0.22:0.12)*(0.5+0.5*sin(p.phase*6.28+time*0.15))
            let head=CGPoint(x:p.x*size.width,y:p.y*size.width)
            let bucket=min(7,max(0,Int(alpha/(strong ? 0.22:0.12)*7)))
            air[bucket].move(to:head)
            air[bucket].addLine(to:CGPoint(x:head.x-mid.x*size.width*(strong ? 0.32:0.12),y:head.y-mid.y*size.width*(strong ? 0.32:0.12)))
            p.old=old;dots[i]=p
        }
        for i in air.indices {
            context.stroke(air[i],with:.color(color.opacity((strong ? 0.22:0.12)*Double(i)/7)),style:StrokeStyle(lineWidth:strong ? 0.7:0.5,lineCap:.round))
        }
        if strong && !compact {
            let geometry=SkinResources.geometry
            let w=size.width*0.48,h=w/geometry.aspect
            let origin=CGPoint(x:size.width*0.46,y:max(9,size.height*0.055))
            let rect=CGRect(origin:origin,size:CGSize(width:w,height:h))
            if rect != brandRect {
                brandRect=rect
                brandPath=Path()
                for lane in SkinResources.brandLanes {
                    for (n,p) in lane.points.enumerated() {
                        let point=CGPoint(x:origin.x+p[0]*w,y:origin.y+p[1]*h)
                        if n==0 {brandPath.move(to:point)} else {brandPath.addLine(to:point)}
                    }
                }
                // Rasterize the steady long-exposure layer once per layout.
                // Only the travelling light heads need fresh paths each frame.
                let width=max(1,Int(ceil(w*2))),height=max(1,Int(ceil(h*2)))
                if let bitmap=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
                    bitmap.scaleBy(x:2,y:2);bitmap.translateBy(x:-origin.x,y:-origin.y)
                    bitmap.setStrokeColor(CGColor(gray:1,alpha:1));bitmap.setLineWidth(0.45);bitmap.setLineCap(.round)
                    bitmap.addPath(brandPath.cgPath);bitmap.strokePath();brandImage=bitmap.makeImage()
                }
            }
            if let brandImage {
                var image=context.resolve(Image(decorative:brandImage,scale:2,orientation:.up).renderingMode(.template))
                image.shading = .color(color.opacity(0.035));context.draw(image,in:rect)
            }
            var lights=(0..<8).map { _ in Path() }
            for (index,lane) in SkinResources.brandLanes.enumerated() {
                let speed=0.009*min(1.8,max(0.5,lane.speed*80))
                let distance=(time*speed+Double(index)*0.061).truncatingRemainder(dividingBy:lane.length)
                let p=lane.point(at:distance),q=lane.point(at:max(0,distance-0.008))
                let fade=min(1,min(distance,lane.length-distance)/0.006)
                let bucket=min(7,max(0,Int(fade*7)))
                lights[bucket].move(to:CGPoint(x:origin.x+q.x*w,y:origin.y+q.y*h));lights[bucket].addLine(to:CGPoint(x:origin.x+p.x*w,y:origin.y+p.y*h))
            }
            for i in lights.indices {
                context.stroke(lights[i],with:.color(color.opacity(0.24*Double(i)/7)),style:StrokeStyle(lineWidth:0.65,lineCap:.round))
            }
        }
    }
}
struct IslandSkinBackdrop: View {
    @ObservedObject var store:AgentStore
    let dark:Bool
    let compact:Bool
    let notched:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nookSurfaceAnimationActive) private var active
    @StateObject private var flow=SkinFlowSimulation()
    @State private var pointer:CGPoint?
    @State private var completionPulse=false
    var body:some View {
        let skin=store.selectedSkin,palette=skin.palette(dark:dark)
        let moving=store.preferences.effectsEnabled && !reduceMotion && active && !(compact && store.preferences.quotaDisplayEnabled)
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors:[Color(skinHex:palette.surface),Color(skinHex:palette.bg)],startPoint:.topLeading,endPoint:.bottomTrailing)
                RadialGradient(colors:[Color(skinHex:palette.glow).opacity(dark ? 0.10:0.07),.clear],center:.topTrailing,startRadius:0,endRadius:geometry.size.width*0.85)
                if skin == .claude {
                    Canvas { context,size in
                        for i in 0..<220 {
                            let x=Double((i*73+19)%997)/997*size.width,y=Double((i*127+41)%991)/991*size.height
                            context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:0.7,height:0.7)),with:.color(Color(skinHex:palette.ink).opacity(0.045)))
                        }
                    }
                }
                TimelineView(.animation(minimumInterval:1.0/30,paused:!moving)) { clock in
                    Canvas { context,size in
                        flow.draw(context:&context,size:size,time:moving ? clock.date.timeIntervalSinceReferenceDate:17,color:Color(skinHex:palette.glow),strong:skin == .virxact,compact:compact,pointer:pointer,moving:moving)
                    }
                }
                if completionPulse { Color(skinHex:palette.glow).opacity(0.08) }
                if notched { LinearGradient(colors:[.black,.clear],startPoint:.top,endPoint:.bottom).frame(height:compact ? geometry.size.height:38).frame(maxHeight:.infinity,alignment:.top) }
            }
            .onContinuousHover { phase in
                switch phase {case .active(let p):pointer=CGPoint(x:p.x/max(1,geometry.size.width),y:p.y/max(1,geometry.size.width));case .ended:pointer=nil}
            }
        }
        .overlay { if compact && store.preferences.quotaDisplayEnabled { Color.black } }
        .onChange(of:store.state) { old,new in
            if old == .working && new == .completed && moving {completionPulse=true}
        }
        .task(id:completionPulse) {
            guard completionPulse else{return};do{try await Task.sleep(for:.milliseconds(700));completionPulse=false}catch{}
        }
        .animation(moving ? .easeOut(duration:0.5):nil,value:completionPulse)
        .accessibilityHidden(true)
    }
}
