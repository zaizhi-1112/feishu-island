import AppKit
import NookApp
import SwiftUI
@testable import IslandShell

struct WorkBuddyCheckinSettings:View {
    @ObservedObject var store=WorkBuddyCheckinStore.shared
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Toggle("每天自动领取 WorkBuddy 免费积分",isOn:Binding(get:{store.enabled},set:{store.setEnabled($0)})).accessibilityIdentifier("workbuddy.daily.enabled")
            Text("每天9:10用本机WorkBuddy已登录账号领取。一切在岛运行即可，无需Codex；睡眠或退出期间不执行，下次运行补查。每位同事自行开启和授权。").font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(WorkBuddyCheckinSchedule.message(store.state)).font(.system(size:13)).accessibilityIdentifier("workbuddy.daily.state")
            HStack{
                Button("检查今日积分"){store.check()}.disabled(!store.enabled || store.busy)
                if store.state=="permission_required" {
                    Button("允许签到组件控制WorkBuddy"){store.authorize()}
                    Button("打开辅助功能设置"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
                }
            }
            Text("仅操作Buddy加油站免费领取并核对“今日已领”；不购买、不操作聊天。只保存日期、账号显示名摘要和领取状态，不保存凭据。无法确认时停止重复点击。").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(16).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
}
