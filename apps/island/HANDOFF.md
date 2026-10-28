# 当前源码入口

- 主程序：`Sources/YuIsland`。
- APP模块：`Sources/IslandShell`，其中`Agents`为Agent、`Todos`为待办和日程、`Workspace`为存储与提醒、`Settings`为设置、`Platform`为中台。
- 原生窗口与外壳依赖：`Vendor/OpenNook`；许可证保留。
- 素材：`Resources`和`SettingsWeb/dist`（原生皮肤仍读取其中的图片与JSON）。
- 当前源码不包含用户工作区；安装和源码构建不会提供其他人的登录态。

完成项正文不使用删除线。日程提醒不得打断待办编辑；屏幕提醒需排队。设置页保持清晰层级与足够字号，不恢复旧折叠筛选。行为与界面以当前代码、产品检查和实际原生窗口验收为准。
