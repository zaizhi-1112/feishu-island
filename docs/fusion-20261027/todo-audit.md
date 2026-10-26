# 待办融合审计与实现取舍

日期：2026-10-27。源码检查依据为本轮用户提供的宰治 build50 与佑哥 0.9.2 ZIP；包内 README 只作历史说明，不作为授权或实测证据。

## 检查结论

两份源码均使用 Swift 5.9、SwiftUI/AppKit、Swift Package Manager 和本地 Vendor/OpenNook，最低 macOS 15，无需再引入 Electron。佑哥入口为 Sources/YuIsland/main.swift，LSUIElement=true，主栏四模块、原生独立设置窗口、四套皮肤可复用。当前协作分支保留宰治更成熟的 OAuth、账号读取、Agent适配及透明提醒播放器。

佑哥待办的 TodoStore 使用模块目录中的 todos.json 原子保存任务、完成时间、已送达提醒标记及附件副本；完成排序与折叠可用。但归档满30天会在启动或定时检查时永久删除记录及附件，与本轮“长期历史”冲突，不能直接沿用。它的 TodoPanel 仍有待处理/暂存/冲屏三层切换，材料处理会启动AI；这些不带入新版待办入口。

佑哥 ScreenReminderPresenter 会激活应用并创建可成为键盘窗口的全屏面板，另铺0.12黑色遮罩；本轮保留宰治透明、鼠标穿透、不抢焦点的 ScreenReminderPresenter。素材管理归外观模块，待办仅选择素材和触发时间。

佑哥设置窗口 IslandSettingsWindow 使用单个980×740 AppKit窗口托管SwiftUI，纵向设置布局适合融合；原六类设置与“材质/快捷键/展开方式”卡片需精简。SettingsServer.open已转原生，但start仍启动HTTP服务，不应因为复用设置视觉保留无用服务器。

佑哥 AgentPreferences 固定只接受三个内置Agent，不支持任意自定义；其Claude只有历史额度，WorkBuddy适配比宰治旧。应复用佑哥Agent面板视觉，保留宰治适配并扩展配置。中台已有主栏隐藏偏好，选卡仍是checkbox，需改switch。首次飞书连接只有已有lark-cli授权，不能当成新安装OAuth已实现。

## 当前待办实现

- 唯一数据源仍为 WorkspaceStore.disk.items / workspace.json，没有新增并行待办库。旧材料、结果、附件、项目和授权数据不删除。
- UnifiedTodoPanel 与 UnifiedTodoSettings 提供单层纵向任务、已完成折叠、生活提醒、按日期历史；不含Agent派任务或材料文件输入。TodoModule使用同一Store，并在自己的模块范围提供轻提示。
- WorkItem可选增加completedAt、todoReminder、completionReminder及导入来源。WorkDisk可选增加todoHistory和importedTodoSources，旧JSON可直接解码。
- 完成时间与不可变完成事件同一次原子保存；重复完成不重复记账或冲屏。重新打开任务保留上次完成事件，归档只改变当前列表位置。原版本完成时间未知的任务明确记为unknown，绝不补造日期。
- 任务可设单次、多个时间、周期及周期结束时间。消费提醒先落盘后显示，睡眠/重启错过多个时间只合并一次；完成与归档不再触发。生活提醒支持轻提示或统一冲屏素材。每条提醒二选一，不再转发Agent/弹幕；素材失败退为一次轻提示并报错，锁屏暂停显示。
- 原TodoStore的30天清理入口变为无操作；原始归档与附件长期保留。启动只读导入已知旧待办目录，按来源幂等，原文件不改；附件复制进入既有Workspace文件目录。
- 提供schema_version=1的todoHistorySnapshot()、exportTodoHistory(to:)。导出是用户主动选择位置的JSON，保留内容、完成状态、完成时间、时间是否已知、来源和归档状态，文件0600。可由主程序额外绑定明确授权的只读接口。
- WorkspaceStore.tick不再自动启动旧云端归档或处理Dot派单，仅保留提醒与中台刷新。无新自动AI任务。

## 验证入口

`FusionChecks --unified-todo-check`：纯合成存储，覆盖重启、多次/周期提醒去重、睡眠跨越补一次、完成冲屏去重、十年历史保留、恢复/重新完成、原有字段兼容、来源幂等导入、原文件不变、导出权限、隐藏原生视图渲染。

旧`TodoChecks`保留逻辑检查并将过期删除断言改为长期保留断言。第一轮统一debug构建与57条专项断言已通过；随后加入设置无嵌套滚动、输入焦点保持、轻提示/冲屏二选一、锁屏与失败回退检查，最终结果由统一构建与交付记录补充。真实新消息、系统睡眠、真人鼠标操作及多日运行不由合成检查替代。
