# 主对话完成后再提醒 · build118 · 2026-11-06

用户反馈 Codex 侧栏仍在加载时，多次弹出“本轮工作已结束”。本轮只读核对生命周期元数据：对应主对话的最新事件仍为 `task_started`，8 个直属子任务中最近一小时出现了 4 次完成事件。旧 `CodexReader` 将每个 rollout 都当作独立用户对话，子任务完成因此触发误报；没有读取或记录对话正文用于诊断。

本轮修正：

- 在读取生命周期前核对 rollout 的 `session_meta`，排除 `source.subagent`、父线程或子 Agent 路径明确标识的内部任务。长于 4 MiB 的文件也先读真实文件头，子任务继承的父对话历史不能产生提醒；内部任务不占最多 80 个主对话的发现名额。
- 用主对话 ID 合并同一聊天的多份 rollout，最新的运行轮次覆盖旧完成状态。用户自己创建的分叉聊天仍独立监测。
- 只有主对话匹配当前轮次的 `task_complete` 才产生完成事件；工具步骤结束、中断或等待输入均不视为完成。完成事件按对话和轮次去重，再核对最新状态；同一对话继续时撤销候选提醒，其他独立对话运行不会阻止已经完成的对话提醒。
- 岛内提示和冲屏队列保留对应的完成身份。排队、解锁恢复和显示期间都会核对；对话继续运行时丢弃待发提醒或关闭正在显示的旧完成提醒。普通待办和休息冲屏沿用原规则。
- 随包 HTML 已纠正旧的“全部会话结束并稳定 20 秒”文案。当前版本为 0.12.24 build118，保留 build117 的弹幕关闭和冲屏倒计时。

验证入口：

```sh
cd apps/island
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 AgentChecks --skin-preview
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks --skin-preview
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 FusionChecks --skin-preview --screen-reminder-check
```

800 项 Agent 检查已通过。新增检查覆盖 85 个内部子任务不会挤掉主对话、不同层级元数据、超过 4 MiB 的长对话、同一聊天多份 rollout、子任务/工具结束保持运行、主轮结束只计一次、同一聊天继续后撤销提醒、排队及正在显示的冲屏失效、解锁后不回放失效完成提醒。使用隔离偏好、合成文件与不上屏的原生窗口。

514 项产品合成检查和 48 项离屏冲屏断言也已通过。随包说明在桌面实际截图核对完成；390px 窄屏的 23px 字号、完整文案和无横向溢出已通过页面回读检查，窄屏截图捕获超时，未计作视觉验收。

生产构建和深度签名通过，最终候选在本 worktree 的 `.build/agent118-candidate/一切在岛.app`。相对 build117 仅主程序、Info.plist、随包说明及签名四个文件变化，没有增删文件；三个连接组件逐字节相同。公开源码继续使用占位地址，本机私有生产副本沿用三个未改连接源文件。

按本人本轮既有安装授权，正常退出 build117 并备份，经 Finder 移走旧 App，将 build118 安装到原 `/Applications/一切在岛.app` 并重新打开。旧应用与私有状态备份位于 `.build/local-install-backups/agent118-20261106/`，状态权限 0700/0600。安装文件逐项匹配候选；工作区、快捷配置和 15 个设置域启动前一致。启动后待办、历史、排序、配方、卡片、提醒字段及偏好保持，只见日历 `lastSync` 正常更新，观察到三个不同的官方 CLI 后台请求进程。没有读取或导出钥匙串凭据。

本机安装回执在 `.build/installation118/`；只包含聚合结果的生命周期核对在 `.build/agent118/lifecycle-audit.json`，日志在 `apps/island/.build/agent118-*.log`。这些本机证据、备份、截图与个人状态不上传。源码同步现有开发分支和 PR #17，未发布新 Release、更新中台或合并 main。真实长对话自然结束后的冲屏仍需随本人正常使用观察，未通过发送任务或强制终止主对话制造验收。

# Agent 运行与完成提醒修复 · 2026-10-30（历史）

本分支从本机 build110 对应源码 eac1e0f 独立修复，未包含另一工作区尚未提交的 build111 改动。

- 完成事件短暂合并 2 秒后提醒；其他聊天仍运行、旧任务残留或暂时缺失不会阻止已经确认完成的任务。没有完成事件仍不推断完成。
- 开始、完成与等待操作提示主动申请 6 秒灵动岛胶囊展示；保留锁屏、开关、用户操作优先级与现有屏幕动效选择。
- Codex、Claude Code 与 WorkBuddy 按每轮开始标识识别新任务，避免同一聊天连续两轮之间没采到空闲时漏掉开始提醒。
- 不改个人偏好、不读取或记录正文、不新增 Agent 权限。DeepSeek Harness 的现有接入仅提供余额，没有任务事件源，本次不虚构其开始/完成状态。

AgentChecks 已通过 758 项检查，包含 Codex / Claude Code / WorkBuddy 经 AgentStore 到 NookActivityCenter 的开始与完成提醒、compact 展示请求、去重、同聊天换轮和旧任务残留场景。读取本机 Codex 生命周期元数据可识别当前运行任务；Claude 与 WorkBuddy 的五项 hook 均指向实际安装路径。未读取或记录对话正文。被动 helper 另通过 79 项合成检查。已安装至 /Applications/一切在岛.app 并重启，包内 IslandLocalPatch 为 agent-alerts-20261030。主程序及 helper 的 SHA-256 与测试后的构建一致，深度签名校验通过；Agent 偏好 JSON 与安装前完全一致。原应用在本工作区 .build/local-backup/一切在岛-build110.app，偏好备份同目录，均只保留本机。原生顶边入口重新出现。未制造真实用户任务或截取聊天画面，三种工具的真实新任务提示和多日运行尚未逐一现场验收。正式 main 与下载发布不在本轮范围。
