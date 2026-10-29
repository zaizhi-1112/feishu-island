# 中台快捷轮盘来源与边界

本次融合复用宰治 build50 的 `WorkspaceStore.hub`、`HubClient` 和独立授权 helper；卡片选择仍写入既有 `selectedCards`。主栏显示、八槽入口及音效偏好单独保存于 `FeishuIsland/Platform/preferences.json`，不重写账号授权或卡片正文。

原生模块和纵向设置参考佑哥提供的柚子岛 0.9.2 `Platform/PlatformModule.swift`。卡片选择统一为滑动开关，关闭主栏仅隐藏入口。

## LOLPingYourAI 移植

来源：用户桌面 `Codex/lol 信号的项目/LOLPingYourAI` 的 0.3.0 本地工具版。

- 八方向角度与中心取消区：`src/shared/geometry.ts` 的 `pickSlice`。
- 轮盘环形布局、分区高亮、中心视觉与图标：`src/renderer/overlay/wheel.ts`、`overlay.css`。
- 图标映射：`src/shared/pings.ts`。
- 移植为 SwiftUI；点击或按住拖动后松手打开一次明确的 HTTPS 入口，返回中心、释放到轮盘外不执行。仅组件内交互，无全局输入 hook。
- 随包资源：9 个 PNG、`Base.wav`、完整原 LICENSE 与 THIRD_PARTY_NOTICES，位于 `Resources/LOLPing`。

没有移植 Agent、AI SDK、截图、录屏、Inbox 收集、房间、relay或后台网络。没有读取或复制原项目用户 `settings.json`。

## 许可

LOLPingYourAI 源码：Copyright © 2026 Danrui Meng / LOLPingYourAI contributors，MIT；保留在 `Resources/LOLPing/LICENSE.txt`。其轮盘代码源于 darrenprx/lolPing 0.5.1，commit `f24a51e5a11c2b31dab72d89a571cc4025ad3c98`，详见原 THIRD_PARTY_NOTICES。

游戏图像与音效 © Riot Games, Inc.，**不适用 MIT**。仅按用户要求在本地融合包中保留原项目已有素材，不声明取得商用或新的分发授权，也不表示 Riot、OpenAI 或 Anthropic 背书。

## 验证入口

`swift run PlatformChecks` 验证八方向、取消区、边界、URL 校验、八槽保存恢复、隐藏保留配置、卡片失效保护、单次打开、权限及坏文件保留。

`swift run PlatformChecks --render /绝对路径/轮盘.png` 额外用不上屏窗口渲染合成轮盘，不读取真实中台，不启动浏览器，不播放声音。

2026-10-27 build55：本人要求轮盘仅由快捷键唤出。新增公开 Carbon 热键 Control+Option+Space 与原生小面板；不采用原 Electron 全局钩子，不读取键入内容，不接 Agent。
