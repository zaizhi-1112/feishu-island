<img src="apps/island/Distribution/site/icon.png" alt="一切在岛图标" width="88">

# 一切在岛

把飞书消息、Agent 状态、待办日程和虚实中台放进 Mac 顶部的灵动岛。

**当前版本：0.12.0 · build94（2026-10-29）** · Apple 芯片 Mac · macOS 15 或更高版本

[下载最新版本](https://github.com/zaizhi-1112/feishu-island/releases/latest) · [产品网页](https://feishu-island.virxact.net) · [反馈问题](https://github.com/zaizhi-1112/feishu-island/issues)

## 安装与开始使用

1. 在 [GitHub Releases](https://github.com/zaizhi-1112/feishu-island/releases/latest) 下载 `.dmg`，或从已登录的[虚实中台入口](https://virxact.net/apps/feishu-island/open)下载。
2. 打开安装包，把「一切在岛」拖进「应用程序」。安装窗口下方有图文指引。
3. 首次打开如果 macOS 拦截，前往「系统设置 → 隐私与安全性」，找到这次打开记录并点击「仍要打开」。当前安装包尚未经过 Apple 公证。
4. 跟随图标完成六步选择：灵动岛移入方式、深浅外观、飞书连接、桌面弹幕、提醒预览和 Agent。以后可以在设置中重新选择。

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

快捷轮盘支持组合键和单键。轻按后可以滑出目标方向、点击选择；也可以按住快捷键选择方向，再松键打开。方向和入口可在设置中拖动配置。

## build94 更新与验证

- 飞书卡片按原始内容读取，修复部分卡片只显示“请升级客户端”的问题。
- 长消息采用多行移动与分段轮播；八条长消息的完整分段、停留和恢复已用合成数据检查。
- 消息与待播进度按本人账号保存在本机，更新和重启后接续；旧版已丢失且已读的内容无法恢复。
- 修复快捷键释放状态残留造成的轮盘唤出失败；用户已在其他应用中确认单键连续唤出正常。
- 完成从 build92 到 build94 的真实应用内更新，安装后文件、签名和数据保留均已核对。

已通过 453 项产品检查、1147 项融合断言、105 会话接收检查、13 项打包检查；16 张此前降级的真实卡片已只读核对完整内容。多行弹幕的真实新消息到达、真人点击与多日持续运行尚未完成现场验收。详细结果见[当前验证记录](docs/验证记录.md)。

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
