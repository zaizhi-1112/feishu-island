# 飞书弹幕
本地 macOS 原生 Swift/AppKit 工具，当前为文豪野犬主题版 0.3.5；Desktop 为跨平台同事试用版 0.4.0。验收目标：个人私聊与群聊均进入桌面弹幕，免打扰按用户规则处理。原通知模式已移除；账号私聊与群聊历史读取已实测；0.3.4 三条真实新消息由用户确认 5–10 秒内显示，但多日运行未验收。
- Sources：应用源码；Tests：消息处理验证；scripts/build.sh：构建本地 .app。
- 使用 `bash scripts/build.sh` 构建，`bash scripts/test.sh` 验证。
- 不记录消息正文到文件，不上传，不读取飞书内部数据库，不擅自扩大授权，不发送消息。
- 通知监听和全量消息接入必须明确区分；未完成真实消息验收不得称全部接通。
- 用户使用说明交付单文件 HTML。范围内修改后同步说明与验证事实。

- tools/lark-cli：本项目内的官方 CLI 1.0.96；scripts/probe-account.mjs：只读账号接入探针。`node scripts/probe-account.mjs --check` 检查配置，`--probe` 在授权后只读抽样验证私聊及群聊，不输出正文、姓名、会话 ID 或密钥。
- 用户已明确批准创建专用飞书应用及私聊、群聊、会话信息只读接入；专用应用已发布且仅本人可用，账号授权已完成；0.3.4 三条连续新消息已现场验收，类别未确认。不擅自申请发送、修改、删除权限。
- 用户身份历史读取与 Bot 实时事件分开验证；全量、免打扰、新消息延迟、分页补偿均需实测，不能由官方文档直接推断已接通。

- Sources/AccountReader.swift：官方 CLI 用户身份轮询；进度、正文、去重 ID 仅内存。全会话列表分页，活跃优先+轮转；消息分页完成才推进时间，失败重试。免打扰默认跳过，按会话名关键词灰色放行，屏蔽优先。不回放启动前历史。
- Tests/account 使用独立合成 CLI 测试接收链路；不得用测试通过代替真实新消息显示验收。

- 0.3.0：Sources/Settings.swift 为 SwiftUI 原生设置面板；App.swift 用原生文字绘制、像素对齐移动与同速间距复用轨道。scripts/icon.swift 生成 AppIcon。账号读取最多并发 3 个，每轮活跃 6 + 轮转 6；轮后间隔可调，失败退避至少 5 秒。Tests/account 的合成 CLI 用文件锁保护测试状态，不接触真实消息。

- 0.3.1：原生面板采用文豪野犬同人档案主题；Assets/dazai-dossier.png 为离线插画，构建时复制至 Resources。插画来源及生成提示词在 Assets/illustration-notes.md；此次仅改主题与窗口布局，账号读取和弹幕渲染逻辑沿用 0.3.0。

- 0.3.2：快查独立读取近期 12 个会话并检查前 6 个，完整会话列表与补读在独立后台队列；无灰色例外时快查仅调用一次免打扰过滤列表。最多 2 个快查读取 + 1 个后台请求。消息通过官方 CLI 的同一只读 GET 接口直接读取，保留毫秒时间、避免线程/媒体扩展；120 秒回看补偿接口晚到，启动前消息过滤，按 ID 去重，重启进度按会话隔离。状态的快查耗时不是送达延迟；App.swift 分别显示真实接收和排队耗时。Tests/latency 验证慢目录不阻塞末尾会话被提升后接收、取消重启和内容解析。

- 0.3.3：Sources/ServerClock.swift 用飞书动态 HTTPS Date 校准查询与消息时间，单调推进，约 5 分钟或检测到墙钟跳变后重校；首次校准失败不静默使用偏差时间。App.swift 接收时间用校准时钟、排队时间用单调时钟。Tests/latency 覆盖本机慢/快 45 秒，不改系统时间。构建可用 DANMU_APP_OUTPUT 指定已移动的实际 .app；使用说明内置 Resources。

- 0.3.4：每个 CLI 请求在退出、解析失败和取消路径显式关闭 stdout/stderr 四个管道句柄，避免长时间轮询耗尽进程文件描述符。失败状态显示接收异常，不冒充正常接收。Tests/stability 验证持续轮询、20 条连续合成消息、空响应恢复及描述符上界；真实持续接收仍需用户现场验证。

- 0.3.5：普通群、话题群、机器人私聊均纳入；通过 +messages-read-status 仅显示确认未读的启动后新消息，未知跳过，不修改飞书已读状态。超过 10 字的正文用完整分页卡片，每页至少 12 秒；待播 500、历史 100，超量移出较早待播并提示。CLI 超时强制退出兜底、首次连接失败重连、每会话去重按成功查询窗口清理。
- Desktop/：Electron 同事版，Mac arm64/x64 与 Windows x64 安装包；本人凭证禁止打包，首次需个人只读应用配置与用户授权。release/site 为虚实中台纯下载页，发布走 get_app_guide/deploy_app。Windows 构建和 Windows 真机验收分开；没有签名/公证证书不得承诺无提示安装。
- 构建保护：通常必须退出 App。DANMU_STAGED_BUILD=1 仅允许输出到本项目 .build/staged-*.app，且检查不能覆盖任何运行中的可执行文件；暂存构建不是已安装或已启动，替换桌面 App 和现场验收仍需退出旧版。

- Web/：2026-10-14 首次引入免安装 Node 网页版，当前为 0.7.1，复用 Desktop 只读接收逻辑。用户同意服务器临时处理本人消息，正文与历史只在内存；官方 CLI 配置与授权凭证按中台身份隔离保存在 /data。无在线页面超过 2 分钟停止读取并清空服务器消息内存。已通过 virxact MCP 部署至 feishu-danmu.virxact.net，仅本人；线上页面和试播验证通过，专用应用配置已交接到 /data，真实飞书网页接入尚待本人授权验收。npm test --prefix Web；本地安全预览：DANMU_WEB_PREVIEW=1 PORT=8768 node Web/server.cjs。预览不读取真实账号；发布仅包含 Web/，禁止打包本机凭证。

- Web 0.6.0：授权成功和打开已授权网页自动接收；用户停止偏好以每账号布尔配置存 /data，刷新/服务重启不自动覆盖。隐藏标签页保持心跳，展示按实际经过时间推进；真实消息打断演示，短消息横移，长消息分页，已读跳过单独计数。外观仅经 appearance-schema.js 的白名单 JSON 导入，以账号隔离存 /data，不接受源码、脚本、CSS 或核心参数。0.6.0 的“复制给 Agent”是当时的手动导入流程，已由下述 0.7.1 本机 MCP 入口替代。scripts/web-autostart.swift 使用 macOS 公开应用启动事件打开网页，不识别飞书账号是否登录；本机 LaunchAgent local.zaizhi.feishu-danmu-web。

- 0.6.0 验证：14 项自动检查、浏览器连续两条合成消息移动/暂停/轮转及真实消息抢占演示通过；线上有效授权自动接收、个人外观保存与刷新恢复通过。新版本真实飞书新消息展示仍待实际到达验收。本机启动联动已加载并运行，未为验收强制退出用户飞书。

- 0.7.1：网页授权、设置与外观继续由 Web 管理，scripts/web-autostart.swift 通过仅监听 127.0.0.1:48763 的 Origin + nonce 桥接复用 Sources/Overlay.swift 原生透明桌面层。飞书公开启动事件打开网页，不检测账号内部登录。scripts/web-autostart.sh 更新本机登录项。
- 禁止用不透明全屏窗口、遮罩或测试背景占用用户桌面；不抢焦点、不拦鼠标，不为验收退出飞书。已删除 --verify-backdrop、验收画布与截图接口。测试优先纯数据与接口，桌面试播只用短暂透明弹幕。
- “接入 Agent”仅保留一个按钮，复制本机外观 MCP 连接说明。scripts/AppearanceMCP.swift 仅提供 read_appearance/update_appearance；独立短期 capability 30 分钟、仅 loopback、拒绝浏览器 Origin，锁屏或网页无心跳 2 分钟撤销。不得把网页桥接 nonce 或消息授权交给 Agent。改动经白名单与对比度验证，浏览器同步至当前账号 /api/appearance 后 ACK，Agent 读到 saved=true 才表示保存成功；网页须保持打开，云端 Agent 无法直连本机。
- 验证：npm test --prefix Web；swiftc scripts/AppearanceMCP.swift Tests/AppearanceMCPTests.swift -o .build/appearance-mcp-tests && .build/appearance-mcp-tests；bash scripts/web-autostart.sh 构建并更新组件。新消息、连续多日运行的实测结论不能从上述合成测试推断。

- 0.7.1 现场验证：virxact 发布 90 live、仅本人；线上按钮复制成功，本机 MCP 修改字号经网页保存并读到 saved=true，核心字段拒绝，原外观已恢复。线上“桌面试播” accepted 从 0 到 1，原生文字可见并向左移动超过 100px，mousePassThrough=true、canBecomeKey=false。未截图任何真实消息；未重启飞书验收启动联动；未完成新版本真实私聊/群聊与多日运行验收。
