# LOLPingYourAI 只读审计与原生融合

## 原实现

- 来源：用户桌面 `Codex/lol 信号的项目/LOLPingYourAI`，package 0.3.0；Electron 44 / React 19 / TypeScript 5。
- 程序入口：`src/main/index.ts`，当前调用 `startLocalTools`。旧 `ai/` 仍保留于源码，但这不代表当前工具版运行 AI 服务。
- 轮盘：`src/shared/geometry.ts` 计算北向起顺时针八扇区及中心死区；`src/renderer/overlay/wheel.ts` / `overlay.css` 完成高亮、收放与信号视觉；`src/shared/pings.ts` 映射图像/声音。
- 持久化：`src/main/settingsStore.ts` 原子保存 `settings.json`，含 toolBindings、轮盘顺序和触发键等。未读取或复制用户运行配置。
- 原权限：C++ 全局事件钩子需辅助功能，截图需录屏；截图/Inbox 与 Agent 均不属于本次中台快捷入口范围。
- 依赖：Electron/React UI、原生 hook helper、Swift desktop helper、AI SDK/Sharp 和 relay 等保留于旧项目。本次移植不引入这些运行依赖。

## 本次取舍与实现

原生 SwiftUI 模块 `UnifiedPlatformModule` 复用宰治版本 `WorkspaceStore.hub`、HubClient、独立中台授权 helper；按佑哥版本统一同级中台入口和纵向设置。

- `HubPingWheel.swift` 原生重现八方向轮盘、中心视觉、图标、高亮、点击/按住拖动松手打开。移回中心或移出边界取消；一次动作只打开一个已配置 HTTPS URL。
- 八槽可设自动分配、固定中台卡片、自定义入口或留空。自动项按选定卡片优先，缺失链接显示不可用，不伪造目标。
- 独立 `UnifiedPlatformStore` 只存主栏显示、轮盘和音效偏好；关闭主栏不清连接、不清卡片。卡片选择/排序继续用既有 selectedCards，所有选择使用滑动开关。
- 主栏未显示仍可从桌面设置管理。卡片正文仅引用原内存快照，未复制存盘。
- 打开动作经 NSWorkspace.open，检查 HTTPS、账号口令、控制字符及明显凭据参数；实际打开失败显示错误。
- 不包含 Agent、聊天、文档发送、截图、Inbox、全局快捷键、录屏或辅助功能请求。不启动第二个 Electron 后台。
- 原项目保持只读，没有修改其应用、设置、系统权限或运行状态。

## 许可

源代码 MIT，保留 Danrui Meng / LOLPingYourAI contributors 署名及原 THIRD_PARTY_NOTICES。轮盘源自 darrenprx/lolPing 0.5.1，固定上游 commit f24a51e5a11c2b31dab72d89a571cc4025ad3c98。

LoL 图像/音效 © Riot Games，不适用 MIT。按用户本地融合要求复制原有素材，不声明商用或新的分发授权，不表示相关公司背书。完整许可随资源打包。

## 验证状态

已通过完整 debug 构建。PlatformChecks 57 项模型检查通过，覆盖几何、取消边界、URL、持久化恢复、隐藏保留配置、失效卡片、单次执行、文件权限与坏文件保留。

独立非生产 bundle 夹具复制了实际 LOLPing 资源，并在不上屏原生窗口渲染轮盘和400×400中台模块；加两项窗口不可见断言，共59项通过。已实际查看两张 PNG，轮盘、八方向文字、标题和操作提示均完整，无重叠或边缘截断。图片为合成中台数据：[轮盘](platform-wheel.png)、[400pt中台模块](platform-panel.png)。

首次沙盒运行在 NSApplication 注册图形会话时中止；采用受审的仅合成离屏渲染权限后成功，不是产品崩溃验收。打开链接采用注入闭包验证一次调用，未真实打开浏览器；真人鼠标拖动、真实中台账号授权未在本次子任务中验收。

## 复制资源 SHA-256

- `Base.wav`：`5faeb0973e85fc3b768afad2f88943a51289469d302cad836623eb037d0bcb24`
- `LICENSE.txt`：`6241c6ee5310b971464142c094cf1ba7ec27154d6d7acb38b2322931fe86f928`
- `THIRD_PARTY_NOTICES.md`：`c84be8eeb8779a27aba938b9d50a6240651ef7ed8254d67480077757da3f2ce9`
- `all_in.png`：`0574710c5b250ecb454ed34e4dddaed7c6a9ac169739c0e244d873e2f98d7d58`
- `assist_me.png`：`506d91d72e260469fa220d4642734018bbc17149bad730e2e0a2aee71979b722`
- `enemy_missing.png`：`85a92a2807f06b45e9e807774f467e2e0d4066702414a4f0b21e92881ea0d93a`
- `generic_ping.png`：`dac063deb4567a42895122a3bdff170bbd3436e98e2d266ee851771aecc28ba2`
- `need_vision.png`：`c421e8a1172cd1c9c5c3a4a0e2b1e7b730ba7bf0519d90adf98824c8b6d78e1d`
- `omw.png`：`b67f8030fcf30aa52faa010433463574c74d9a7214f1e80f9f0e25ac5f4b07d5`
- `pingwheel_enemyvisionrender.png`：`b0bff531e4f662c337c2ab3a3624d01b45718f8a4fbca3348d750a92e6620562`
- `pingwheel_retreatrender.png`：`269be035c1f88173a9ec76e4d5f1f5b81ae5f5091655860869563842877b791c`
- `push.png`：`a4bf19adbfe0e106e519d5dbe657a7f8c301e5ef5455edfcdde25b053efba267`
