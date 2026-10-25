# 飞书工作岛安装入口

公司入口为 https://feishu-island.virxact.net/ ，名称“飞书工作岛”、通用分类、宰治指定蓝绿图标，现向全公司同事开放，需公司飞书登录。下载页与现有公司授权服务同站部署，服务身份、环境变量和 /data 不随页面改动改变。

`site/` 是精简安装页：一个 DMG 下载入口、一个“复制交给 Agent”、三条默认折叠帮助。详细阅读帮助为 `开始使用.html`；Agent 的操作指引为 `site/agent-guide.html`，只含公开操作路径，没有令牌，也不自动授予权限。外观与项目 MCP 仍使用本机各自受限入口。

当前发布包为 0.8.0 build47，沿用build47功能，统一“飞书工作岛”名称，并更新胶囊消息图标、产品介绍页和共同发布署名；独立授权和签到helper的签名字节保持。DMG 只展示 App 与 Applications 拖入目标，网页收录扩展保留在应用的 `Contents/Resources/BrowserBridge/chrome-reader` 内。校验清单在 DMG 旁，用户无需处理 JSON 或额外文件夹。未完成 Developer ID 公证，不承诺首次无系统来源提示；各人的飞书和 Dot 授权仍需本人完成。

```sh
python3 apps/island/scripts/package-pilot.py /absolute/path/to/application.app
python3 apps/island/scripts/package-download-site.py /absolute/path/to/feishu-island-0.8.0-build47-arm64.dmg .build/new-download-output
python3 apps/island/scripts/package-auth-service.py .build/new-download-output .build/new-service-output
```

输出目录必须尚不存在。第一步白名单审计、检查全部 helper 架构和签名、构建 DMG、只读挂载核对文件哈希与 Finder 布局后卸载，输出旁置 `package-manifest.json` 和 `SHA256SUMS`；第二步核对版本、清单、DMG 哈希与页面，再复制公开文件；第三步加入既有授权服务源码。只经 virxact MCP `deploy_app` 发布最后的服务输出目录，不上传仓库、本机工作区、profile、Dot 配对或 .env，沿用全公司可见范围。

验证入口：`python3 apps/island/Tests/package-pilot-test.py`、`node --test apps/island/AuthService/*.test.cjs`。还需实际检查页面、下载及 Finder 拖拽窗口；合成和开发者验证不替代史天佑本人设备验收。历史 ZIP 发布与真实归档记录保留在根 README/AGENTS 和验收文档。
