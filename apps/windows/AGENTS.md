# 一切在岛 Windows 版
- 目标：用 Electron 在 Windows 10/11 x64 上提供与 Mac 版「一切在岛」相同的四个模块（飞书消息、Agent、待办日程、虚实中台）、设置、首次引导、桌面弹幕、快捷轮盘、屏幕提醒和检查更新。行为以 apps/island 的 Swift 实现为准，规则不另起炉灶。计划与验收见 ../../docs/windows-port.md。
- 目录：main/ 主进程（窗口、授权、接收、存储，全部 CommonJS）；core/ 纯逻辑（无 Electron 依赖，可在 Node 直接测试）；renderer/ 各窗口页面（原生 HTML/CSS/JS，无框架、无远程资源）；assets/ 图标与随包素材；tests/ node --test 合成测试；scripts/ 构建与发布脚本；vendor/win-x64 官方 lark-cli.exe（不进 Git，构建前由 scripts/fetch-cli.cjs 从官方发布下载并核对 SHA-256）。
- 验证：`npm test --prefix apps/windows`；`npm run pack:win --prefix apps/windows` 在 macOS 上交叉打出 NSIS 安装包。Mac 上能打包不等于 Windows 真机通过，两者必须分开记录；没有代码签名证书，不得承诺安装无 SmartScreen 提示。
- 隐私边界与 Mac 版相同：消息只读、不改已读、不发送；消息正文只在内存和本机 userData 下按账号隔离保存（默认 7 天，可关）；不写日志正文；凭据只用 Electron safeStorage（Windows DPAPI）加密保存；安装包禁止包含任何个人 profile、token、App Secret 或真实消息。
- 渲染进程一律 contextIsolation、sandbox、无 nodeIntegration，只通过 preload 暴露的白名单接口与主进程通信；不加载远程页面，公司授权窗口单独使用持久分区，只允许 feishu-island.virxact.net 与公司登录跳转所需域名。
- 默认只跑合成数据。真实账号接收、Windows 真机安装、发布 Release 和中台部署都需本人当次明确同意；正式 Release 与 main 合并仍需两位负责人分别批准同一版本。
