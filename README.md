<img src="apps/island/Distribution/site/icon.png" alt="一切在岛图标" width="88">

# 一切在岛

把飞书消息、Agent 状态、待办日程和虚实中台放进 Mac 顶部的灵动岛。

**开发版本：0.12.16 · build110（2026-10-30）；公开下载仍为 build108** · Apple 芯片 Mac · macOS 15 或更高版本

发布进度及待解决问题见 [验证记录](docs/build95-first-run.md)。

[下载最新版本](https://github.com/zaizhi-1112/feishu-island/releases/latest) · [产品网页](https://feishu-island.virxact.net) · [反馈问题](https://github.com/zaizhi-1112/feishu-island/issues)

## 安装与开始使用

1. 在 [GitHub Releases](https://github.com/zaizhi-1112/feishu-island/releases/latest) 下载 `.dmg`，或从已登录的[虚实中台入口](https://virxact.net/apps/feishu-island/open)下载。
2. 打开安装包，把「一切在岛」拖进 Applications，然后从「应用程序」打开它。
3. 首次打开如果 macOS 拦截，前往「系统设置 → 隐私与安全性」，找到这次打开记录并点击「仍要打开」。当前安装包尚未经过 Apple 公证。
4. 依次完成七步选择：展开、外观、飞书、弹幕、提醒、快捷键和 Agent，点击「开始使用」后灵动岛才出现。Agent 可先跳过，以后在设置中一键发现并选择连接。

连接飞书时，点击「连接飞书」并使用自己的账号授权。消息只读，日程连接用于查看本人日历；普通用户不用创建 CLI 应用或挑选本机配置。飞书和中台功能需要账号本身具有相应权限。

build94 支持应用内检查更新。发布新的安装包到 GitHub Release 后，应用会提醒，由用户点击下载、安装和重新启动；旧版 build91 及以前需要先手动升级一次。完整离线说明随安装包提供，也可从 [Release 的 installation-guide.html](https://github.com/zaizhi-1112/feishu-island/releases/latest) 下载阅读。

## 可以做什么

| 模块 | 当前功能 |
| --- | --- |
| 飞书消息 | 重要与最近消息、正确打开对应会话、长消息多行弹幕；点击弹幕停留，移开继续 |
| 消息保留 | 默认在本机保留 7 天、每天 03:00 清理；可调整天数和清理时间，也可仅保留本次使用 |
| Agent | 查看工具运行状态；DeepSeek Harness 可使用本人已有登录查看余额，采用 DeepSeek 蓝色鲸鱼主题 |
| 待办与日程 | 待办、完成历史、本人日程查看、提醒预览和可删除的内置或导入素材 |
| 虚实中台 | 岛内个人卡片；独立八向快捷轮盘，可选中台入口、常用应用和本机设置 |
| 外观与交互 | 完整展开或先露胶囊；深浅主题；弹幕直接选色，背景和边线独立开关 |

快捷轮盘支持组合键和单键。轻按后可以滑出目标方向、点击选择；也可以按住快捷键选择方向，再松键打开。方向和入口可在设置中拖动配置。点击方向旁的编辑按钮，可修改自定义名称、HTTPS 网址和图标；图片支持拖入、点击图标后 ⌘V、粘贴按钮和文件导入。图标只保存于本机。

未完成待办可通过上下箭头或拖动手柄调整顺序，重启后保留；新待办放在最前面。

## 当前更新与验证

- 打开安装盘中的 App 后可一键安装并进入七步引导；未完成引导时，消息和提示不能提前唤出岛。
- Agent 只在本人点击连接后读取；跳过后保持未连接。快捷键通过「自定义快捷键」录制。
- 收起状态可选完全隐藏或露出黑边；先露胶囊与完整展开分别预览。虚实主题使用官方 Logo 和纯净黑白背景。
- 普通待办显示删除按钮；飞书日程可从本机移除并记住选择，不删除飞书原日程。
- 中台嵌套数据按标题、分组和数值展示，隐藏内部链接与字段，检查窄宽窗口和深浅色。
- 屏幕动效出现 3 秒后可点击或按任意键关闭；跨应用按键关闭需要本人授予 macOS 权限。KUN、Gemini 和自定义视频先处理成透明背景，原视频不变。

- 岛内字号可调整；Agent 提醒支持岛内提示和屏幕动效，可选择素材。
- Claude 桌面 Code 从客户端已有用量缓存补齐重置时间；设置窗口保持普通层级，展开的岛始终在普通应用上层，锁定仅控制移开后是否收起。中台快捷圆盘使用虚实 Logo。

检查、发布与未验证项见[当前验证记录](docs/验证记录.md)。本机已安装 build108；本轮不清空账号、待办和偏好，也不替同事授权。

## 源码与开发

| 目录 | 用途 |
| --- | --- |
| [apps/island](apps/island) | 当前 macOS 原生应用：Swift / SwiftUI / AppKit、资源、测试、构建与更新发布脚本 |
| [apps/island/AuthService](apps/island/AuthService) | 现有公司登录下的飞书业务授权与安装包下载服务 |
| [apps/island/Distribution/site](apps/island/Distribution/site) | 已上线的产品网页、演示和下载入口 |
| [apps/danmu](apps/danmu) | 历史飞书弹幕原生、Web 和 Electron 实现及合成检查 |
| [docs](docs) | 当前验证、协作方式、版本记录和来源说明；历史文档保留原日期 |

完整构建、依赖和打包步骤见 [应用开发说明](apps/island/README.md)。构建需要 macOS、兼容的 Swift 工具链及官方 `lark-cli` 可执行文件；源码不包含个人登录态或发布私钥。

```sh
# 不读取真实账号的 Node 合成检查
bash scripts/check.sh web
node --test apps/island/Tests/deepseek-balance.test.cjs
node --test apps/island/AuthService/*.test.cjs

# macOS 原生检查：使用本机实际可用的 SDK
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
bash scripts/check.sh island-reader
bash scripts/check.sh island
```

源码、安装包和官网分别有各自的交付步骤。发布前应同步这里的版本、功能说明与下载入口，并核对仓库默认分支、Release 和产品网页；不能只上传安装包。具体协作与发布核对见[协作速查](docs/协作速查.md)。

## 数据、来源与许可

消息正文不写诊断日志、不上传、不用于公开演示；本机历史按账号隔离，授权凭据和个人材料不进入仓库。公开源码不改变公司网页的访问范围，也不代表第三方账号已经接通。

柚子开发灵动岛，宰治开发飞书弹幕，双方共同推进「一切在岛」。第三方来源与现有许可证继续保留，见[来源与许可](docs/来源与许可.md)。仓库目前公开，项目整体许可证尚未另设；历史导入说明不代表当前产品状态。
