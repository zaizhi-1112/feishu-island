# 飞书工作岛 · 一起开发

入口 `/collab/`。无需 GitHub 网页操作，双方各自用公司账号登录。应用仍保持公司登录；只有明确加入的两位成员能读写协作记录。原弹幕入口用 DANMU_OWNER_ID 限制本人。

- 需求：保存描述、进度，点击“交给 Codex”复制任务。
- 版本：发布助手从真实 GitHub PR 同步改动与检查。没有通过检查、冲突或版本过期不能同意。
- 双方同意：绑定具体代码 SHA、主版本 SHA、标题、改动、验证信息。任一变化清空同意。要求修改立即撤销排队。Agent 不能投票。
- 过程：保留讨论、状态变更、两人决策与发布结果。阶段归纳基于这些记录生成，不虚构 Agent 工作进度。
- 上线：Codex 本机 heartbeat 自动检查。使用本机 GitHub 登录与虚实中台 MCP；凭证不上传。先构建并验证，再合并批准代码、发布 Mac 下载与网页版，分别核实。两种结果都存在才标记成功。不会自动安装 Mac 更新。
- 自动化需要负责人电脑上的 Codex 可运行并保持中台登录；否则任务等待。检查间隔 1 分钟，构建时间另计。不是每次点击立即完成。

`COLLAB_OWNER_ID`、`DANMU_OWNER_ID` 是平台稳定用户 ID；不得用昵称替代。新增伙伴通过申请与负责人确认完成绑定，分享范围只加柚子。发布 capability 只允许同步、领取与报告，不能同意。签名防篡改与重放，持久文件在 `/data/collab`。

本地预览：设置 COLLAB_PREVIEW=1、DANMU_WEB_PREVIEW=1、DANMU_DATA_DIR 指向独立目录，以端口 8772 启动 Web/server.cjs。`?actor=b` 仅在此本地模式中切换合成伙伴。生产拒绝预览。测试：`npm test --prefix apps/danmu/Web`。

发布自动化按仓库 scripts/collab-sync.mjs 生成签名同步请求，经已登录的同源浏览器转发，不复制公司登录 Cookie。scripts/collab-envelope.cjs 签名 claim/result；scripts/collab-runner.mjs 验证 claim 响应签名、针对批准 SHA 构建并发布 Mac 版，把结果写入文件。网页版必须继续走 virxact MCP 正式入口，不能自行找 SSH 或公司私有发布接口。

发布失败保留构建目录和记录，不盲目重试。Mac Release 用确定的批准 SHA 标签；同名版本来源不同立即停止。已领取任务不被重复领取；执行中断须让 Codex 核对 GitHub 与中台的实际结果再恢复，不能直接标记成功。
