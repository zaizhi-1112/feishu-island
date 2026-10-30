# 一切在岛 Windows 版：范围、做法与验收

2026-10-30 宰治要求：以当前最新 Mac 版（0.12.16 build110 + Agent 提醒补丁）为基准做完整对齐的 Windows 版安装包，并同步到 GitHub 与飞书中台下载页。本文是 Windows 版的规范；Mac 源码行为为准。

## 为什么是重写而不是打包

Mac 版是 1.7 万行 Swift/AppKit/SwiftUI，依赖 Mac 刘海区域（OpenNook）、钥匙串、LaunchAgent、WKWebView 和 macOS 通知。这些在 Windows 上不存在，只能用 Electron 按同样的规则重做。规则（消息筛选、免打扰、未读核对、保留天数、待办排序、提醒时间）逐条照搬，避免两端行为不一致。

## Windows 与 Mac 的对应关系

| Mac 版 | Windows 版 | 说明 |
| --- | --- | --- |
| 刘海灵动岛（OpenNook） | 屏幕顶部居中的悬浮胶囊窗口，悬停展开、移开收起 | 无刘海，形态改为顶部胶囊；保留四模块切换、锁定展开、5 秒新消息提示 |
| 桌面弹幕 Overlay | 全屏透明、鼠标穿透的置顶窗口 | 只有弹幕本身区域接收点击（点击停留、移开继续、打开会话） |
| WKWebView 公司登录 + /api/auth/access | Electron 持久分区窗口 + 同样的同源 POST | 只允许 island.example.invalid；令牌只在内存 |
| 官方 lark-cli（Mac） | 官方 lark-cli.exe 1.0.96 windows-amd64 | 构建时下载并按官方 checksums.txt 核对 SHA-256 |
| 钥匙串 | Electron safeStorage（DPAPI） | 中台 OAuth refresh token 等只以加密形式落盘 |
| UserDefaults / Application Support | %APPDATA%\一切在岛\ 下 JSON | 消息历史按账号哈希文件隔离 |
| LaunchAgent 登录项 | app.setLoginItemSettings | 引导中由本人选择，默认关闭 |
| 全局快捷键 / 快捷轮盘 | globalShortcut + 轮盘透明窗口 | 支持组合键；单键模式在 Windows 需系统级钩子，暂只支持组合键 |
| 屏幕提醒视频 | 全屏透明窗口播放透明视频 | 3 秒后点击或按键关闭 |
| 应用内检查更新（GitHub Release） | 同一 Release 读取 Windows 资产 | 由用户点击下载并运行安装包 |

## 分阶段

每阶段都能打出可安装的 Windows 包，并跑一遍 Node 合成测试。

1. **骨架**：主进程、顶部岛窗口（收起/展开/锁定/模块切换）、设置窗口、七步首次引导、托盘、单实例、数据目录与加密存储。
2. **飞书消息与弹幕**：公司授权连接、AccountReader 接收逻辑移植、消息解析与重要规则、会话提醒规则、本机历史保留、岛内阅读分页、桌面弹幕、打开会话（feishu:// applink）。
3. **待办与日程**：待办增删改、排序、完成历史、回收记录、到期提醒、飞书日程只读（schedule 用途）、本机移除日程。
4. **Agent**：Codex 会话状态与额度（读 %USERPROFILE%\.codex）、Claude Code（hook 写入 %USERPROFILE%\.claude\settings.json，需本人点击连接）、Claude 桌面用量、自定义 Agent 入口、运行/完成提醒（岛内与弹幕）。
5. **虚实中台**：OAuth PKCE（127.0.0.1 回调）、个人卡片、快捷轮盘与入口编辑、外观主题。
6. **提醒、外观与更新**：屏幕提醒素材、休息提醒、字号、深浅主题、皮肤、检查更新。
7. **打包与发布**：NSIS 安装包、下载页加入 Windows 入口、GitHub 开发分支与 PR、Release 资产。

## 暂不支持（需真实 Windows 环境确认后再做）

- WorkBuddy：Mac 版通过本机 Unix socket 读取，Windows 版接口未知。
- DeepSeek Harness 余额：依赖 Mac 版 Harness 的本机登录位置，Windows 位置未确认。
- Dot 隧道 / 豆包工作回传 / Codex 后台任务队列：依赖 Mac 专用 helper 与签名，未移植。
- 单键快捷轮盘、跨应用按键关闭屏幕提醒：需要系统级键盘钩子。

界面中对应入口显示「Windows 版暂不支持」，不伪装成已连接。

## 验收状态（2026-10-30）

- [x] `npm test --prefix apps/windows`：25 项合成测试通过（消息解析、规则优先级、接收器去重/未读核对/免打扰、历史保留、待办、提醒、休息、日历、Codex 会话、Claude Code 设置写入与恢复）。
- [x] `npm run pack:win`：在 macOS 交叉打出 `FeishuIsland-Setup-0.12.16-x64.exe`（131.3 MB）。包内 lark-cli.exe 与官方 checksums.txt 一致；脚本扫描未发现凭据、个人配置、消息记录或本机路径；exe 已写入图标与版本信息。
- [x] macOS 上用 Electron 实际启动（`--demo` 合成数据，含安装包内 app.asar 本体）：岛四个模块、收起状态、设置六个分区、七步引导、桌面弹幕、快捷轮盘、透明屏幕提醒共 22 张截图核对，无遮挡错位。演示模式不读取本机 Codex/Claude 数据。
- [ ] **Windows 真机安装与运行：未验证。** 包括鼠标穿透、置顶层级、全局快捷键、托盘、开机启动、DPI 缩放。
- [ ] **真实飞书消息/日历/中台授权：未验证**，需本人在 Windows 上授权后测试。
- [ ] **Claude Code 状态提醒（PowerShell 脚本）：未在 Windows 执行过**，只验证了设置文件的写入、保留与恢复。
- [ ] 未签名：首次安装会出现 SmartScreen“未知发布者”提示。
- [x] 2026-10-30 按宰治要求发布 GitHub 预发布版 [v0.12.16-windows](https://github.com/zaizhi-1112/feishu-island/releases/tag/v0.12.16-windows)（Pre-release，未设为 Latest）：安装包与 SHA256SUMS，公开下载核对 SHA-256 一致；Mac 的 Latest（build108）与 appcast 未变。
- [ ] 正式 Release 与 main 合并：需宰治、柚子分别批准同一版本。
- [x] 中台产品页：2026-10-30发布759已上线，访问范围不变；线上实际点击Windows安装包下载成功，完整SHA-256与GitHub资产一致。Mac下载仍为build111。Windows运行与真实授权仍未验收。

## 常用命令

```bash
npm install --prefix apps/windows
npm test --prefix apps/windows
npm run demo --prefix apps/windows          # 合成数据，不连真实账号
npm run pack:win --prefix apps/windows      # 下载并核对官方 CLI → 打包 → 安全扫描
```

屏幕提醒素材从 Mac 版 HEVC Alpha 转换：`swiftc -O apps/windows/scripts/convert-reminders.swift -o /tmp/convert && /tmp/convert <in.mov> <out.webm>`（仅 macOS）。
