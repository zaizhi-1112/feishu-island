# 双源码检查与飞书模块融合记录

检查日期：2026-10-27。此文件记录开发前读取到的源码事实，以及本轮飞书模块的取舍；正式交付验收以同目录的最终检查结果为准。没有在检查阶段执行 ZIP 内的脚本，也没有连接真实账号。包内历史授权/说明只作为资料，不作为本轮行动授权。

## 源包完整性与开发基座

- 宰治：`宰治.zip`，22,475,253 字节，ZIP 595 项，展开 27,451,290 字节，CRC 检查通过。SHA-256：`9ac14a2ea0b2f668c86ef06f14267a0cb986b76a43f081b7e65119d400dafba4`。
- 佑哥：`佑哥.zip`，11,312,928 字节，ZIP 272 项，展开 14,553,698 字节，CRC 检查通过。SHA-256：`d407f6ec9d8a0e570d5b6a6a91792a5d9e4466ff110efd2c69e303e7fccf15ca`。
- 解压前逐项检查路径不会逃逸目标目录，并拒绝符号链接项。两个包均解压到工作区 `.build/fusion-import-20261027/`，未覆盖正式源码。
- 宰治包内根目录为 `你的飞包-build50-源码`。共 502 个普通文件，逐文件 SHA-256 对照本仓库开发前的 `ad79178`：500 个完全一致、0 个不同；另 2 个为打包说明 `先读我.html` 和 `源码校验清单.json`。
- 因此继续使用现有 `feishu-island-integration-075` / `codex/integrate-youzi-075` 作为唯一可维护主线。没有把同一版本另复制为第二套产品。
- 佑哥包内根目录为 `柚子岛-0.9.2-源码`。对照显示两者共同使用 OpenNook，但 Host、Vendor 悬浮实现、设置窗口、待办/提醒、中台及 Agent 展示存在独立变化；不能用整目录覆盖替代逐模块整合。

## 两套代码的技术与运行结构

| 项目 | 宰治 build50 | 佑哥 0.9.2 |
|---|---|---|
| 技术栈 | Swift Package 5.9，SwiftUI + AppKit，目标 macOS 15+ | 相同 |
| 程序入口 | `apps/island/Sources/YuIsland/main.swift` → `NookApp.main(IslandHost.configuration())` | 包内 `Sources/YuIsland/main.swift` → 同一宿主模式 |
| 窗口/刘海外壳 | 本地 `Vendor/OpenNook`，屏幕刘海几何、edgeDocked、compact/expanded、穿透窗口 | 同一上游，另有悬浮收纳与自定义面板补丁 |
| 模块入口 | `FeishuModule`、`AgentModule`、`WorkspaceModule`；中台在旧 Workspace 内 | `FeishuModule`、`AgentModule`、`TodoModule`、`PlatformModule` 四个并列模块 |
| 桌面设置 | `WorkspaceWindow.swift` 原生 NSWindow；消息设置旧版通过内嵌 WKWebView 载入 loopback 页面 | `Settings/IslandSettingsWindow.swift` 原生 NSWindow + SwiftUI 侧栏/纵向内容，`IslandSkinStudio.swift` 皮肤配置 |
| Dock | `Resources/Info.plist` 的 `LSUIElement=true`，原生 accessory 模式 | 相同 |
| 原生依赖 | AppKit、SwiftUI、Foundation、Combine、Network、WebKit、AVFoundation 等系统框架；唯一 Swift 包依赖是本地 OpenNook | 相同类型的系统框架和本地 OpenNook |
| 外部组件 | 官方 lark-cli、独立签名中台授权 helper；旧版另有 Agent/任务/隧道等 helper | lark-cli 路径接收；包内中台 helper 二进制和来源说明 |
| 构建 | `apps/island/scripts/build.sh` 支持独立输出路径与 scratch，避免覆盖运行中的 App | `scripts/build.sh` 原版默认写 dist，SDK 默认指向开发者的 26.5 路径；不能原样当作此机环境 |

宰治包还包含历史 `apps/danmu` 下的 Swift 原版、Electron Desktop、Node Web 和协作面板。这些是历史/独立运行入口，不是当前融合 Mac 安装包的第二个接收器。此次不得将它们同时启动。

## 持久化、系统权限和依赖边界

**宰治版本**

- `FeishuStore.swift`：启停、规则、已关注 ID、静音、外观与连接配置在模块 UserDefaults。消息、正文、页码、去重状态在内存。
- `CompanyConnection.swift`：官方公司接收通道由专属 WKWebsiteDataStore 承载本人登录；服务器管理 OAuth 刷新凭据，客户端只缓存短期访问凭据到内存，并验证应用 ID、范围和稳定用户 ID。不读取其他浏览器 cookies，不把密钥随 App 分发。
- `WorkspaceCore.swift`：旧任务、材料、结果、提醒在 `Application Support/FeishuIsland/Workspace` 的原子 JSON 与本机附件目录，目录 0700、文件 0600。旧任务派发、归档、Dot 等是本轮要退出主产品运行面的功能，不能仅隐藏按钮但继续运行任务服务。
- `Agents/AgentStore.swift`：监控偏好持久化，状态/额度来自各自适配器，不要求所有来源有同样字段。旧 `AgentPreferences` 只接受固定三个来源；自定义来源与“最多展示三个”的语义需要本轮调整。
- `Workspace/ScreenReminder.swift`：已有本机素材、循环调度、透明且不抢焦点的提醒渲染，可供统一素材库复用。
- 中台的独立 helper 持有本应用自身 Keychain 服务。保持其稳定签名字节，不能重新签名其他 helper 或代替用户处理系统权限。
- 旧 WorkBuddy 签到 helper 含 AX 权限流程；这属于可选旧功能，飞书接收、待办、普通灵动岛与设置窗口本身不依赖它，也没有必要向新版默认申请屏幕录制/辅助功能。

**佑哥版本**

- `TodoStore.swift`：原子 `todos.json` 位于按 bundle/module 区分的 Application Support；已具有 `completedAt`、`archivedAt`，但 `archiveExpiresAt` 和 `purgeExpiredArchives()` 会在 30 天后清理归档。此行为与本轮“长期历史”直接冲突，不能照搬。
- `Reminders/ScreenReminderStore.swift`：`reminders.json` 保存素材和循环提醒；具有到期、错过与恢复状态。可参考调度/界面，但最终只保留一套素材与提醒数据源。
- `Platform/PlatformStore.swift` 与 `IslandLayout.swift`：提供中台主栏显示及启动模块偏好；可直接参考其四模块并列导航与主栏开关思想。
- `Agents/AgentModel.swift` 同样限制固定三种内置来源，因此不能仅换成佑哥面板就称支持自定义多个 Agent。
- `Resources/Integrations/SOURCE.md` 标明 helper 的源文件和 SHA-256，并区分二进制与账号凭据；包内 helper 不是可复制他人授权的凭据。本次应沿用主线自身稳定构建缓存。
- 两包的 OpenNook 许可证、来源及补丁说明必须随产品保留；提醒素材和皮肤来源说明保留。本次本地整合不推导新的公开再分发授权。

## 开发前识别的关键缺口

1. 宰治 `FeishuModule` 用 `receivingDefault: false`，没有首次安装自动拉起授权；已有 `CompanyConnection.prepare/activate/credential` 足以复用，不应另建账号系统。
2. 旧消息设置把联系人/群聊/关注/屏蔽分成多个区域，且公司接收权限不含联系人目录搜索。统一管理应直接用已经授权的 `im +chat-list --types=p2p,group`，按稳定 chat ID 操作，不追加通讯录权限。
3. `AppearanceMCP` 有字号、配色、圆角；`Overlay` 有 duration，但上层没有独立速度配置。气泡底色也被 `DanmuPlayback` 固定关闭，需要贯通到真正渲染器。
4. 宰治的 `IntegrationTopBar` 为刘海加过顶部留白，外壳还计算 notch cutout；佑哥另有浮层布局。必须在主线统一几何与切换，避免把两份补偿同时叠加。
5. 佑哥待办的 30 天删除策略、两套任务/材料存储、旧 Agent composer 和旧 Dot 服务，与新版轻量产品定位不兼容；需要明确退出运行面，同时保存旧数据，不做破坏性删除。
6. 宰治现有主线和 ZIP 一致，保留其接收器/授权/渲染器能减少已有校时、分页、去重、未读检查和句柄关闭修复的回退风险。

## 本轮飞书模块实际取舍与接口

- 保留宰治 `AccountReader`、`ServerClock`、`FeishuTransport`、`CompanyConnection` 的只读接收核心；不改权限范围、不修改已读、不写消息正文日志。
- 新增 `Settings/UnifiedFeishuSettings.swift`。采用佑哥原生纵向设置思路，一页完成连接、默认规则、会话管理、弹幕外观；宿主统一设置窗口提供滚动，不再依赖浏览器设置页。
- `FeishuStore.active` 供统一原生窗口绑定同一个接收实例。`beginAutomaticConnectionIfNeeded()` 只在真实运行、新安装且没有保存的启停/连接偏好时给出一次授权引导。已有暂停偏好继续保留；已有启用状态在启动时恢复。恢复时如果明确提示登录过期，会打开一次本人连接窗口；普通网络异常不反复弹登录，完成授权后由原接收器恢复。
- `CompanyConnection.prepareReceive()` 复用同一个独立授权窗口。用户取消后不激活；授权过程中若规则/账号配置变化，不用过期准备结果覆盖；窗口关闭或十分钟期限结束后留在可重试状态。
- `FeishuCustomRules.conversations` 用同一 chat ID 表达私聊和群聊。旧关注迁移为每条提醒，旧屏蔽迁移静音，静音优先；老规则名称可在刷新列表后匹配最新名称。阅读页不再提供“关注”按钮。
- `FeishuDirectory.conversations()` 使用既有聊天列表权限，合并私聊/群聊/话题群、检查分页、去重、错误 ID。不会读取正文，不申请联系人目录权限。
- 新样式字段 `speed` 为 40–240 点/秒，`bubble` 为纯文字/墨色/浅色/自选。字号、颜色、速度和气泡贯通原生 `Overlay`；新增样式沿用白名单与 4.5 对比度检查。
- 预览仅在设置页面的 96 点高裁切区域播放合成文本，最长 12 秒，支持减少动态效果；不会发送消息，也不创建桌面遮罩。
- `FeishuModule` 与阅读活动去掉材料投放层，避免新版消息页继续接受 AI 材料。
- 普通消息去重、静音、锁屏与未读校验仍由同一个接收/播放实例负责；完整长文继续在灵动岛阅读，桌面弹幕仅显示短消息。

## 检查与验收边界

`Tests/UnifiedFeishuChecks/main.swift` 提供隔离合成检查：首次引导策略、旧规则迁移、静音优先、重启恢复、重复事件、渲染参数、低对比度与非法字段拒绝、统一会话分页，以及隐藏原生设置窗口的宽度检查。主线统一 Debug 编译通过；独立审查补充“登录过期恢复提示”和“导入配色必须按已校验背景渲染”回归后，39 条专项断言实际通过。命令：`CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift run --disable-sandbox --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.4.sdk -j 2 UnifiedFeishuChecks`；输出为 `PASS: 39 unified Feishu assertions; no account calls or visible windows`。

本次不以合成测试冒充本人或同事的首次 OAuth、真实飞书新消息、所有私聊/群聊类别或多日运行验收。安装包签名/架构/最低系统版本以及最终 UI 点验由主线统一构建验收记录确认。
