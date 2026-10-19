# OpenNook来源与本地修改

- 上游：https://github.com/twinkling-reality/opennook
- 固定提交：`2b50b5c3a99df8914e25e199d29bf7aa505f7a59`
- 仅引入`NookSurface`、`NookKit`、`NookApp`三个核心模块，没有引入演示产品、网站或自动更新器。
- `NookSurface`为MIT；`NookKit`和`NookApp`为Apache-2.0。原始许可证、版权声明及第三方声明保留在本目录，并随应用打包。

本地补丁：

1. 核心库使用独立Swift Package。构建脚本默认使用本机已安装的macOS 26.5 SDK，避开macOS 27 SDK在当前Command Line Tools中缺失的SwiftUI宏插件。
2. `NookSharedElement.swift`中的3个`@Entry`改成等价的显式`EnvironmentKey`，不改变环境值语义。
3. `NookDisplayPreference`新增`automatic`，优先外屏，再回退内屏或当前可用屏幕；校验失效的主屏索引。显示设置补齐对应选项与说明。
4. `Nook.swift`同时监听显示器变化、系统唤醒和屏幕唤醒，250毫秒合并突发通知后重新定位窗口。
5. `EnvironmentValues.nookSwitchModule`改为公开访问，供外部模块里的导航按钮使用。
6. `NookChromeBehavior.edgeDocked`启用三段交互；`NookEdgeDockLayout`统一计算顶边收起、悬停露出及展开的几何与感应范围。`NookView`只绘制收起时的小边，并保留露出时从顶边通向胶囊的感应区域。鼠标悬停不触发完整展开，只有点击或已有快捷键才展开。内屏小边避开硬件刘海；窗口重建时清空旧鼠标状态。
7. 悬浮形态的第二段胶囊露出时，上沿距屏幕顶边4个逻辑像素；在刘海屏强制选择悬浮时，从硬件刘海下沿留4个逻辑像素。第三段也使用相同上沿，消除展开时向下移动；贴合刘海的完整面板从屏幕顶边绘制并避让硬件区域。
8. 0.2.3为真实刘海且采用刘海形态的屏幕新增独立布局：收起时隐藏软件黑色表面，仅保留近透明感应区；悬停状态使用刘海两侧槽位；完整面板使用自然高度，避免被用于收起的小高度裁切。`NookNotchDockLayout`只在收起时限制尺寸。模块切换入口在刘海区域只显示图标，保留完整辅助功能名称。

9. 0.3.0使用`NookHostingView.acceptsFirstMouse`接收窗口未激活时的首次点击，`NookPanel.sendEvent`在同一鼠标按下事件分发前获得键盘焦点，避免第一次点击只激活窗口。仍保持悬停仅露出、点击才展开。

升级时应逐项复核这些补丁，运行根目录`scripts/check.sh`及应用`--self-test`，再做实际屏幕拔插验收。上游部分Swift 5并发警告仍保留，不代表已经迁移到Swift 6严格并发模式。
