import AppKit
import CoreImage.CIFilterBuiltins
import NookApp
import SwiftUI

struct FeishuMessageConnectionSheet: View {
    @ObservedObject var store: FeishuStore
    @ObservedObject var service: LocalFeishuService = .shared
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nookResolvedTheme) private var theme
    @State private var accountsExpanded = false
    @State private var ownsFlow = false
    @State private var succeeded = false
    private var qr: NSImage? {
        guard let url = service.authorizationURL else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 144, height: 144))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.canResumeSavedConnection ? "管理飞书账号" : "连接飞书").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭账号连接")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(store.connection.localAccount?.userName ?? "连接自己的飞书账号", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                    Text("在飞书官方页面确认授权。只读取会话与消息，不发送消息，不修改已读状态。").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    if service.purpose != .receive && service.busy {
                        Text("正在处理\(service.purpose.title)的连接，请完成后再连接消息。").foregroundStyle(theme.warning)
                    } else {
                        if !store.canResumeSavedConnection || accountsExpanded || service.selected.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("选择本机账号", selection: $service.selected) {
                                    Text("请选择自己的账号配置").tag("")
                                    ForEach(service.profiles) { Text($0.label).tag($0.id) }
                                }.disabled(service.busy)
                                if service.profiles.isEmpty && !service.busy {
                                    Text("这台Mac还没有可用配置，需要先完成首次配置。公司限制创建应用时，请联系管理员。").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                                }
                                HStack {
                                    Button("刷新账号列表") { Task { await service.refresh() } }
                                    Button("首次配置…") { ownsFlow = true; service.configure() }
                                }.disabled(service.busy || !store.allowsDirectoryLookup)
                            }.padding(16).modifier(FeishuSettingsSurface())
                        } else {
                            Button("选择其他本机账号…") { accountsExpanded = true }.buttonStyle(.link).disabled(service.busy)
                        }
                        Text("已有提醒规则会保留；更换账号时会先请你确认。").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Divider()
                        HStack(alignment: .top, spacing: 10) {
                            if service.busy { ProgressView().controlSize(.small) }
                            Text(service.feedback).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("unified.feishu.authorizationFeedback")
                        }
                        if let url = service.authorizationURL {
                            HStack(spacing: 18) {
                                if let qr { Image(nsImage: qr).interpolation(.none).frame(width: 144, height: 144).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 8)) }
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("用飞书扫码授权").font(.system(size: 15, weight: .semibold))
                                    Link("在浏览器中打开授权页", destination: url)
                                    Text("授权完成后会自动检查连接。").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                                }
                            }
                        }
                    }
                }.padding(.vertical, 2)
            }
            HStack(spacing: 12) {
                Button(service.busy && ownsFlow ? "取消授权" : "关闭") { close() }.controlSize(.large)
                Spacer()
                if !service.busy {
                    Button("使用已有授权") { ownsFlow = true; service.connectMessages(store: store, authorize: false) }
                        .disabled(service.selected.isEmpty || service.purpose != .receive || !store.allowsDirectoryLookup)
                    Button(store.canResumeSavedConnection ? "重新授权并连接" : "授权并连接飞书") { ownsFlow = true; service.connectMessages(store: store, authorize: true) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(service.selected.isEmpty || service.purpose != .receive || !store.allowsDirectoryLookup)
                        .accessibilityIdentifier("unified.feishu.authorize")
                }
            }
        }.padding(26).frame(width: 540, height: 570).foregroundStyle(theme.primaryLabel)
            .background(theme.subtleFill).tint(theme.accent)
            .task {
                guard !service.busy, store.allowsDirectoryLookup else { return }
                service.purpose = .receive
                if store.canResumeSavedConnection { service.selected = store.connection.profile }
                await service.refresh()
            }
            .onChange(of: service.messageConnectionRevision) { _, _ in if ownsFlow { succeeded = true; completed(); dismiss() } }
            .onDisappear { if ownsFlow && !succeeded && service.busy { service.cancel() } }
    }
    private func close() { if ownsFlow && service.busy { service.cancel() }; dismiss() }
}
