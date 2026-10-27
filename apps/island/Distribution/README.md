# 一切在岛安装入口

公司入口为 https://feishu-island.virxact.net/ ，中台名称“一切在岛”、通用分类、宰治和柚子共同发布，沿用全公司可见，需公司飞书登录。使用本人新指定的云朵插画透明图标，提取提示词与来源见 `artwork/README.md`。下载页与既有公司授权服务同站部署，沿用环境变量和/data；不读取或导出服务器凭据。

`site/` 按本人指定的 [DeepSeek Harness](https://www.deepseek.com/harness/) 参考页调整为统一深色产品页：居中标题、浅色下载按钮、大幅单框四入口轮播。每个入口一句话加示意演示，详细安装说明通过链接查看。复用虚实字体、色彩变量与图标；本页固定深色、居中限宽与胶囊按钮遵循本次指定参考，不采用早先工具页布局。2026-10-27 发布至中台，release 414 为 live。详细阅读帮助为 `开始使用.html`；`site/agent-guide.html` 已对齐只读 Agent 状态、自定义 JSON 与主动导出待办。旧网页工作台、材料/AI 派单、Dot 隧道、项目/外观 MCP、签到与网页收录不再作为当前版功能宣传。服务保留旧授权协议兼容；授权页明确当前桌面版只需消息接收。

当前安装包为 0.9.0 build 53，与本机交付的 DMG 保持同一哈希 `24b16dca2415b88f705b9b8d652c020bd243030717b732cca56034cf073da87c`；包内应用名为“一切在岛”。DMG 只展示 App 与 Applications 拖入目标；仅包含官方 CLI、中台授权与 Agent 状态三个 helper。未完成 Developer ID 签名或 Apple 公证，各同事的真实授权和长期运行仍需本人设备核对。

```sh
python3 apps/island/scripts/package-pilot.py /absolute/path/to/application.app
python3 apps/island/scripts/package-download-site.py /absolute/path/to/feishu-island-0.9.0-build53-arm64.dmg .build/new-download-output
python3 apps/island/scripts/package-auth-service.py .build/new-download-output .build/new-service-output
```

输出目录必须尚不存在。第一步白名单审计、检查全部 helper 架构和签名、构建 DMG、只读挂载核对文件哈希与 Finder 布局后卸载，输出旁置 `package-manifest.json` 和 `SHA256SUMS`；第二步核对版本、清单、DMG 哈希与页面，再复制公开文件；第三步加入既有授权服务源码。只经 virxact MCP `deploy_app` 发布最后的服务输出目录，不上传仓库、本机工作区、profile、Dot 配对或 .env，沿用全公司可见范围。

验证入口：`python3 apps/island/Tests/package-auth-service-test.py`、`node --test apps/island/AuthService/*.test.cjs`。历史服务基线的 27 项服务检查与 3 项托管帮助检查通过；当前主页面不再设置常见问题和独立安装区块。release 406 的网页与线上 SHA256SUMS 已在真实入口核对；最终安装包线上浏览器下载核验遇到超时，不能以先前 release 405 的下载结果代替。托管帮助仅使用外部 CSS/JS，保持 CSP 的 self 限制；合成和开发者检查不替代同事实际账号和设备验收。

2026-10-27 精简发布页：桌面、390 px、深色模式与键盘页签切换检查通过；27 项服务与 3 项托管帮助检查通过。轮播支持暂停、悬停/聚焦暂停和减少动态效果。安装包沿用 build53，不包含其他正在开发的原生改动。

下载按钮位于首屏正中，点击区域 220×54 px。当前版本检查：1440 px 桌面与 390 px 手机无横向溢出；页签/方向键、自动轮播、暂停与减少动态效果均通过；系统浅色/深色设置下均保持深色页面。设计检查 0 错误、0 提醒；3 项托管帮助检查通过。发布包基于线上 release 410 的冻结服务，仅 index.html 和 landing.css 字节变化，未带入并行开发中的日历授权或原生改动。
