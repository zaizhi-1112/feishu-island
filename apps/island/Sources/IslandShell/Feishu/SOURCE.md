# 飞书消息来源与边界

`AccountReader.swift`、`ServerClock.swift`和`Tests/FeishuReaderChecks`改编自用户提供的《飞书弹幕-0.7.1-源码与协作说明-2026-10-17》中的原生Swift接收器及测试。原始压缩包保留在桌面，研究副本与SHA-256清单见`research/feishu-danmaku-review-2026-10-18`。

本地改动：复用默认CLI账号；保留结构化会话、消息与@字段；通过原始只读查询兼容旧CLI；未知阅读状态不写入去重并保留进度重试；独立岛模块、重要规则、内存列表、静音及本次运行的稍后提醒。

已读查询使用POST `/open-apis/im/v1/messages/read_status`，请求体为`message_ids`数组；该POST是查询，并非标记已读。路径与请求体核对了原包CLI的`im +messages-read-status --dry-run`，并用现有CLI和真实账号成功读取。

打开会话按飞书官方AppLink：
https://open.feishu.cn/document/uAjLw4CM/uYjL24iN/applink-protocol/supported-protocol/open-a-chat-page

使用`https://applink.feishu.cn/client/chat/open?openChatId=oc_...`，交给本机飞书应用；`oc_` 是 Open Chat ID，不能放进客户端数字编号 `chatId` 参数。不承诺定位到单条消息。

参数区分同时核对官方 CLI 的 [AppLink 说明](https://github.com/larksuite/cli/blob/main/skills/lark-im/SKILL.md)，2026-10-29。

交接包未授予公开再分发许可；本次仅为用户个人项目融合，未发布源码或应用到公共平台。
