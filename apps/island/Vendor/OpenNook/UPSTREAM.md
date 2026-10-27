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

10. 0.6.1曾在第二阶段关闭紧凑内容的命中测试，以避免图标吞掉展开点击。0.6.2撤回此补丁，因为它也阻断了图标悬停。现由产品层在嵌入展开入口、Agent切换按钮和通知中的角色图标关闭自身TapGesture，保留onHover；外层展开和切换按钮正常接收点击。回归窗口见根目录`Tests/CompactClickChecks`，使用隔离偏好和真实Agent面板，程序仅保持第二阶段的悬停状态；展开及三种Agent的小图标切换通过原生UI点击验收。

11. 0.6.3新增`NookLiveActivity.Alert.compact`与`NookSurfacePresentation.compact`，通过现有表面仲裁只露出第二阶段，不增加peek正文。`compactRevealActive`维持无悬停时的胶囊可见性，结束声明后恢复；同一活动连续完成时延长停留，点击打开该活动详情，主动打开的面板不会被到时收走。隔离原生验收在根目录`verification/completion-capsule/`。

12. 0.6.4在顶部模块入口中，两个模块时使用直接切换按钮，保持当前模块图标、名称和原位置，以双向箭头替代下拉箭头。按钮预留较长标题的宽度，两个方向使用同一点击范围；三个及以上模块仍使用原菜单。设置和详情中的返回入口保持原行为。

升级时应逐项复核这些补丁，运行根目录`scripts/check.sh`及应用`--self-test`，再做实际屏幕拔插验收。上游部分Swift 5并发警告仍保留，不代表已经迁移到Swift 6严格并发模式。

13. 0.7.2新增默认关闭的`NookConfiguration.allowsHorizontalModuleSwipe`，由产品主面板启用。展开路由背景中的AppKit本地滚动事件监视器只接管岛内、带手势阶段的精确横向滚动；方向锁定、阈值、每手势一次和惯性过滤由独立状态机处理。监视器放在模块身份之外，切换时保留手势状态；设置、拖入和活动详情不响应。主面板切换增加轻量方向位移，减少动态时仅淡入淡出。产品提醒标记位于`IslandModuleAttention`和自定义顶栏，不修改上游通用提醒语义。

## 柚子岛待办接入（2026-10-22）

扩展`NookDropPayload`与`onDrop`以接收文字、网页链接及文件；旧`onFileDrop`在未注册新回调时继续有效。AppKit拖入仍由原有状态机处理，取消时恢复原状态。不同活动的提示在`NookActivityCenter`排队，保持当前提示完整显示；同一活动的更新继续合并。产品专用的三个固定图标和到期数量在宿主自定义顶栏实现。

拖入接收限制在岛附近，避免透明窗口误收其他区域的文字与链接。刘海模拟展开时不使用顶边收起遮罩；窗口重建后按主体和伴随内容共同扩展高度，避免高面板被半屏初始窗口裁切。
