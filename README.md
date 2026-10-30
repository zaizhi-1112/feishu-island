<p align="center"><img src="apps/island/Distribution/site/icon.png" alt="一切在岛" width="88"></p>

<h1 align="center">一切在岛 · Feishu Island</h1>
<p align="center">把飞书消息、Agent 状态和待办，收进屏幕顶部。</p>
<p align="center"><a href="#下载">下载安装</a> · <a href="#功能">功能</a> · <a href="#开发">开发</a> · <a href="CONTRIBUTING.md">参与贡献</a> · <a href="https://github.com/zaizhi-1112/feishu-island/issues">反馈问题</a></p>

macOS 原生工作岛，以及正在测试的 Windows 版本。飞书消息与桌面弹幕、待办日程、Agent 状态和快捷入口，在一个小窗口里查看。

## 下载

| 平台 | 版本 | 安装包 | 当前状态 |
| --- | --- | --- | --- |
| macOS 15+ · Apple 芯片 | **0.12.17 · build111** | [下载 Mac 版 DMG](https://github.com/zaizhi-1112/feishu-island/releases/download/v0.12.17-build111/feishu-island-0.12.17-build111-arm64.dmg) · [发布说明](https://github.com/zaizhi-1112/feishu-island/releases/tag/v0.12.17-build111) | 已发布，尚未 Apple 公证 |
| Windows 10/11 · x64 | **0.12.16 · 测试版** | [下载 Windows 安装包](https://github.com/zaizhi-1112/feishu-island/releases/download/v0.12.16-windows/FeishuIsland-Setup-0.12.16-x64.exe) · [发布说明](https://github.com/zaizhi-1112/feishu-island/releases/tag/v0.12.16-windows) | Pre-release，未签名，尚未 Windows 真机验收 |

[全部版本](https://github.com/zaizhi-1112/feishu-island/releases) · [公司产品页](https://feishu-island.virxact.net)（需要公司登录）

Windows 使用独立版本号，目前未完整对齐 Mac build111。GitHub 的 Latest 当前指向 Mac 正式发布包；Windows 请使用上表入口。

## 开始使用

**Mac：**打开 DMG，把「一切在岛」拖进 Applications，打开后完成首次引导。build94 及以后支持应用内检查更新，安装仍由你确认。安装及系统提示说明见 [Mac 使用说明](apps/island/Distribution/开始使用.html)。

**Windows：**下载并运行上表的 x64 安装程序。测试包没有代码签名，系统可能显示未知发布者提示。不要将测试版的交叉构建通过视为真机稳定性保证；已实现范围与未支持功能见 [Windows 说明](docs/windows-port.md)。

**账号连接：**当前分发包的飞书和中台连接依赖虚实传媒的授权服务及账号权限，并非任意飞书用户都能直接接入。公开源码不开放公司的服务权限。开发者可以先运行 Windows 合成演示；自建授权服务参见 [AuthService 说明](apps/island/AuthService/README.md)，仍需自行配置合法的应用与授权，不能复用维护者凭据。

## 功能

| 模块 | macOS | Windows 测试版 |
| --- | --- | --- |
| 飞书消息 | 重要/最近消息、会话跳转、多行弹幕、图片缩略图与点击展开 | 消息列表、规则筛选、弹幕与会话跳转；真实账号尚未验收 |
| 待办与日程 | 待办排序、历史、时间提醒、本人日历只读查看 | 已实现待办、提醒与日历流程；日历授权待真机验收 |
| Agent | 已连接工具的状态、额度及开始/完成提醒 | Codex、Claude Code 等部分入口；不支持项见 Windows 说明 |
| 快捷入口 | 八向轮盘、自定义 HTTPS 入口与图标 | 轮盘与入口编辑；目前使用组合快捷键 |
| 数据保留 | 消息默认本机保留7天，可调整或关闭 | 同样按账号隔离保存，见 Windows 说明 |

Mac build111 修复指定时间编辑和更新弹窗遮挡，增加消息图片显示。真实历史图片已在灵动岛点击展开并验证缩放；真实新图片进入桌面弹幕仍待现场观察。全部验证范围见 [验证记录](docs/验证记录.md)。

## 开发

| 目录 | 内容 |
| --- | --- |
| [apps/island](apps/island) | macOS：Swift、SwiftUI、AppKit、OpenNook、原生检查与打包 |
| [apps/windows](apps/windows) | Windows：Electron、主进程、页面、纯逻辑测试与NSIS打包 |
| [apps/island/AuthService](apps/island/AuthService) | 公司授权与安装包下载服务 |
| [apps/island/Distribution/site](apps/island/Distribution/site) | 产品网页源码 |
| [apps/danmu](apps/danmu) | 历史弹幕项目，保留来源与回归检查 |
| [docs](docs) | 平台说明、来源和有日期的验证记录 |

### Windows

```sh
npm ci --prefix apps/windows
npm test --prefix apps/windows
npm run demo --prefix apps/windows
# Windows x64 安装包；会下载并校验官方 CLI
npm run pack:win --prefix apps/windows
```

demo 使用合成数据，不连接真实账号。具体依赖与限制见 [Windows 开发说明](apps/windows/README.md)。

### macOS

```sh
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
bash scripts/check.sh island-reader
bash scripts/check.sh island
```

生产构建需要兼容 Swift 工具链、SDK 和官方 lark-cli。完整步骤见 [Mac 开发说明](apps/island/README.md)。仓库不包含个人登录态或发布签名私钥。

## 隐私与反馈

消息读取不发送消息、不修改飞书已读状态。消息历史与图片缓存按账号保存在本机，不写入诊断日志；主动使用的公司服务另按本人权限访问。

报告问题请提供平台、版本、复现步骤与预期结果，并遮盖账号、聊天内容及凭据。普通问题使用 [Issues](https://github.com/zaizhi-1112/feishu-island/issues)；涉及凭据泄露或安全漏洞，先看 [安全反馈](SECURITY.md)。

## 贡献、来源与许可

柚子开发灵动岛，宰治开发飞书弹幕，双方共同推进「一切在岛」。欢迎通过 Issue 描述问题，通过 Pull Request 提交改进；流程见 [贡献指南](CONTRIBUTING.md)。

**当前仓库公开，但项目整体许可证尚未确定。** 第三方代码保留原许可证；商标、角色、图片、音乐和视频不因源码公开而获得统一再授权。来源与素材边界见 [来源与许可](docs/来源与许可.md)。

源码、安装包和公司网站分别发布。当前整理在合并请求中准备，正式源码合入仍需两位负责人批准；不通过更换默认分支掩盖版本差异。
