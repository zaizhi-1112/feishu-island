# build116：按钮点击与弹幕关闭

2026-11-05，基于已发布的 build115 开发 0.12.22 build116 候选。本轮用户反馈岛上按钮偶尔点不动、需要重复点，并要求看完后能立即关闭飘动中的弹幕。

## 变化

- 顶部消息、Agent、待办、中台、小锁与设置按钮显式使用完整矩形点击区域，覆盖图标、文字和周围留白；按下改变透明度，不移动按钮。共用 `IslandButtonStyle` 同样补齐点击区域。导航尺寸和模块切换方式保持。
- 每条移动弹幕右下角常驻 ×，点击立即关闭当前条。按钮有 30×30pt 点击区域，支持非激活窗口的首次点击；无气泡时采用深色底，保持关闭图标可辨认。
- 鼠标移入即停留，避免追着关闭按钮跑；移开继续。原来的点击停留保留。图片悬停、整条消息悬停和点击停留分别保存，图片局部离开不会覆盖其他暂停原因。
- 关闭只从正在展示的集合移除当前条，并调用既有 `onFinished` 移除该条待播状态；不修改岛内原文或飞书已读状态。重复关闭无效，后面的消息和队列保留。
- 后续消息仍保持同轨间距。演示和无飞书会话的 Agent 提醒同样可以关闭；没有消息 ID 时不伪造完成 ID。
- 设置提示和随包 `开始使用.html` 同步新操作。

## 已验证

使用独立 `--skin-preview` 偏好、合成消息及未上屏的原生窗口；未读真实消息，未退出或重启飞书。

```sh
cd apps/island
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks \
  --skin-preview --button-interactions-only \
  --render-button-interactions .build/button-interactions
.build/debug/UnifiedProductChecks --skin-preview
```

- 21 项交互检查通过：移入暂停、同轨防重叠、关闭按钮边缘命中、仅关闭当前条、队列保留、关闭幂等、全局暂停时关闭、演示关闭、岛内内容与阅读状态保留、导航尺寸和首次点击配置。
- 485 项完整产品合成检查通过，包含 28 项消息连续性检查。
- 生产构建、应用图标生成及 `codesign --verify --deep --strict` 通过。候选为 0.12.22 build116；与本机 build115 逐文件比较，仅主程序、Info.plist、随包使用说明及对应签名不同，无增删文件，三个 helper 及其他文件字节一致。
- 单文件使用说明的目录与字号按钮已点验；桌面 1366px / 正文 21px、窄屏 390px / 放大字号 23px 均无页面横向溢出，实际截图已查看。
- 生产副本的 272 个 Swift 文件逐项核对，只有三个未改动的连接文件使用上一生产版本的服务地址。
- 深浅两种弹幕外观及导航栏离屏渲染已查看。交互测试日志和图片保留于本 worktree 的 `apps/island/.build/`，不上传。

## 候选与边界

候选输出位于本 worktree 的 `.build/interaction-candidate/一切在岛.app`。生产副本只在被忽略的 `.build/interaction-production/` 中保留上一已安装版本的三个连接源文件；公开源码继续使用占位地址。官方 CLI、中台 helper 和 Agent helper 复用当前 build115 的相同文件，避免本次交互改动触及既有连接组件。

本机 build115 应用回退副本已保存于本 worktree 的 `.build/local-install-backups/interactions-20261105/一切在岛-build115.app`，深度签名验证通过；没有移动当前应用或读取个人消息文件。

截至记录时，本机仍运行 `/Applications/一切在岛.app` build115。未安装候选，未主动启动新一轮真实账号接收，未新建登录项、发布 GitHub Release 或修改中台，未合并 main。开发分支同步依照已有授权执行；不代表正式上线批准。

离屏事件投递探针不能触发 SwiftUI 的实际点击，已移除该探针；没有把它当作按钮实机验收。顶部整块按钮、跨应用第一下点击、弹幕移入到 × 的完整鼠标路径，需要安装后在实际窗口验证。真实新消息与长期运行仍待实际观察。
