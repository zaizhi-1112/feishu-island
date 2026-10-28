import AppKit
import SwiftUI
import WebKit

struct CompanyAuthorizationView: View {
    @ObservedObject var connection: CompanyConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: IslandBrandAssets.appIcon).resizable().scaledToFit().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接自己的飞书").font(.system(size: 21, weight: .semibold))
                    Text("一切在岛").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            if connection.authorizationPageReady {
                GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 10) {
                            step("1", "登录公司账号", complete: true)
                            step("2", "确认飞书授权", complete: connection.authorizationGranted)
                            step("3", "Mac确认连接", complete: connection.authorizationConnected)
                        }
                        Picker("连接用途", selection: $connection.authorizationPurpose) {
                            Text("消息接收").tag(CompanyConnection.Purpose.receive)
                            Text("待办日历").tag(CompanyConnection.Purpose.calendar)
                        }.pickerStyle(.segmented).disabled(connection.authorizationBusy)
                            .onChange(of: connection.authorizationPurpose) { _, _ in Task { await connection.refreshAuthorizationStatus() } }
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: connection.authorizationConnected || connection.authorizationGranted ? "checkmark.circle.fill" : "paperplane.circle.fill")
                                .font(.system(size: 38)).foregroundStyle(connection.authorizationGranted ? Color.green : .accentColor)
                            Text(connection.authorizationConnected ? "已连接，可以使用了" : connection.authorizationGranted ? "飞书授权已完成" : "确认后，让飞书与小岛连接")
                                .font(.system(size: 21, weight: .semibold))
                            Text(connection.authorizationPurpose == .calendar
                                 ? "读取主日历，创建或更新你主动选择同步的待办。不删除日程、不邀请参会人。"
                                 : "读取本人会话与新消息，按你的规则提醒。不发送消息，也不修改已读状态。")
                                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Divider()
                            Text(connection.authorizationFeedback).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("company.authorization.feedback")
                            if connection.authorizationBusy {
                                HStack { ProgressView().controlSize(.small); Text("等待你在飞书确认…").font(.system(size: 12)).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 10) {
                                    Button("重新打开飞书授权页") { connection.reopenAuthorization() }
                                    HStack {
                                        Button(connection.authorizationChecking ? "检查中…" : "检查授权结果") { connection.checkAuthorizationProgress() }
                                            .disabled(connection.authorizationChecking)
                                        Button("取消本次授权") { connection.cancelAuthorization() }
                                    }
                                }.buttonStyle(.bordered)
                            } else if connection.authorizationConnected {
                                Button("返回设置") { connection.returnToSettings() }.buttonStyle(.borderedProminent).controlSize(.large)
                            } else {
                                Button(connection.authorizationGranted ? "重新核对连接" : "授权并前往飞书") {
                                    if connection.authorizationGranted { connection.continueDesktopConnection() }
                                    else { connection.beginAuthorization() }
                                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!connection.authorizationConfigured)
                                Button("重新检查授权状态") { Task { await connection.refreshAuthorizationStatus() } }.buttonStyle(.link)
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                            Text("授权、Mac连接和消息接收分别显示。接收开关可以在设置中单独关闭。")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(width: max(0, geometry.size.width - 48), alignment: .leading).padding(24)
                }
                }
            } else if let error = connection.loginError {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("暂时无法连接").font(.system(size: 20, weight: .semibold))
                    Text(error).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("重新打开登录页") { connection.reloadLoginPage() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else if let web = connection.web {
                Text("先完成公司账号登录，随后会自动进入授权步骤。")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 14)
                CompanyLoginWebView(web: web)
            } else {
                ProgressView("正在准备连接…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 480, minHeight: 540)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private func step(_ number: String, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 7) {
            Text(complete ? "✓" : number).font(.system(size: 11, weight: .semibold))
                .frame(width: 23, height: 23).background(complete ? Color.green.opacity(0.12) : Color.primary.opacity(0.06), in: Circle())
                .foregroundStyle(complete ? .green : .secondary)
            Text(title).font(.system(size: 11, weight: .medium))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompanyLoginWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
