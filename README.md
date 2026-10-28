# 飞书工作岛（协作暂名）

「一切在岛」的共同源码仓库。当前原生应用位于 `apps/island`，本轮以柚子 0.10.0 build82 为基线修复并安装本机更新。下文导入结构与融合顺序保留为历史说明；当前构建入口见 [应用说明](apps/island/README.md)，本轮验证见 [工作记录](docs/build82-refinements.md)。

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
bash scripts/check.sh mcp            # macOS：外观 MCP 纯数据测试
bash scripts/check.sh island-reader  # macOS：同事版只读接收合成测试
bash scripts/check.sh island         # macOS：灵动岛逻辑检查，需兼容的 Swift SDK
```

`ISLAND_SDK` 可以覆盖当前选中的 SDK。例如本轮验证使用本机实际存在的 `MacOSX26.4.sdk`。不要照搬其他人的 SDK 路径。

本仓库不带 CLI 可执行文件、登录态或安装包。使用某个真实入口前，先读它的 HANDOFF/AGENTS 和本说明，按本人授权配置。原生完整弹幕的 CLI 恢复：在 `apps/danmu` 下 `npm ci --prefix tools/lark-cli`，将匹配架构的固定版本 CLI 放到 `tools/lark-cli/bin/lark-cli`；Electron 可用 `mkdir -p .build && python3 scripts/release/fetch-cli.py` 恢复三平台工具。不要复制别人的 profile。

## 两人协作

一项需求对应一个 Issue；每个 Agent 从最新 main 建自己的分支；测试后提交 Pull Request，由另一人/维护者查看效果与限制再合并。不要让两边直接覆盖 main，不 force push，不自动发布。GitHub 是否强制执行评审，以仓库设置实际结果为准，CODEOWNERS 本身不构成强制保护。

## 本轮融合方向

灵动岛负责常驻入口与重要消息列表，弹幕作为可关闭的展示通道；同一进程只运行一个本机接收器，接收成功后按规则分发。沿用同事版结构化消息和未知未读状态重试，接入你已有的透明渲染器。云端 Web 暂时独立保留，不擅自把本机授权或消息送到服务器。

项目和同事的导入代码不默认开源。保留 OpenNook、NookSurface 与第三方许可，仓库保持私有。
