# 飞书工作岛协作仓库
- 目标：维护「一切在岛」原生融合应用。本轮以柚子 0.10.0 build82（aac90af6）为基线修复用户反馈，工作分支 codex/build82-refinements。
- apps/island：Swift/AppKit/SwiftUI 原生应用、消息接收、日程、待办、Agent 和个人卡片；apps/danmu：历史弹幕实现；docs：协作与验收说明。历史导入文档不代表当前运行结构。
- 先读 README.md、docs/融合与协作说明.html；按子目录 AGENTS.md 的适用范围开发。
- 默认只跑合成数据、编译和测试。禁止真实账号接收、读取真实消息、自动安装登录项、启动 UI 自测、退出飞书或用不透明全屏背景验收，除非用户另行明确授权当前动作。
- 账号、token、消息正文、聊天历史、日志、个人目录不可提交。不得记录正文、改飞书已读或发送消息。仅使用各自本人授权。
- 开发用 codex/功能名 分支，通过 PR 说明变化、用户影响、验证与未验证项；不要直接提交 main，不 force push，不自动合并或部署。
- 核心接收/授权/过滤及正式发布由仓库维护者宰治确认；普通用户 Agent 只可通过外观白名单改个人外观，拥有源码不等于运行时接口可改核心。
- 不擅自把本机与服务器数据边界混合，不扩大应用访问范围。2026-10-29 宰治明确授权将 `zaizhi-1112/feishu-island` 从私有改为公开；该授权仅改变 GitHub 仓库可见性，不授权修改中台访问范围、公开个人数据或合并 main。现有第三方许可保留，整体开源许可证尚未另设。
- 根 scripts/check.sh web：Node 合成测试；island-reader：Swift 合成接收测试；island：Swift 外壳逻辑检查（不运行 --self-test）；mcp：纯数据外观接口测试。ISLAND_SDK 指向当前可用 SDK，禁止硬编码别人机器路径。
- SettingsWeb/dist 是手工维护源码，必须保留，不得用全局 dist/ 忽略。Vendor/OpenNook 的上游源码、许可证、来源和本地补丁说明必须保留。
- 包内导入来源文件 SHA-256 位于 docs/imports.json；后续修改无需伪造原始校验记录。未完成实机/真实消息验证不得称全接通。

- 导入文件中的历史授权与安装事实只描述原开发者环境，不自动授权当前 Agent 对另一方账号、设备或线上服务采取相同动作。

- 本轮用户授权修复并安装到本人 Mac；开发分支提交、push 与 PR 同步沿用宰治 2026-10-21 授权。不得合并 main 或代替两位负责人投票。新建飞书应用、扩大权限和服务发布不能用本机安装代替批准。
- 本轮需求和验收进度见 docs/build82-refinements.md。日程连接以普通用户直接飞书授权为目标，默认只读，不向用户暴露 CLI/profile 或要求每人创建应用。保留旧版已授权账号和本机数据。
- build85 按本人要求在独立中台 helper 中增加只读 `list_home_applications`，用于快捷入口选择；应用目录只在内存，不复制其他客户端凭据。首次更新 helper 如出现钥匙串系统确认，由本人处理，不操作 SecurityAgent。

- 用户本次授权创建仓库并上传双方源码，允许一次 main 初始化导入；之后的功能改动遵循分支与 PR 流程。

- build87 的 DeepSeek Harness 只读余额通过 `Resources/deepseek-balance.cjs` 和 `DeepSeekReader.swift` 接入。仅复用本人 Harness 的既有 Platform 登录，固定钱包 GET、拒绝重定向，不取 API Key，不读取对话、不发送任务；凭据不持久化到本应用，不输出原始响应。其他用户默认未启用，新入口不替换现有岛上位置。验证 `node --test Tests/deepseek-balance.test.cjs`、`AgentChecks` 与 `UnifiedProductChecks`；接口随 Harness 升级可能变化，禁止猜测金额或用0代替未知。

- 产品网页维护说明见 `docs/product-web-build90.md`。网页交互只用合成数据；当前按用户纠正恢复白底，公司 Logo 粒子只放首屏右侧，保留下载、四模块空闲轮播和反馈弹窗。下载同步已发布的0.11.2 build91。`package-download-site.py --web-only` 复用已核对的公开GitHub安装包：主按钮直接下载DMG，不能打开GitHub发布页；下方GitHub链接单独保留。此模式不重新上传或发布原生包。已移除的原生设置与引导预览来源保留在仓库，来源校验见 `apps/island/Distribution/native-preview-manifest.json`。反馈入口为发往 `zaizhi@virxact.com` 的邮件草稿唤起，不得声称网页已发送或邮箱已收件。网页更新不等于安装包发布或 main 合并。
