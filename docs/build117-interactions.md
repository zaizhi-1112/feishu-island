# build117：弹幕左上角关闭与冲屏倒计时

2026-11-06，基于 build116 修正当前弹幕关闭和冲屏控件，版本为 0.12.23 build117。用户反馈长弹幕右下角的 × 出现太晚，关闭需要重复点击；冲屏按钮小、难辨认，也不知道何时结束。

## 行为与原因

- 弹幕 × 固定在左上角的 30×30pt 区域。增加 40pt 顶部空间，正文不与按钮重叠；进入屏幕后前 38pt 即可看到整个按钮。鼠标移入仍暂停、移开继续。
- 移动的非激活窗口在第一次鼠标按下时直接关闭，不等松开后再判断鼠标位置。冲屏的本地事件监听关闭提醒后继续传递鼠标事件，避免吞掉点向其他岛内控件的第一下；键盘关闭保持原行为。
- 冲屏底部使用深色面板、白色大字和高对比按钮，动作高度 52pt、字号 20pt。休息提醒保留开始休息、稍后提醒与跳过三个动作；窄屏改为竖排。视频区域避开底部控件。
- 倒计时使用单调时钟，按视频和设置共同决定的实际自动关闭时刻更新，显示“剩余秒数 + 秒后自动关闭”。关闭、锁屏、换下一条时撤销旧计时器并清理状态，不显示负数。
- 关闭仅影响当前展示和对应待播状态，不删除会话、岛内原文或飞书已读状态。接收、授权与过滤逻辑沿用 build116。

## 验证

```sh
cd apps/island
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks --skin-preview --button-interactions-only
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks --skin-preview --screen-controls-only --render-screen-controls .build/screen-controls
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks --skin-preview
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 FusionChecks --skin-preview --screen-reminder-check
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks --skin-preview --queue-timer-review
```

- 56 项交互检查通过，其中包含 29 项冲屏控件检查。覆盖左上角边缘命中、第一次按下直接关闭、禁用按钮、重复关闭、冲屏结束后同一次点击交给目标弹幕、宽窄布局、按钮文字完整、倒计时视频时长/边界/锁屏/排队/清理。
- 514 项完整产品合成检查、48 项离屏冲屏断言通过；三条实际计时器驱动的合成冲屏按顺序交接并自动关闭。
- 独立原生移动弹幕只点一次 ×，记录手动关闭一次、完成回调一次、剩余面板零，关闭时 x=744.09pt，排除自然飘完。测试窗口消失后回读原生回调，没有再点第二次。
- 原生 12 秒冲屏观察到 12 至 4 的连续秒数更新，约 9 秒时因普通输入提前关闭，不能把该轮当作自然归零通过。自动到期由前述三条实际定时试播验证，全部秒数边界由合成时钟检查覆盖。
- 深浅弹幕、宽屏三动作、窄屏竖排、单关闭动作的原生渲染均已查看。随包单文件 HTML 在 1366px/正文 21px 与 390px/正文 23px 检查，无横向溢出，目录与字号按钮可用。
- 生产构建与深度签名通过；仅主程序、Info.plist、随包说明和对应签名四个文件相对 build116 改变，无增删，连接组件逐字节一致。公开源码保持占位地址；本机私有生产副本保留既有连接源文件。

所有 UI 检查使用隔离的 skin-preview 和合成内容，不读取账号、真实任务或聊天，不截图真实消息。测试日志、图片与状态回调保留在被忽略的 `.build/native117/`、`apps/island/.build/`，不上传。可复验入口为 `ButtonInteractionReview.swift` 与 `ScreenControlsLiveReview.swift`，后者需显式指定 `--skin-preview --interactive --screen-controls-review /absolute/output`。

## 本机安装与保留

沿用本人本轮“允许安装并验证”的明确授权，正常退出 build116 后备份，经 Finder 移走旧 App，将最终候选安装到原 `/Applications/一切在岛.app` 并重新打开。安装文件逐项匹配 `.build/interaction117-final/一切在岛.app`，签名通过。

旧应用与本机状态位于 `.build/local-install-backups/interactions117-20261106/`，私有状态权限 0700/0600。工作区和快捷配置在启动前与备份一致；15 个设置域仅 `SULastCheckTime` 更新检查时间变化。启动后两条待办、回收、完成历史、排序、配方、卡片及提醒字段保持一致，仅日历 `lastSync` 和 Agent `notifiedQuotaCycles` 等运行状态更新。观察到三次不同的官方 CLI 后台请求进程，确认接收循环已恢复；未检查真实消息正文。安装核对回执在 `.build/installation117/`。

本轮未新建登录项、读取或导出钥匙串凭据、发布 GitHub Release、修改中台或合并 main。正式下载继续为 build115；源码同步现有开发分支和 PR #17。跨应用物理鼠标的全部路径、真实新消息和长期运行未完整覆盖。
