# Agent 运行与完成提醒修复 · 2026-10-30

本分支从本机 build110 对应源码 eac1e0f 独立修复，未包含另一工作区尚未提交的 build111 改动。

- 完成事件短暂合并 2 秒后提醒；其他聊天仍运行、旧任务残留或暂时缺失不会阻止已经确认完成的任务。没有完成事件仍不推断完成。
- 开始、完成与等待操作提示主动申请 6 秒灵动岛胶囊展示；保留锁屏、开关、用户操作优先级与现有屏幕动效选择。
- Codex、Claude Code 与 WorkBuddy 按每轮开始标识识别新任务，避免同一聊天连续两轮之间没采到空闲时漏掉开始提醒。
- 不改个人偏好、不读取或记录正文、不新增 Agent 权限。DeepSeek Harness 的现有接入仅提供余额，没有任务事件源，本次不虚构其开始/完成状态。

AgentChecks 已通过 758 项检查，包含 Codex / Claude Code / WorkBuddy 经 AgentStore 到 NookActivityCenter 的开始与完成提醒、compact 展示请求、去重、同聊天换轮和旧任务残留场景。读取本机 Codex 生命周期元数据可识别当前运行任务；Claude 与 WorkBuddy 的五项 hook 均指向实际安装路径。未读取或记录对话正文。被动 helper 另通过 79 项合成检查。已安装至 /Applications/一切在岛.app 并重启，包内 IslandLocalPatch 为 agent-alerts-20261030。主程序及 helper 的 SHA-256 与测试后的构建一致，深度签名校验通过；Agent 偏好 JSON 与安装前完全一致。原应用在本工作区 .build/local-backup/一切在岛-build110.app，偏好备份同目录，均只保留本机。原生顶边入口重新出现。未制造真实用户任务或截取聊天画面，三种工具的真实新任务提示和多日运行尚未逐一现场验收。正式 main 与下载发布不在本轮范围。
