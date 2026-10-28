# APP中的Agent接入

当前实现位于`Sources/IslandShell/Agents`，状态辅助程序源码位于`scripts/agent-status-helper.swift`。从APP设置中的“接入Agent”取得当前提示词并按工具能力接入；账号凭据由各工具自行管理，不放入源码或交付包。

配置读取失败时，APP暂停相关监测和写回；先导出或修复配置，不自动覆盖。具体接口与验证以`AgentHookProtocol.swift`、`AgentBridge.swift`和`Tests/AgentTests`为准。
