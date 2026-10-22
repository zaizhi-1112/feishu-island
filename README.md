# 飞书工作岛（协作暂名）

柚子岛 0.5.0 与飞书弹幕 0.7.1 的共同源码仓库。**当前本机工作版 0.7.0 build28：已从中台实际下载并核验安装包，备份后升级日用版；594 条融合断言、18 项公司授权服务检查和 3 项打包检查通过。本人日用 WK 首次扫码登录、启用公司归档、岛内直接归档合成文字/链接/TXT/PNG、飞书独立回读及链接返回岛内已完成。原飞书接收配置、21 条既有任务、中台连接与 5 个稳定 helper 保持。重启后公司登录持久性、史天佑设备及其个人 Dot 首次配置仍待验收。**

历史功能与验证：**build26：新增可选Chrome当前页面收录扩展，复用已登录页面可见正文；扩展已由本人安装在ego lite，完整点击收录→顶部灵动岛→飞书归档与网页回读已通过；另已实测交给Dot后自动分析、自动归档并返回岛内链接，中间无需复制粘贴。538条融合断言和合成登录页面提取、原生归档回读已通过。build25：新增可选网页正文提取，先预览，再直接归档或交给AI分析后归档。统一归档支持新建文档、追加已有文档、多维表格新增文档链接记录，也可直接归档不调用AI。独立授权和真实归档回读已通过，日用Dot自动处理到归档返回链接已实测。日常工作已连接真实 Dot 私人插件与事件自动任务，点击“交给AI”后自动领取、回传并在灵动岛提醒。2026-10-22 已完成日常项目合成任务A及升级重启后的B真实自动往返；无需逐次复制连接或催办。修复本机代理DNS导致回调校验失败；保留公网地址和TLS校验。飞书接收与中台保持原连接。Mac与ChatGPT需在线；build23已补隧道健康重启、断线暂存和回调恢复后自动重试，模拟94小时续订通过；平台自然跨天续订与多日运行仍待实际证据。** 原导入未更改线上弹幕；本人后续已明确切换至融合版并停用旧组件，其他用户配置不受影响。

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

历史build19：待办可在岛内编辑、删除并恢复；顶部按明确悬停展开意图触发。操作与验收见[使用说明](docs/预览版使用说明.html)。

## 同事试用准备（尚非安装即全接通）

首位试用者为史天佑（柚子）。[试用准备说明](apps/island/Distribution/开始使用.html)明确安装条件、各自授权与尚未完成的接入环节。现有日用账号的真实验收不能替代同事账号验收。

构建时可指定尚不存在的绝对 `.app` 路径 `ISLAND_APP_OUTPUT`，保留当前运行版本。构建会一并带入当前网页收录扩展。`python3 apps/island/scripts/package-pilot.py /absolute/path/to/application.app` 生成独立试用 ZIP、文件哈希清单和 SHA256SUMS；只接受列明的程序资源，核验签名与所有 helper 架构，不复制 profile、工作区、隧道配置或授权凭据。输出在忽略的 `apps/island/releases`，不上传到源码仓库。

build27 阶段验证：`python3 apps/island/Tests/package-pilot-test.py`；独立 Release 构建、arm64 架构校验、ZIP CRC、桌面/390px 说明阅读检查通过；未替换或重启日用应用，接收仍开启且状态正常。下载入口当时已上线；该阶段未配置同事真实账号、未合并 main。后续日用 build28 安装与本人公司归档验收见下文。

飞书后台接入范围：消息应用 1.0.2、独立归档应用 1.0.1 已发布，仅宰治与史天佑两位成员，原权限未变；史天佑本人尚未授权/验收。旧中台下载域名已实测无对应应用；新下载入口为 https://feishu-island.virxact.net，仅宰治和柚子可见。公司授权服务已上线；原生接续在 build28 实现，本人日用版首次登录与公司归档已实测；同事账号仍需分别验收。

首次授权的技术边界：飞书官方 [v3 用户令牌说明](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/get-user-access-token-v3)明确，自建应用为 Confidential Client，换取用户令牌仍需要应用密钥；不能把共享 App Secret 装进可分发包。build28 已增加公司授权服务与本机接续实现；不复制开发者 CLI profile；本人首次登录与公司归档已通过，同事完整流程仍需单独验收。

此前独立分发 build27 使用宰治指定图标，运行逻辑沿用 build26；build28 沿用该图标。图标、白名单打包与入口可复现。3 项分发检查、538 条融合合成断言通过，日用接收未重启。该阶段记录不代表当前日用版本。当前仍不能承诺史天佑仅安装即全部接通：其本人授权、个人 Dot 首次配置和同事实机验收仍未完成。Windows 版按本人决定延期，当前只交付 M 系列 Mac 试用包。


## 公司连接（build28，已安装日用版）

公司授权服务 release248 已上线，仍只对宰治和柚子开放。消息和归档各自授权，应用密钥与刷新凭据由服务器加密保管。Mac 内置独立 WebKit 公司登录窗口，先 prepare 核对授权，重新检查任务和设置未变化后才 activate；核对期间不切换现有消息或归档连接。有效公司登录会话下，短期访问令牌只在内存中交给官方 CLI 1.0.96 的 `LARKSUITE_CLI_USER_ACCESS_TOKEN` 环境提供方；App Secret 和 refresh token 不回到 Mac。不读取外部浏览器 Cookie，不改既有 CLI profile。

2026-10-23 本人明确要求替换后，已从中台实际下载 SHA-256 为 `c401a0503754a724e3f6b04c56865b75738abb97a3becae00316739f490ee708` 的 ZIP，备份旧 build26 与工作区，再安装日用 build28。接收开启，connection/account/rules/customRules/danmu 配置哈希一致，21 条既有任务完整，中台已连接，5 个稳定 helper 字节一致。594 条融合断言、18 项服务检查与 3 项分发检查通过。

日用 WK 重开全新登录事务后，本人扫码登录成功；公司归档授权经 prepare/activate 启用。实际从灵动岛点击“直接归档”，合成任务 `0A6CE1C5-4AF9-4BCD-93B7-EB0645FFF425` 的文字、链接、TXT 与 PNG 已保存到飞书，归档 succeeded、verifiedAt 存在，正文与两项附件回读通过；中台另行读取同一文档核对一致。岛内显示“飞书归档已完成”和打开文档链接。未调用 AI 或派发 Dot，任务已标完成并取消提醒。[本次合成文档](https://datakhazix.feishu.cn/docx/R70adIGG0oZ49gxpmdXcTTGjnge)；[完整验收记录](docs/AI工作台接入与验收.html#company28)。

尚未重启验证公司登录持久性；公司消息授权未迁移，消息继续使用原有正常接收配置。史天佑设备、其个人 Dot 首次配置与完整流程仍未实测，不把本人归档验证说成同事安装即全接通。
