import SwiftUI

@MainActor struct HubShortcutSettings: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var launcher: UnifiedPlatformStore
    @State private var editing: HubPingDestination?
    @State private var search = ""
    @State private var group = "全部"
    @State private var target: Int?
    @State private var customTitle = ""
    @State private var customAddress = ""
    static let directions = ["↑ 上", "↗ 右上", "→ 右", "↘ 右下", "↓ 下", "↙ 左下", "← 左", "↖ 左上"]
    private var choices: [HubShortcutChoice] { HubShortcutChoice.catalog(cards:workspace.hub.cards,applications:workspace.hub.applications ?? []) }
    private var visible: [HubShortcutChoice] {
        choices.filter { (group == "全部" || $0.group == group) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    private var destinations: [HubPingDestination] { launcher.destinations(cards:workspace.hub.cards,selectedIDs:workspace.disk.selectedCards,applications:workspace.hub.applications ?? []) }
    var body: some View {
        IslandSettingsCard("快捷轮盘") {
            HStack {
                HubShortcutRecorder(store: launcher)
                Spacer()
                Button("试开轮盘") { HubPingLauncher.shared.show() }.buttonStyle(IslandButtonStyle())
                    .help("滑出目标方向的外圈打开，也可直接点击。按住快捷键时，选好方向后松开即可打开。")
            }
            Text("把右边的入口拖到左边；拖动左边两行可交换位置。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 6) {
                    ForEach(destinations) { destination in slot(destination) }
                }.frame(width: 218)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    TextField("搜索入口或应用", text: $search).textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("入口分类", selection: $group) {
                            ForEach(["全部", "常用应用", "中台入口", "本机", "全部应用", "我的卡片"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                        Button { Task { await workspace.refreshHub() } } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(workspace.hubBusy).accessibilityLabel("刷新常用应用")
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 8)], spacing: 8) {
                            ForEach(visible) { choice in
                                Label(choice.title, systemImage: choice.symbol)
                                    .font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading)
                                    .padding(.horizontal, 10).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(RoundedRectangle(cornerRadius: 8)).draggable(choice.id)
                                    .contextMenu {
                                        ForEach(0..<8, id: \.self) { index in
                                            Button("放到" + Self.directions[index]) { _ = launcher.setSlot(index, choice.shortcut) }
                                        }
                                    }
                                    .accessibilityLabel(choice.title + "，可拖到左边或右键选择位置")
                            }
                        }
                        if visible.isEmpty { Text("没有匹配的入口").foregroundStyle(.secondary).padding() }
                    }.frame(height: 310)
                    if let error = workspace.hub.applicationsError {
                        Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                    } else if !workspace.hub.connected {
                        Text("连接中台后会显示你首页的常用应用。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity)
            }
            HStack {
                TextField("自定义名称", text: $customTitle).frame(width: 125)
                TextField("https://…", text: $customAddress)
                Menu("添加到…") {
                    ForEach(0..<8, id: \.self) { index in
                        Button(Self.directions[index]) {
                            if launcher.setSlot(index, .init(source:.custom,title:customTitle.trimmingCharacters(in:.whitespacesAndNewlines),address:customAddress.trimmingCharacters(in:.whitespacesAndNewlines))) {
                                customTitle = ""; customAddress = ""
                            }
                        }
                    }
                }.fixedSize()
            }.textFieldStyle(.roundedBorder)
            Toggle("打开入口时播放信号音效", isOn: Binding(get:{launcher.preferences.soundEnabled},set:{ _ = launcher.setSound($0) }))
            if !launcher.error.isEmpty { Text(launcher.error).font(.system(size: 12)).foregroundStyle(.orange) }
        }.accessibilityIdentifier("platform.shortcutBoard")
        .sheet(item: $editing) { destination in
            HubShortcutEditor(store: launcher, index: destination.id, destination: destination)
        }
    }
    private func slot(_ destination: HubPingDestination) -> some View {
        HStack(spacing: 8) {
            Text(Self.directions[destination.id]).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            Button { editing = destination } label: {
                if let image = HubShortcutIcon.image(destination.iconPNG) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24)
                } else { Image(systemName: "square.and.pencil").frame(width: 24, height: 24) }
            }.buttonStyle(.plain).help("编辑名称、网址与图标")
                .accessibilityLabel("编辑" + Self.directions[destination.id] + "入口与图标")
            Text(destination.title).font(.system(size: 13, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("编辑入口与图标…") { editing = destination }
                Divider()
                ForEach(choices) { choice in Button(choice.title) { _ = launcher.setSlot(destination.id, choice.shortcut) } }
                Divider()
                Button("使用这个方向的默认入口") { _ = launcher.setSlot(destination.id, .init()) }
                Button("留空") { _ = launcher.setSlot(destination.id, .init(source:.empty)) }
            } label: { Image(systemName:"chevron.down") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
                .accessibilityLabel("更换" + Self.directions[destination.id] + "的入口")
        }.padding(.horizontal, 10).frame(height: 40)
            .background(target == destination.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(target == destination.id ? Color.accentColor : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 8)).draggable("slot:\(destination.id)")
            .dropDestination(for: String.self) { values, _ in
                guard values.count == 1, let value = values.first else { return false }
                if value.hasPrefix("slot:"), let source = Int(value.dropFirst(5)) { return launcher.swapSlots(source, destination.id) }
                guard let choice = choices.first(where: { $0.id == value }) else { return false }
                return launcher.setSlot(destination.id, choice.shortcut)
            } isTargeted: { active in target = active ? destination.id : nil }
    }
}
