import SwiftUI

struct TodoRecordDetail:View {
    let title:String
    let content:String
    var completedAt:Date?
    var receipt:WorkArchiveReceipt?
    let close:()->Void
    @Environment(\.nookResolvedTheme) private var theme
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {Text("记录详情").font(.system(size:20,weight:.semibold));Spacer();Button("关闭",action:close).buttonStyle(TodoSettingsLinkStyle())}
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text(title).font(.system(size:17,weight:.medium))
                    if let completedAt {Text("已完成 · "+completedAt.formatted(date:.abbreviated,time:.shortened)).font(.system(size:13)).foregroundStyle(theme.secondaryLabel)}
                    if !content.isEmpty,content != title {Text(content).font(.system(size:14)).lineSpacing(5)}
                    if let receipt {
                        Divider()
                        Text("旧归档记录").font(.system(size:16,weight:.semibold))
                        Text(receipt.error.isEmpty ? "原回执保留，当前版本不会自动继续远程写入。" : receipt.error)
                        Text("操作编号："+receipt.operation.uuidString)
                        if let intent=receipt.intent {Text("待核对操作："+intent)}
                        if !receipt.target.url.isEmpty {Text("原目标："+receipt.target.url)}
                        if let document=receipt.document {Text("文档："+document)}
                        if let record=receipt.record {Text("记录："+record)}
                        Text("请先在飞书核对原文档或记录。这里保留回执，不会清空或重新提交。")
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(24).frame(width:520,height:440).foregroundStyle(theme.primaryLabel).background(theme.subtleFill)
    }
}
