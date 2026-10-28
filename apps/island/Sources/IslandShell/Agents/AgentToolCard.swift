import SwiftUI
import NookApp

struct AgentToolCard:View {
    @ObservedObject var store:AgentStore
    let profile:AgentProfile
    let mode:String
    let setMode:(String)->Void
    let setup:()->Void
    let open:()->Void
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering=false
    private var palette:SkinPalette {AgentSkin(agentID:profile.id).palette(dark:scheme == .dark)}
    private var accent:Color {Color(skinHex:palette.accent)}
    private var snapshot:AgentSnapshot {store.snapshots[profile.id] ?? .init()}
    private var state:AgentState {store.state(for:profile.id)}
    private var motion:Bool {store.preferences.effectsEnabled && !reduceMotion}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:10) {
                AgentPortrait(id:profile.id,size:48,motion:motion,tapFeedback:false)
                    .shadow(color:accent.opacity(0.2),radius:4,y:4)
                VStack(alignment:.leading,spacing:6) {
                    Text(profile.name).font(.system(size:15,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing:5) {
                        Circle().fill(profile.id == "deepseek" && !snapshot.metrics.isEmpty ? accent : state.color).frame(width:6,height:6)
                        Text(profile.id == "deepseek" ? (mode == "off" ? "余额读取已暂停" : snapshot.metrics.isEmpty ? "等待余额" : "余额已连接") : profile.kind=="launcher" ? "等待接入" : mode=="off" ? "任务读取已暂停":state.label)
                            .font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                Spacer(minLength:0)
                if profile.kind != "launcher" {
                    Button {store.refreshQuotas();Task{await store.poll()}} label:{Image(systemName:"arrow.clockwise").font(.system(size:12,weight:.medium)).padding(6)}
                        .buttonStyle(.plain).foregroundStyle(theme.secondaryLabel).disabled(store.refreshing)
                        .help("刷新状态和额度").accessibilityLabel("刷新"+profile.name+"状态和额度")
                }
            }
            if profile.kind=="launcher" {
                Text("入口已添加，接入后可查看任务与额度。").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                HStack {Button("设置接入",action:setup).buttonStyle(.borderedProminent);Button("打开工具",action:open).buttonStyle(.bordered)}
            } else {
                VStack(alignment:.leading,spacing:14) {
                    if snapshot.quotas.isEmpty && snapshot.metrics.isEmpty {
                        Text(profile.id == "deepseek" ? "—" : "额度未知").font(.system(size:24,weight:.semibold,design:.rounded))
                        Text(profile.id == "deepseek" ? (mode == "off" ? "连接后显示账户余额" : "等待刷新账户余额") : "此来源尚未提供额度数据").font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    }
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),alignment:.top),count:snapshot.quotas.count>1 ? 2:1),alignment:.leading,spacing:14) {
                        ForEach(snapshot.quotas) { quota in AgentToolQuota(quota:quota,accent:accent) }
                    }
                    ForEach(snapshot.metrics) { metric in
                        VStack(alignment:.leading,spacing:5) {
                            Text(metric.label).font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                            HStack(alignment:.firstTextBaseline,spacing:4) {
                                Text(metric.displayNumber).font(.system(size:25,weight:.semibold,design:.rounded)).monospacedDigit()
                                Text(metric.unit).font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                            }
                            if !metric.isFresh(now:Date().timeIntervalSince1970) {Text("上次记录 · 待刷新").font(.system(size:10)).foregroundStyle(theme.secondaryLabel)}
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                    .background(Color(skinHex:palette.well).opacity(0.8),in:RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(theme.subtleStroke.opacity(0.5)))
                HStack(spacing:3) {
                    modeButton("show","岛上显示","rectangle.topthird.inset.filled")
                    modeButton("alerts",profile.id == "deepseek" ? "仅设置页" : "仅提醒",profile.id == "deepseek" ? "rectangle" : "bell")
                    modeButton("off","不使用","minus.circle")
                }.padding(4).background(theme.subtleFill,in:RoundedRectangle(cornerRadius:11))
                if !snapshot.detail.isEmpty {
                    Text(snapshot.detail).font(.system(size:10)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
                }
                if profile.kind=="file" {Button("更改接入设置",action:setup).font(.caption)}
                if profile.id == "deepseek" { Button("打开 DeepSeek Harness") { _ = store.openAgent(profile.id) }.font(.caption) }
            }
        }
        .padding(15).frame(maxWidth:.infinity,alignment:.topLeading)
        .background(LinearGradient(colors:[Color(skinHex:palette.surface),Color(skinHex:palette.bg)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:18))
        .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(hovering ? accent.opacity(0.45):theme.subtleStroke))
        .overlay(RoundedRectangle(cornerRadius:17).strokeBorder(.white.opacity(scheme == .dark ? 0.04:0.7)).padding(2))
        .shadow(color:.black.opacity(scheme == .dark ? 0.18:0.065),radius:hovering ? 10:5,y:hovering ? 5:3)
        .offset(y:hovering && motion ? -2:0)
        .onHover{hovering=$0}.animation(motion ? .easeOut(duration:0.18):nil,value:hovering)
        .accessibilityIdentifier("agent.tool."+profile.id)
    }
    private func modeButton(_ id:String,_ name:String,_ icon:String)->some View {
        Button {setMode(id)} label:{
            VStack(spacing:5) {Image(systemName:icon).font(.system(size:12));Text(name).font(.system(size:10,weight:mode==id ? .semibold:.regular)).lineLimit(1)}
                .frame(maxWidth:.infinity).padding(.vertical,8)
                .foregroundStyle(mode==id ? accent:theme.secondaryLabel)
                .background(mode==id ? Color(skinHex:palette.surface):.clear,in:RoundedRectangle(cornerRadius:8))
                .shadow(color:.black.opacity(mode==id ? 0.07:0),radius:2,y:1)
                .contentShape(RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).accessibilityLabel(profile.name+"，"+name).accessibilityAddTraits(mode==id ? .isSelected:[])
    }
}

private struct AgentToolQuota:View {
    let quota:AgentQuota
    let accent:Color
    @Environment(\.nookResolvedTheme) private var theme
    private var fresh:Bool {quota.isFresh(now:Date().timeIntervalSince1970)}
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            Text(quota.label.components(separatedBy:" · ").last ?? quota.label).font(.system(size:11)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(quota.remainingUnits.map{AgentQuotaCompactSummary.number($0)} ?? String(format:"%.0f",quota.remainingPercent))
                    .font(.system(size:29,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(quota.remainingUnits != nil ? "积分剩余":"%剩余").font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
            }
            GeometryReader { g in
                Capsule().fill(theme.subtleFill).overlay(alignment:.leading){Capsule().fill(!fresh ? .gray : quota.remainingPercent<20 ? .orange:accent).frame(width:g.size.width*min(100,max(0,quota.remainingPercent))/100)}
            }.frame(height:6)
            if !fresh {Text("上次记录 · 待刷新").font(.system(size:10)).foregroundStyle(theme.secondaryLabel)}
            else if let reset=quota.resetsAt {Text("重置 "+Date(timeIntervalSince1970:reset).formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())).font(.system(size:10)).foregroundStyle(theme.secondaryLabel)}
            else {Text("更新于"+Date(timeIntervalSince1970:quota.updatedAt).formatted(date:.omitted,time:.shortened)).font(.system(size:10)).foregroundStyle(theme.secondaryLabel)}
        }
    }
}
