import SwiftUI
import NookApp

enum TodoRepeatUnit:String,CaseIterable {
    case minutes, hours
    var title:String {self == .minutes ? "分钟":"小时"}
    var maximum:Int {self == .minutes ? 60:24}
    func minutes(from text:String)->Int? {
        guard let value=Int(text.trimmingCharacters(in:.whitespacesAndNewlines)),(1...maximum).contains(value) else{return nil}
        return self == .hours ? value*60:value
    }
}

struct UnifiedTodoEditor: View {
    @ObservedObject var store: WorkspaceStore
    let item: WorkItem
    let finished: () -> Void
    @State private var title=""
    @State private var details=""
    @State private var hasDeadline=false
    @State private var deadline=Date().addingTimeInterval(86400)
    @State private var mode="off"
    @State private var dates=[Date().addingTimeInterval(1200)]
    @State private var intervalText="20"
    @State private var intervalUnit=TodoRepeatUnit.minutes
    @State private var legacyInterval:Int?
    @State private var bounded=false
    @State private var end=Date().addingTimeInterval(10800)
    @State private var reminder: ScreenReminderStyle?
    @State private var completion: ScreenReminderStyle?
    @State private var initialSchedule=WorkTodoReminder()
    @State private var error=""
    @FocusState private var editing: Bool
    @Environment(\.nookResolvedTheme) private var theme
    private var schedule: WorkTodoReminder {
        WorkTodoReminder(pendingDates:mode=="off" ? []:dates,repeatMinutes:mode=="repeat" ? (legacyInterval ?? intervalUnit.minutes(from:intervalText)):nil,repeatUntil:mode=="repeat" && bounded ? end:nil)
    }
    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack {Text("编辑待办");Spacer();Text("正文可直接修改")}.font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                    TextField("待办正文",text:$title,axis:.vertical).lineLimit(3...8).textFieldStyle(.plain)
                        .font(.system(size:14)).padding(10).frame(minHeight:90,alignment:.topLeading).modifier(IslandCard(radius:9))
                        .focused($editing).accessibilityIdentifier("unified.todo.editor.title")
                    VStack(alignment:.leading,spacing:8) {
                        Text("补充说明（可选）").font(.system(size:13,weight:.medium))
                        TextField("需要记住的细节",text:$details,axis:.vertical).lineLimit(2...6).textFieldStyle(.plain)
                            .font(.system(size:14)).padding(10).modifier(IslandCard(radius:9)).focused($editing)
                            .accessibilityIdentifier("unified.todo.editor.details")
                    }
                    VStack(alignment:.leading,spacing:10) {
                        Text("提醒").font(.system(size:13,weight:.medium))
                        HStack(spacing:3) {
                            ForEach([("off","不提醒"),("times","指定时间"),("repeat","重复提醒")],id:\.0) {value,label in
                                Button {mode=value} label: {
                                    Text(label).font(.system(size:12,weight:mode==value ? .medium:.regular)).frame(maxWidth:.infinity).padding(.vertical,8)
                                        .background(mode==value ? theme.subtleFill:Color.clear,in:RoundedRectangle(cornerRadius:8))
                                        .shadow(color:mode==value ? .black.opacity(0.06):.clear,radius:3,y:1)
                                }.buttonStyle(.plain).accessibilityAddTraits(mode==value ? .isSelected:[])
                            }
                        }.padding(3).background(theme.secondaryLabel.opacity(0.09),in:RoundedRectangle(cornerRadius:10))
                        if mode != "off" {
                            ForEach(dates.indices,id:\.self) { i in
                                VStack(alignment:.leading,spacing:6) {
                                    Text(mode=="repeat" ? "首次提醒":"提醒\(i+1)").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                                    HStack(spacing:8) {
                                        TodoDateField(title:"提醒日期\(i+1)",selection:$dates[i])
                                        DatePicker("提醒时间\(i+1)",selection:$dates[i],displayedComponents:.hourAndMinute).labelsHidden().datePickerStyle(.field)
                                        if mode=="times" && dates.count>1 {Button{dates.remove(at:i)}label:{Image(systemName:"minus.circle").frame(width:24,height:28)}.buttonStyle(.plain).accessibilityLabel("移除提醒\(i+1)")}
                                    }.font(.system(size:13)).controlSize(.large)
                                }
                            }
                            if mode=="times" {Button("＋ 添加提醒时间"){dates.append(max(dates.last ?? Date(),Date()).addingTimeInterval(3600))}.buttonStyle(.plain).foregroundStyle(theme.accent).disabled(dates.count>=48)}
                            if mode=="repeat" {
                                if let legacyInterval {
                                    HStack {Text("原有间隔：每\(legacyInterval)分钟");Spacer();Button("修改间隔"){self.legacyInterval=nil;intervalUnit = .minutes;intervalText="20"}.buttonStyle(.plain).foregroundStyle(theme.accent)}
                                } else {
                                    HStack(spacing:9) {
                                        Text("每")
                                        TextField("1～\(intervalUnit.maximum)",text:$intervalText).textFieldStyle(.plain).multilineTextAlignment(.center)
                                            .font(.system(size:14)).frame(width:64).padding(.vertical,8).padding(.horizontal,8)
                                            .modifier(IslandCard(radius:8)).focused($editing)
                                            .accessibilityLabel("重复间隔数值").accessibilityIdentifier("unified.todo.editor.interval")
                                        Picker("重复间隔单位",selection:Binding(get:{intervalUnit},set:{intervalUnit=$0;intervalText="1"})) {
                                            ForEach(TodoRepeatUnit.allCases,id:\.self) {unit in Text(unit.title).tag(unit)}
                                        }.labelsHidden().pickerStyle(.menu).frame(width:92).controlSize(.large)
                                        Text("提醒")
                                        Spacer(minLength:0)
                                    }
                                    Text("可填1～\(intervalUnit.maximum)\(intervalUnit.title)").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                                }
                                Text("完成后停止提醒。").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                                Toggle("到指定时间停止",isOn:$bounded).toggleStyle(.switch)
                                if bounded {HStack {Text("停止于");TodoDateField(title:"停止日期",selection:$end);DatePicker("停止时间",selection:$end,displayedComponents:.hourAndMinute).labelsHidden().datePickerStyle(.field)}.controlSize(.large)}
                            }
                        }
                    }
                    Divider().overlay(theme.subtleStroke)
                    Toggle("完成期限",isOn:$hasDeadline).toggleStyle(.switch)
                    Text("这件事最晚何时完成，不会额外提醒。").font(.system(size:12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
                    if hasDeadline {HStack {Text("最晚完成");TodoDateField(title:"完成日期",selection:$deadline);DatePicker("完成时间",selection:$deadline,displayedComponents:.hourAndMinute).labelsHidden().datePickerStyle(.field)}.controlSize(.large)}
                    if mode != "off" {Divider().overlay(theme.subtleStroke);ScreenReminderChoice(store:store,selection:$reminder).controlSize(.large)}
                }.font(.system(size:13)).padding(14).modifier(IslandCard(radius:14)).padding(14)
            }.scrollBounceBehavior(.basedOnSize).frame(maxWidth:.infinity,maxHeight:.infinity)
                .accessibilityIdentifier("unified.todo.editor.scroll")
            VStack(alignment:.leading,spacing:8) {
                if !error.isEmpty {Text(error).font(.system(size:12)).foregroundStyle(theme.warning).fixedSize(horizontal:false,vertical:true)}
                HStack(spacing:10) {
                    Spacer()
                    Button(action:finished) {Text("取消").frame(minWidth:34).padding(.horizontal,12).padding(.vertical,8).modifier(IslandCard(radius:9))}
                        .keyboardShortcut(.cancelAction)
                    Button(action:save) {Text("保存").frame(minWidth:34).padding(.horizontal,12).padding(.vertical,8).foregroundStyle(theme.subtleFill).background(theme.accent,in:RoundedRectangle(cornerRadius:9))}
                        .keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("unified.todo.editor.save")
                }.font(.system(size:13,weight:.medium)).buttonStyle(.plain)
            }.padding(.horizontal,14).padding(.vertical,10).overlay(alignment:.top){Rectangle().fill(theme.subtleStroke).frame(height:1)}
        }.foregroundStyle(theme.primaryLabel).nookKeepsExpanded(whileFocused:$editing)
        .onChange(of:mode) {_,v in if v=="repeat" {dates=Array(dates.prefix(1))}}
        .onAppear {
            title=item.title;details=item.input==item.title ? "":item.input
            hasDeadline=item.deadline != nil;deadline=item.deadline ?? deadline
            reminder=item.screenReminder;completion=item.completionReminder
            if let due=item.due,!item.reminded {
                mode="times";dates=[due]
                if let plan=item.todoReminder {
                    if !plan.pendingDates.isEmpty {dates=plan.pendingDates}
                    if let repeatMinutes=plan.repeatMinutes {
                        mode="repeat";dates=Array(dates.prefix(1))
                        if repeatMinutes%60==0,(1...24).contains(repeatMinutes/60) {intervalUnit = .hours;intervalText=String(repeatMinutes/60)}
                        else if (1...60).contains(repeatMinutes) {intervalUnit = .minutes;intervalText=String(repeatMinutes)}
                        else {legacyInterval=repeatMinutes}
                    }
                    if let stop=plan.repeatUntil {bounded=true;end=stop}
                }
            }
            initialSchedule=schedule
        }
    }
    private func save() {
        do {
            if mode=="repeat",legacyInterval==nil,intervalUnit.minutes(from:intervalText)==nil {
                throw WorkError.message("请输入1～\(intervalUnit.maximum)的整数\(intervalUnit.title)。")
            }
            guard try store.configureTodoReminder(item.id,dates:schedule.pendingDates,repeatMinutes:schedule.repeatMinutes,
                repeatUntil:schedule.repeatUntil,style:reminder,completionStyle:completion,
                title:title,details:details,deadline:.some(hasDeadline ? deadline:nil),
                preserveReminderSchedule:schedule==initialSchedule) else{throw WorkError.message(store.error)}
            finished()
        } catch{self.error=error.localizedDescription}
    }
}
