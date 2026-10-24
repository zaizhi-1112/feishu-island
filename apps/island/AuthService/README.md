# 飞书工作岛公司授权服务

已获本人批准，部署目标沿用 feishu-island.virxact.net，仍仅作者和柚子可见。公司登录由中台入口负责，本服务只办理两套专用飞书应用的个人业务授权。

## 运行和校验

Node 22+，无第三方依赖；`node --test apps/island/AuthService/*.test.cjs`。
通过 `scripts/package-auth-service.py` 把审计后的下载目录与服务源码合成独立发布目录；只包含 server.cjs、core.cjs、desktop.cjs、package.json、package-lock.json、virxact.json 和 public。

环境变量通过 virxact set_app_env 配置：FEISHU_RECEIVE_SECRET、FEISHU_ARCHIVE_SECRET、AUTH_VAULT_KEY（32 字节随机值的 base64）。不得再次生成并覆盖现有 AUTH_VAULT_KEY，否则现有加密记录无法读取。凭据按中台稳定用户 ID 与用途分开，加密写入 /data/auth；不保存消息正文或材料。不记录请求或上游原始响应。

设备授权实现依据官方 larksuite/cli v1.0.96 的 device_flow.go 与 uat_client.go，代码独立实现，无复制其源码。固定 scope 不从页面接收，也不使用 CLI 的全部领域授权。start/poll/cancel 只接受当前公司登录身份与同源请求，设备头不接受；轮询仅由本人启动授权后产生，按官方 interval 最低 5 秒，完成/取消后停止。

## 证据边界

18 项 Node 合成测试覆盖加密隔离、越权、取消、过期、精确权限、CSRF、设备拒绝、续期与保存失败、临时令牌返回边界与身份核验。网页本人归档授权已实际保存，公司凭据经官方 CLI 新建合成文档并回读两条反馈成功。

Mac 自己的持久 WKWebView 先走公司登录，只有精确同源 POST + X-Island-Auth 才能取得选定用途的短期访问令牌；不返回 refresh 或 App Secret，不开放 API 代理。每次新令牌通过飞书 user_info 核对身份，客户端固定首次绑定的中台 ID 和各用途 open_id；切账号后拒绝沿用。此核验不等于证明中台与飞书账号属于同一自然人，首次授权仍须本人核对页面。

Mac 不复制已登录浏览器 Cookie，不使用公共设备钥匙。官方 CLI 1.0.96 实际支持 LARKSUITE_CLI_USER_ACCESS_TOKEN 和 APP_ID 的 token-only env provider（默认分发已注册）；此前“无外部令牌入口”的调查结论已被实际源码与二进制检查纠正。auth status/check 在该模式不可调用，App 使用已核对身份与固定权限集合处理这两项检查。其他消息、文档与附件命令沿用原组件。

Mac 内置公司登录窗口与同事本人设备尚待真实验收。当前日用 build26 未改；build28 为独立构建。公司登录过期应提示本人登录，不擅自延长授权；保存失败的兑换结果仅可在当前服务进程内重试持久化，磁盘故障并伴随进程重启仍可能需重新授权。没有真实跨天续期结论。
