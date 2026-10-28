import SwiftUI
import NookApp

/// Account management shows people and actions; local profile names remain an
/// implementation detail. New connections use the app's hosted authorization.
struct FeishuMessageConnectionSheet: View {
    @ObservedObject var store: FeishuStore
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.canResumeSavedConnection ? "飞书账号" : "连接飞书").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { completed(); dismiss() }.buttonStyle(.plain)
            }
            Label(store.canResumeSavedConnection ? store.account : "连接自己的飞书", systemImage: "person.crop.circle")
                .font(.system(size: 17, weight: .medium))
            Text("在飞书确认授权后，自动开始接收新消息。只读取会话和消息。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let hint = store.connectionHint { Text(hint).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 16) {
                Button(store.canResumeSavedConnection ? "重新授权" : "连接飞书") {
                    dismiss(); store.openMessageConnection()
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!store.allowsDirectoryLookup).accessibilityIdentifier("unified.feishu.authorize")
                if store.canResumeSavedConnection {
                    Button("更换账号") { dismiss(); store.requestCompanyAccountSwitch() }.buttonStyle(.link)
                }
            }
        }.padding(28).frame(width: 440)
    }
}
