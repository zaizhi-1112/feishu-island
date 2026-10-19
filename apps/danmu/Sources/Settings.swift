import SwiftUI
import Combine

final class Settings: ObservableObject {
    @Published var size = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 32
    @Published var duration = UserDefaults.standard.object(forKey: "duration") as? Double ?? 14
    @Published var opacity = UserDefaults.standard.object(forKey: "opacity") as? Double ?? 1
    @Published var lanes = UserDefaults.standard.object(forKey: "lanes") as? Double ?? 4
    @Published var palette = UserDefaults.standard.object(forKey: "newPalette") as? Int ?? 3
    @Published var position = UserDefaults.standard.integer(forKey: "position")
    @Published var backdrop = UserDefaults.standard.object(forKey: "backdrop") as? Bool ?? true
    @Published var heavy = UserDefaults.standard.object(forKey: "heavy") as? Bool ?? false
    @Published var poll = UserDefaults.standard.object(forKey: "poll") as? Double ?? 1
    @Published var gray = (UserDefaults.standard.stringArray(forKey: "grayRules") ?? []).joined(separator: "，")
    @Published var hidden = (UserDefaults.standard.stringArray(forKey: "hiddenRules") ?? []).joined(separator: "，")
    @Published var status = "正在连接飞书账号…"
    @Published var latency = "尚无新消息延迟样本；快查耗时不等于送达耗时"
    @Published var counter = "真实消息 0 条 · 未读待展示 0 条"
    @Published var healthy = false
    @Published var history = ""
    @Published var paused = false
    @Published var receiving = true
    @Published var pending = 0
    func save() {
        let d = UserDefaults.standard
        for (key, value) in ["fontSize":size,"duration":duration,"opacity":opacity,"lanes":lanes,"poll":poll] { d.set(value, forKey:key) }
        d.set(palette, forKey:"newPalette"); d.set(position, forKey:"position")
        d.set(backdrop, forKey:"backdrop"); d.set(heavy, forKey:"heavy")
    }
}

private enum Dossier {
    static let paper = Color(red:0.94,green:0.91,blue:0.84)
    static let sheet = Color(red:0.975,green:0.956,blue:0.908)
    static let ink = Color(red:0.16,green:0.15,blue:0.14)
    static let muted = Color(red:0.43,green:0.40,blue:0.35)
    static let red = Color(red:0.48,green:0.13,blue:0.13)
    static let rule = Color(red:0.69,green:0.64,blue:0.55)
    static func title(_ size:CGFloat) -> Font { .custom("Songti SC",size:size).weight(.bold) }
}
private struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<2100 {
                let x = CGFloat((i * 127 + 29) % 2003) / 2003 * size.width
                let y = CGFloat((i * 193 + 17) % 1999) / 1999 * size.height
                context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:0.7,height:0.7)),with:.color(Dossier.ink.opacity(0.09)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct ArchiveButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:14,weight:.medium))
            .padding(.horizontal,16).padding(.vertical,10)
            .foregroundColor(filled ? Dossier.sheet : Dossier.ink)
            .background(filled ? Dossier.red : Dossier.sheet.opacity(0.65))
            .overlay(Rectangle().stroke(filled ? Dossier.red : Dossier.rule,lineWidth:1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct SettingsPanel: View {
    @ObservedObject var settings: Settings
    var preview: () -> Void
    var pause: () -> Void
    var listen: () -> Void
    var clear: () -> Void
    var saveRules: () -> Void
    var guide: () -> Void
    @State private var page = 0
    private var portrait: NSImage? {
        guard let url = Bundle.main.url(forResource:"dazai-dossier",withExtension:"png") else { return nil }
        return NSImage(contentsOf:url)
    }
    var body: some View {
        HStack(spacing:0) {
            cover
            VStack(alignment:.leading,spacing:0) {
                header
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        if page == 0 { appearance }
                        if page == 1 { reception }
                        if page == 2 { recent }
                    }.padding(.vertical,20).padding(.trailing,3)
                }
                footer
            }.padding(.horizontal,28).padding(.top,24).padding(.bottom,20)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(Dossier.paper.overlay(PaperGrain()))
        }.foregroundColor(Dossier.ink).background(Dossier.paper)
            .preferredColorScheme(.light).tint(Dossier.red)
    }
    var cover: some View {
        GeometryReader { geometry in
            ZStack(alignment:.top) {
                Dossier.paper
                if let image = portrait {
                    Image(nsImage:image).resizable().scaledToFill()
                        .frame(width:286,height:max(450,geometry.size.height - 195),alignment:.top).clipped()
                }
                VStack(alignment:.leading,spacing:0) {
                    Text("BUNGO STRAY DOGS").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(2.5)
                    HStack(alignment:.lastTextBaseline,spacing:8) {
                        Text("文豪野犬").font(Dossier.title(36)).tracking(3)
                        Text("通信簿").font(Dossier.title(15)).foregroundColor(Dossier.red)
                    }.padding(.top,8)
                    Rectangle().fill(Dossier.ink).frame(height:2).padding(.top,15)
                    HStack { Text("横浜 / YOKOHAMA"); Spacer(); Text("NO. 001") }
                        .font(.system(size:9,design:.monospaced)).tracking(1).padding(.top,8)
                    Spacer(minLength:20)
                    HStack(alignment:.bottom) {
                        VStack(alignment:.leading,spacing:5) {
                            Text("太宰 治").font(Dossier.title(25))
                            Text("OSAMU DAZAI").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(2)
                        }
                        Spacer()
                        Text("武装\n侦探社").font(Dossier.title(16)).multilineTextAlignment(.center)
                            .padding(8).foregroundColor(Dossier.red)
                            .overlay(Rectangle().stroke(Dossier.red,lineWidth:2)).rotationEffect(.degrees(-7))
                    }.padding(14).background(Dossier.sheet.opacity(0.94)).padding(.bottom,16)
                    VStack(spacing:7) {
                        ForEach(Array(["外观与播放","接收与过滤","最近消息"].enumerated()),id:\.offset) { index,title in
                            Button { page = index } label: {
                                HStack(spacing:12) {
                                    Text("0\(index+1)").font(.system(size:11,design:.monospaced)).opacity(0.65)
                                    Text(title).font(.system(size:15,weight:.medium))
                                    Spacer()
                                    Image(systemName:index == page ? "arrow.right" : "minus").font(.system(size:11))
                                }.padding(.horizontal,14).padding(.vertical,12)
                                    .background(page == index ? Dossier.red : Dossier.sheet.opacity(0.94))
                                    .foregroundColor(page == index ? Dossier.sheet : Dossier.ink)
                                    .overlay(Rectangle().stroke(page == index ? Dossier.red : Dossier.rule.opacity(0.6),lineWidth:1))
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button("使用说明",action:guide).buttonStyle(.plain).font(.system(size:12))
                        Spacer()
                        Text("同人主题 · 本机运行").font(.system(size:10))
                    }.foregroundColor(Dossier.muted).padding(.top,18)
                }.padding(23)
            }.overlay(alignment:.trailing) { Rectangle().fill(Dossier.rule).frame(width:1) }
        }.frame(width:286)
    }
    var header: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("武装侦探社  /  桌面通信档案").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(2).foregroundColor(Dossier.muted)
                Spacer()
                Text("FILE — 0\(page+1)").font(.system(size:11,design:.monospaced)).foregroundColor(Dossier.red)
            }
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:5) {
                    Text(["让消息，成为眼前的风景。","每一封来信，都有去处。","收件簿。 "][page]).font(Dossier.title(28))
                    Text(settings.status).font(.system(size:12)).foregroundColor(Dossier.muted).fixedSize(horizontal:false,vertical:true)
                    Text(settings.latency).font(.system(size:11)).foregroundColor(Dossier.red).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:10)
                if settings.pending > 0 {
                    Text("\(settings.pending)").font(.system(size:13,weight:.semibold))
                        .padding(7).foregroundColor(.white).background(Dossier.red).clipShape(Capsule())
                        .accessibilityLabel("未读待展示 \(settings.pending) 条")
                }
                Button(action:listen) {
                    HStack(spacing:6) {
                        Circle().fill(settings.healthy ? Color(red:0.29,green:0.38,blue:0.27) : Dossier.muted).frame(width:6,height:6)
                        Text(settings.receiving ? (settings.healthy ? "接收中" : "重试中") : "已停止")
                    }
                }.buttonStyle(ArchiveButton()).help("点击停止或重新开启账号接收")
            }
            Rectangle().fill(Dossier.ink).frame(height:2)
        }
    }
    var footer: some View {
        VStack(spacing:14) {
            Rectangle().fill(Dossier.rule).frame(height:1)
            HStack(spacing:12) {
                Text(settings.counter).font(.system(size:11,design:.monospaced)).foregroundColor(Dossier.muted)
                Spacer(minLength:8)
                Button(settings.paused ? "继续播放" : "暂停画面",action:pause).buttonStyle(ArchiveButton())
                Button(action:preview) { Label("桌面试播",systemImage:"play.fill") }.buttonStyle(ArchiveButton(filled:true))
            }
        }
    }
    func section<Content:View>(_ number:String,_ title:String,@ViewBuilder content:() -> Content) -> some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:10) {
                Text(number).font(.system(size:11,design:.monospaced)).foregroundColor(Dossier.red)
                Text(title).font(Dossier.title(19))
                Rectangle().fill(Dossier.rule.opacity(0.5)).frame(height:1)
            }
            content()
        }.padding(19).frame(maxWidth:.infinity,alignment:.leading)
            .background(Dossier.sheet.opacity(0.78))
            .overlay(Rectangle().stroke(Dossier.rule.opacity(0.65),lineWidth:1))
    }
    func slider(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,_ unit:String,step:Double = 1) -> some View {
        HStack(spacing:14) {
            Text(title).frame(width:72,alignment:.leading)
            Slider(value:value,in:range,step:step).tint(Dossier.red).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue))\(unit)").font(.system(size:13,weight:.semibold,design:.monospaced))
                .foregroundColor(Dossier.red).frame(width:60,alignment:.trailing)
        }.font(.system(size:14))
    }
    func choices<T:Hashable>(_ labels:[String],_ values:[T],_ selection:Binding<T>) -> some View {
        HStack(spacing:0) {
            ForEach(Array(labels.enumerated()),id:\.offset) { index,title in
                Button { selection.wrappedValue = values[index] } label: {
                    Text(title).font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity).padding(.vertical,8)
                        .background(selection.wrappedValue == values[index] ? Dossier.ink : Color.clear)
                        .foregroundColor(selection.wrappedValue == values[index] ? Dossier.sheet : Dossier.muted)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(selection.wrappedValue == values[index] ? "已选择" : "未选择")
            }
        }.overlay(Rectangle().stroke(Dossier.rule,lineWidth:1))
    }
    func check(_ title:String,_ value:Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing:8) {
                Image(systemName:value.wrappedValue ? "checkmark.square.fill" : "square").font(.system(size:17)).foregroundColor(Dossier.red)
                Text(title).font(.system(size:14))
            }
        }.buttonStyle(.plain).accessibilityValue(value.wrappedValue ? "已开启" : "已关闭")
    }
    var appearance: some View {
        Group {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Text("映写室 / LIVE PREVIEW").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(1.5)
                    Spacer()
                    Text("仅示例 · 不发送消息").font(.system(size:11))
                }.foregroundColor(Dossier.paper.opacity(0.65))
                ScrollView(.horizontal,showsIndicators:false) {
                    Text("同事：今天也要好好生活。")
                        .font(.system(size:settings.size,weight:settings.heavy ? .bold : .medium))
                        .foregroundColor(settings.palette == 1 ? Color(nsColor:.systemMint) : settings.palette == 2 ? Color(nsColor:.systemOrange) : .white)
                        .padding(.horizontal,14).padding(.vertical,8)
                        .background(settings.backdrop ? Color.black.opacity(0.65) : .clear).cornerRadius(8).opacity(settings.opacity)
                        .frame(minHeight:65).fixedSize(horizontal:true,vertical:false)
                }
                HStack {
                    Rectangle().fill(Dossier.paper.opacity(0.35)).frame(width:26,height:1)
                    Text("外观自动保存 · 桌面试播查看实际效果").font(.system(size:11)).foregroundColor(Dossier.paper.opacity(0.7))
                }
            }.padding(20).background(Dossier.ink)
                .overlay(Rectangle().inset(by:5).stroke(Dossier.paper.opacity(0.16),lineWidth:1))
            section("I","文字装帧") {
                slider("文字大小",$settings.size,22...52,"pt")
                HStack(spacing:16) { Text("文字配色").font(.system(size:14)).frame(width:72,alignment:.leading); choices(["缤纷","冷色","暖色","纯白"],[0,1,2,3],$settings.palette) }
                HStack { check("深色衬底",$settings.backdrop); Spacer(); check("加粗文字",$settings.heavy) }
                slider("不透明度",Binding(get:{settings.opacity*100},set:{settings.opacity=$0/100}),40...100,"%")
            }
            section("II","播放与布局") {
                slider("横穿屏幕",$settings.duration,8...26,"秒")
                slider("弹幕轨道",$settings.lanes,1...8,"条")
                HStack(spacing:16) { Text("显示区域").font(.system(size:14)).frame(width:72,alignment:.leading); choices(["顶部","中部","底部"],[0,1,2],$settings.position) }
                Text("秒数越大，移动越慢。轨道留出间距后即可接下一条。")
                    .font(.system(size:12)).foregroundColor(Dossier.muted)
            }
        }
    }
    var reception: some View {
        Group {
            section("I","接收节奏") {
                choices(["快速 · 1 秒","均衡 · 3 秒","省资源 · 6 秒"],[1.0,3.0,6.0],$settings.poll)
                Text("设置的是近期会话快查结束后的等待时间，不是送达时间保证。新消息快查与完整会话补读独立运行；原始消息直接读取，减少附加处理。上方显示真实消息的接收与排队耗时，受飞书接口和本机时钟影响。")
                    .font(.system(size:14)).foregroundColor(Dossier.muted).lineSpacing(6)
            }
            section("II","会话过滤") {
                Text("免打扰会话默认跳过；屏蔽名单优先。按会话名关键词匹配，多个用逗号分隔。")
                    .font(.system(size:14)).foregroundColor(Dossier.muted).lineSpacing(5)
                field("灰色放行名单",placeholder:"例如：兴趣交流群、资料分享群",value:$settings.gray)
                field("屏蔽名单",placeholder:"这些会话不显示弹幕",value:$settings.hidden)
                Button("保存过滤规则",action:saveRules).buttonStyle(ArchiveButton(filled:true))
            }
            section("III","保密约定") {
                Text("消息仅留在本机内存，不写入文件。跳过自己发送和已删除的消息。暂停画面仍会接收；停止后再次开启，不回放停止期间的旧消息。")
                    .font(.system(size:14)).foregroundColor(Dossier.muted).lineSpacing(6)
            }
        }
    }
    func field(_ title:String,placeholder:String,value:Binding<String>) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Text(title).font(.system(size:14,weight:.medium))
            TextField(placeholder,text:value).textFieldStyle(.plain).font(.system(size:15)).padding(11)
                .background(Dossier.paper.opacity(0.6)).overlay(Rectangle().stroke(Dossier.rule,lineWidth:1))
                .accessibilityLabel(title)
        }
    }
    var recent: some View {
        section("III","最近收件 · 100 条") {
            HStack {
                Text("仅本机内存 · 退出即消失").font(.system(size:12)).foregroundColor(Dossier.muted)
                Spacer()
                Button("清空弹幕与记录",action:clear).buttonStyle(ArchiveButton())
            }
            if settings.history.isEmpty {
                VStack(spacing:16) {
                    Image(systemName:"envelope.open").font(.system(size:40,weight:.ultraLight)).foregroundColor(Dossier.red)
                    Text("尚无新来信").font(Dossier.title(24))
                    Text("新收到的私聊与群聊，会记录在这里。").font(.system(size:14)).foregroundColor(Dossier.muted)
                }.frame(maxWidth:.infinity).padding(.vertical,65)
            } else {
                Text(settings.history).font(.system(size:16)).lineSpacing(8).textSelection(.enabled)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12)
            }
        }
    }
}
