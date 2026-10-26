# build51 融合验证记录

2026-10-27。阅读版为同目录 `使用说明.html`；本文件保留开发复现信息。

## 自动检查

- Debug 全目标编译通过；Release 使用 macOS 26.4 SDK、Swift 6.3.1 编译，最低部署目标 macOS 15。
- FusionChecks：1,149 条。涵盖消息去重与未读校验、待办原子保存、完成历史、旧数据迁移、一次/多次/周期提醒、锁屏与重复提醒，以及保留代码的兼容回归。旧 Dot/归档回归只是兼容检查，正式产品不启用这些入口。
- AgentChecks：703 条。含最多三位展示、独立监测、实际积分 metrics、来源隔离、极端时间值、锁屏与单来源暂停。
- UnifiedFeishuChecks：49 条。含首次连接决策、坏配置保留、统一会话迁移、切换账号时规则隔离。
- IslandChecks：104 条；NavigationChecks --skin-preview：49 条；TodoChecks：85 条；PlatformChecks：57 条。
- UnifiedProductChecks：30 条，包含 12 条真实排队转换的移出、取消与被新任务替代回归；这些测试没有创建窗口。
- UnifiedProductChecks --skin-preview --render：五页面分别在 1020×760 和 840×620 隐藏窗口渲染；20 条视口/不上屏检查通过。新增悬浮取消断言前的这次渲染总数为38，不将它与后来的30重复相加。
- Python package-pilot-test.py：12 项，含12个必需主题资源逐项缺失拒绝的子检查。

## 原生界面点验

使用独立 `local.feibao.fusion-review` 测试身份与合成数据。未读取真实聊天，未打开账号授权。

- 五个独立设置页面均能切换。
- 原生系统粘贴后添加任务；完成后移动到底部；仅折叠其中一项，另一项保持可见；展开已完成区并归档，历史显示日期及原文。
- Agent 隐藏后监测开关仍保留；排序后首尾按钮状态随顺序变化。
- 两种鼠标移入模式可切换；深色模式实际生效；纵向滚动可到达外观页底部。
- 关闭中台主栏显示后，其连接、轮盘八槽和卡片配置仍留在设置中。
- 已检查常规/最小窗口宽度与亮/暗主题的实际原生渲染。截图均为合成内容。
- 初次测试夹具未安装系统 Edit 菜单，系统粘贴没有生效；夹具与正式 AppCoordinator 对齐安装同一 NookEditMenu 后，实际粘贴成功。这不是通过改文字绕过验收。

## 安装包边界

按项目正式 `scripts/build.sh` 生成新路径的应用。运行时仅允许 lark-cli、feishu-hub-helper、agent-status-helper；LOLPing 素材许可、主题与冲屏素材及离线说明随包。没有浏览器扩展、Dot 隧道、签到 helper、个人凭据或本机材料。

DMG 的最终哈希、只读挂载比对与签名结果另见随包 `package-manifest.json`。安装包使用本地签名，未进行 Developer ID 签名或 Apple 公证；仅验证 Apple 芯片架构。

最终 Release 隔离副本（只改测试 Bundle ID 后重新本地签名）已完成20项原生启动检查：四个入口切换、五个原生设置页面、收起/展开、首击接收，以及模拟屏幕变化/唤醒通知后的窗口重建全部通过。没有实际热插拔或让电脑睡眠。

DMG 已通过镜像完整性、只读挂载、文件哈希逐项一致、主程序及三个 helper 的签名/arm64 架构检查，并已卸载验证卷。SHA-256：`897700646ff0ae9ab4ed4d659f915c3425e6e31ec3e62ffb269864d0df3b986d`。

## 不冒充已验收的部分

后续安装：本人明确要求替换后，已正常退出 build50 及其4个主/子组件，备份旧程序、Workspace/Platform和相关偏好，在原路径安装并启动build51。安装后确认同Bundle仅1个主进程，旧隧道不再运行，旧启动软链接保留；原3条任务的标题、正文、结果、状态、附件及项目字段完整保留，完成历史3条。中台授权helper字节保持一致。安装未替代真实新消息、额度与多日验证。

真实首次飞书 OAuth、授权过期/切换账号、不同账号的真实消息与 Agent 额度、物理鼠标连续悬停手感、实际显示器热插拔、睡眠唤醒与多日运行仍需真实使用证据。未部署公司网页，未合并 main。

## 复现命令

在 `apps/island` 执行：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache" \
  swift build --disable-sandbox -j 2 --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.4.sdk
.build/debug/FusionChecks
.build/debug/AgentChecks
.build/debug/UnifiedFeishuChecks
.build/debug/IslandChecks
.build/debug/TodoChecks
.build/debug/NavigationChecks --skin-preview
.build/debug/PlatformChecks
.build/debug/UnifiedProductChecks
python3 Tests/package-pilot-test.py
```

媒体、粘贴板与窗口测试需要正常 macOS 桌面会话；受限沙盒不提供这些系统服务，不能把该环境失败当作功能通过。不要把需要人工点击并常驻的 CompactClickChecks 当作自动退出的批量测试。
