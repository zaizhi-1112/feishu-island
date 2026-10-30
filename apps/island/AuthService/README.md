# 飞书工作岛公司授权服务

已获本人批准，部署目标沿用 island.example.invalid，现按本人2026-10-25要求向全公司开放，仍需公司账号登录。公司登录由中台入口负责，本服务只办理两套专用飞书应用的个人业务授权。

## 运行和校验

Node 22+，无第三方依赖；`node --test apps/island/AuthService/*.test.cjs`。
发布目录只包含 server.cjs、core.cjs、desktop.cjs、package.json、package-lock.json、virxact.json 和 public。本轮从现有服务的完整发布目录复制，保留原 public 下载资源，仅替换 core.cjs。可通过 `ISLAND_DOWNLOAD_SITE=/absolute/path/to/staging/public node --test AuthService/*.test.cjs` 核对待发布的真实资源；不要用本目录的连接页覆盖现有下载页。

环境变量通过 virxact set_app_env 配置：FEISHU_RECEIVE_SECRET、FEISHU_ARCHIVE_SECRET、AUTH_VAULT_KEY（32 字节随机值的 base64）。不得再次生成并覆盖现有 AUTH_VAULT_KEY，否则现有加密记录无法读取。凭据按中台稳定用户 ID 与用途分开，加密写入 /data/auth；不保存消息正文或材料。不记录请求或上游原始响应。

设备授权实现依据官方 larksuite/cli v1.0.96 的 device_flow.go 与 uat_client.go，代码独立实现，无复制其源码。固定 scope 不从页面接收，也不使用 CLI 的全部领域授权。start/poll/cancel 只接受当前公司登录身份与同源请求，设备头不接受；轮询仅由本人启动授权后产生，按官方 interval 最低 5 秒，完成/取消后停止。

## 证据边界

32 项 Node 合成测试覆盖加密隔离、越权、取消、过期、精确权限、CSRF、设备拒绝、续期与保存失败、临时令牌返回边界与身份核验。网页本人归档授权已实际保存，公司凭据经官方 CLI 新建合成文档并回读两条反馈成功。

Mac 自己的持久 WKWebView 先走公司登录，只有精确同源 POST + X-Island-Auth 才能取得选定用途的短期访问令牌；不返回 refresh 或 App Secret，不开放 API 代理。每次新令牌通过飞书 user_info 核对身份，客户端固定首次绑定的中台 ID 和各用途 open_id；切账号后拒绝沿用。此核验不等于证明中台与飞书账号属于同一自然人，首次授权仍须本人核对页面。

Mac 不复制已登录浏览器 Cookie，不使用公共设备钥匙。官方 CLI 1.0.96 实际支持 LARKSUITE_CLI_USER_ACCESS_TOKEN 和 APP_ID 的 token-only env provider（默认分发已注册）；此前“无外部令牌入口”的调查结论已被实际源码与二进制检查纠正。auth status/check 在该模式不可调用，App 使用已核对身份与固定权限集合处理这两项检查。其他消息、文档与附件命令沿用原组件。

Mac 内置公司登录窗口与同事本人设备尚待真实验收。build83 恢复应用内的直接授权入口。公司登录过期应提示本人登录，不擅自延长授权；保存失败的兑换结果仅可在当前服务进程内重试持久化，磁盘故障并伴随进程重启仍可能需重新授权。没有真实跨天续期结论。

静态资源验收：更换首页时，必须通过download.test.cjs中基于实际首页引用资源的HTTP检查；文件打进public不代表PUBLIC_ASSETS已放行。新增资源继续按名称显式允许，不开放任意目录。

## build83 的只读日历

新客户端的日历按钮使用 `schedule` 用途，仅请求身份、日历和日程读取及续期；旧 `calendar` 用途保留供旧客户端使用，两个用途的加密记录独立。服务必须核对实际返回 scope；旧的较宽授权须经官方续期接口收窄后才可返回，不能仅修改 scope 标签。

本轮获得授权的发布仅替换现有服务 core.cjs，下载页与 18 个公开资源逐文件相同。线上部署编号和本机验收更新于 ../../../docs/build82-refinements.md。
