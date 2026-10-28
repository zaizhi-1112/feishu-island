import SwiftUI
import NookApp

/// Uses the skin gallery's real character artwork; selection only changes the primary Agent.
struct AgentPrimaryChoice:View {
    let profile:AgentProfile
    let selected:Bool
    let motion:Bool
    let select:()->Void
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering=false
    private var dark:Bool {scheme == .dark}
    private var palette:SkinPalette {AgentSkin(agentID:profile.id).palette(dark:dark)}
    private var accent:Color {Color(skinHex:palette.accent)}
    private var animate:Bool {motion && !reduceMotion}
    var body:some View {
        Button(action:select) {
            VStack(spacing:0) {
                ZStack {
                    LinearGradient(colors:[Color(skinHex:palette.well),Color(skinHex:palette.surface)],startPoint:.topLeading,endPoint:.bottomTrailing)
                    Ellipse().fill(accent.opacity(dark ? 0.16:0.10)).frame(width:76,height:13).blur(radius:5).offset(y:33)
                    if ["codex","claude","workbuddy"].contains(profile.id) {
                        AgentPortrait(id:profile.id,size:72,motion:animate,tapFeedback:false)
                            .shadow(color:accent.opacity(0.17),radius:5,y:5)
                            .offset(y:hovering && animate ? -3:0)
                    } else { AgentIdentityIcon(id:profile.id,size:54) }
                }
                .frame(height:106).clipShape(RoundedRectangle(cornerRadius:12))
                .overlay(alignment:.topTrailing) {
                    Image(systemName:selected ? "checkmark.circle.fill":"circle")
                        .font(.system(size:16,weight:.semibold))
                        .foregroundStyle(selected ? accent:theme.tertiaryLabel.opacity(0.5))
                        .padding(9)
                }
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(profile.name).font(.system(size:13,weight:.semibold)).lineLimit(1)
                        Text(selected ? "当前主用":"点击切换").font(.system(size:11)).foregroundStyle(selected ? accent:theme.secondaryLabel)
                    }
                    Spacer(minLength:2)
                }.padding(.horizontal,7).padding(.vertical,12)
            }
            .padding(7).frame(maxWidth:.infinity)
            .background(LinearGradient(colors:[Color(skinHex:palette.surface),Color(skinHex:palette.bg)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(selected ? accent.opacity(0.75):hovering ? accent.opacity(0.40):theme.subtleStroke,lineWidth:selected ? 1.5:1))
            .overlay(RoundedRectangle(cornerRadius:17).strokeBorder(.white.opacity(dark ? 0.04:0.65),lineWidth:1).padding(2))
            .shadow(color:.black.opacity(dark ? 0.20:hovering ? 0.10:0.055),radius:hovering ? 10:5,x:0,y:hovering ? 6:3)
            .offset(y:hovering && animate ? -2:0)
            .contentShape(RoundedRectangle(cornerRadius:18))
        }
        .buttonStyle(AgentPrimaryPressStyle(animate:animate))
        .foregroundStyle(theme.primaryLabel)
        .onHover{hovering=$0}
        .animation(animate ? .spring(response:0.26,dampingFraction:0.82):nil,value:hovering)
        .animation(animate ? .easeOut(duration:0.18):nil,value:selected)
        .accessibilityLabel(profile.name+(selected ? "，当前主用":"，设为主用"))
        .accessibilityAddTraits(selected ? .isSelected:[])
        .accessibilityIdentifier("agent.primary.\(profile.id)")
    }
}
private struct AgentPrimaryPressStyle:ButtonStyle {
    let animate:Bool
    func makeBody(configuration:Configuration)->some View {
        configuration.label.scaleEffect(configuration.isPressed && animate ? 0.975:1)
            .opacity(configuration.isPressed ? 0.92:1)
            .animation(animate ? .easeOut(duration:0.12):nil,value:configuration.isPressed)
    }
}
