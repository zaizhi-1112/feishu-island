# 四套皮肤

原生与网页使用 `dist/skins.json` 的同一套深浅色值。Agent角色根据真实Agent ID索引，和当前皮肤分开。

- Codex蓝色角色：官方Codex应用内置的 `codex-spritesheet-v6`；对应官网参考：https://developers.openai.com/modretro 。保留原有像素造型，仅裁去透明边距并制作头像。
- Claude Code角色：官方Claude应用的 `ion-dist/images/install-hub/clawd-laptop.mov` 原始Clawd帧；保留官方像素风格，不重新建模。
- WorkBuddy角色：https://www.workbuddy.cn/work/ 官网的 `buddy-worker-woRTGfZH.png`，保留完整猫耳、耳机、银色材质和电脑。
- 虚实传媒标志与原字：https://virxact.com 首屏公开SVG，保留两根斜杠及原有字形。`scripts/skins/prepare-assets.py`生成几何与静态降级图；`prepare-flow.py`在原轮廓内求解稳态势流，生成原生和网页共用的流线。

`skin-effects.js`与原生`SkinFlow.swift`负责轻动效，隐藏、关闭动效或系统减少动态时停下；原有控件布局不参与动画。

构建：`./scripts/build.sh` → `./scripts/package-skin-preview.sh` → `./scripts/skin-preview.sh`。预览使用独立bundle、设置和18776端口，不连接真实业务数据，也不会替换已安装应用。

## build40 Codex 标识
用户指定紫蓝色云朵终端图标。`dist/agent-codex.png` 逐字节复制本机已安装 ChatGPT.app 的 `Contents/Resources/icon-codex-dark-color.png`，用于 Agent 选择、胶囊和状态提醒，不再用 OpenAI 结形图标或机器人头像代替。`pet-codex.png` 和原 `avatar-codex.png` 仍保留作角色素材。未修改原始图像像素。
