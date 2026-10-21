# 飞书工作岛（协作暂名）

柚子岛 0.5.0 与飞书弹幕 0.7.1 的共同源码仓库。**当前本机工作版 0.7.0：飞书消息、材料处理、后台AI完成提醒、持久待办及个人中台卡片；build18新增本人豆包网页往返与云文档新建/中台回读，独立授权组件在UI更新后自动恢复。Dot短期连接的合成任务真实回传与重读已核对；build20新增项目长期配对、主动派单与独立联调窗口，真实Dot长期合成往返已独立核对成功；日用版现已升级到build20；build21已补事件订阅、签名通知和随应用运行的私人隧道组件；受限凭据存独立钥匙串，目前暂停启用并等待此次新增访问确认。Dot私人插件安装、真实订阅和自动唤醒尚未验收，日用仍为build20。本人安装与真实飞书只读查询通过；本人已明确同意统一权限并完成独立中台OAuth，真实周报已在原生岛内显示。** 原导入未更改线上弹幕；本人后续已明确切换至融合版并停用旧组件，其他用户配置不受影响。

- 当前版本先读 [使用说明](docs/预览版使用说明.html)，构建不自动安装或替换旧版。
- 先双击打开 [融合与协作说明.html](docs/融合与协作说明.html)：面向双方和 Agent，含对比、融合顺序、分工及可复制的任务指令。
- GitHub 在线阅读见 [协作速查](docs/协作速查.md)。HTML 请下载或克隆后双击打开，GitHub 默认显示其源码。
- [当前验证记录](docs/验证记录.md)、[来源与许可证](docs/来源与许可.md)。

## 放了什么

| 目录 | 用途 |
| --- | --- |
| `apps/island` | 同事的灵动岛、本机飞书接收、重要规则和本机网页设置 |
| `apps/danmu` | 你的桌面弹幕、私有网页、外观 MCP；保留 Swift/Electron 两套桌面实现 |
| `docs` | 融合决定、非技术协作说明、导入记录 |
| `.github` | 需求模板、PR 模板、核心文件负责人和自动合成检查 |

## 测试入口（不会启动真实账号接收）

```sh
bash scripts/check.sh web            # Node：Web 和 Electron 核心合成测试，无需 npm install
bash scripts/check.sh fusion         # 合成 CLI、分发、渲染、设置与 MCP
bash scripts/check.sh mcp            # macOS：外观 MCP 纯数据测试
bash scripts/check.sh island-reader  # macOS：同事版只读接收合成测试
bash scripts/check.sh island         # macOS：灵动岛逻辑检查，需兼容的 Swift SDK
```

`ISLAND_SDK` 可以覆盖当前选中的 SDK。例如本轮验证使用本机实际存在的 `MacOSX26.4.sdk`。不要照搬其他人的 SDK 路径。

本仓库不带 CLI 可执行文件、登录态或安装包。使用某个真实入口前，先读它的 HANDOFF/AGENTS 和本说明，按本人授权配置。原生完整弹幕的 CLI 恢复：在 `apps/danmu` 下 `npm ci --prefix tools/lark-cli`，将匹配架构的固定版本 CLI 放到 `tools/lark-cli/bin/lark-cli`；Electron 可用 `mkdir -p .build && python3 scripts/release/fetch-cli.py` 恢复三平台工具。不要复制别人的 profile。

## 两人协作

日常使用 [中文协作面板](https://feishu-danmu.virxact.net/collab/)：需求、版本、过程与阶段总结在同一个入口。宰治与柚子分别同意同一版本后，确认的源码版本合入 GitHub；网站面板用于信息同步与协作。定时任务目前关闭。源码操作使用各自的 GitHub 身份，不自动安装应用或上线产品服务。首次由柚子申请加入，宰治确认身份。细节见 `apps/danmu/Web/collab/README.md`。


一项需求对应一个 Issue；每个 Agent 从最新 main 建自己的分支；测试后提交 Pull Request，由另一人/维护者查看效果与限制再合并。不要让两边直接覆盖 main，不 force push，不自动发布。GitHub 是否强制执行评审，以仓库设置实际结果为准，CODEOWNERS 本身不构成强制保护。

## 本轮融合方向

灵动岛负责入口、消息列表与分页阅读，当前本机显示全部留在岛内；同一进程只运行一个本机接收器，接收成功后按规则分发。沿用同事版结构化消息和未知未读状态重试，接入你已有的透明渲染器。云端 Web 暂时独立保留，不擅自把本机授权或消息送到服务器。

项目和同事的导入代码不默认开源。保留 OpenNook、NookSurface 与第三方许可，仓库保持私有。

## 独立融合预览构建

指定本机兼容的 ISLAND_SDK 和可选的官方工具绝对路径 ISLAND_LARK_CLI，运行 `bash apps/island/scripts/build.sh`。产物是 `apps/island/dist/飞书工作岛预览版.app`，不会启动或安装。只复制 CLI 二进制和许可证，不复制 profile 或任何登录态。首次接收与弹幕关闭；检测到旧弹幕运行会拒绝开启新的真实接收，不结束旧进程。详细操作和验证限制见预览版 HTML。

每次迭代经相关检查后同步开发分支和 PR，方便两位负责人各自用 Codex 接续；正式源码版本合入 main 仍需宰治与柚子分别同意。同步不包含本机授权、材料、任务结果或真实聊天记录。

当前使用与各平台真实验收：[AI工作台接入与验收](docs/AI工作台接入与验收.html)。

本机build19：待办可在岛内编辑、删除并恢复；顶部按明确悬停展开意图触发。操作与验收见[使用说明](docs/预览版使用说明.html)。
