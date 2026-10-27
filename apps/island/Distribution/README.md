# 一切在岛安装入口

公司入口为 https://feishu-island.virxact.net/ ，中台名称“一切在岛”、通用分类、宰治和柚子共同发布，沿用全公司可见，需公司飞书登录。使用本人新指定的云朵插画透明图标，提取提示词与来源见 `artwork/README.md`。下载页与既有公司授权服务同站部署，沿用环境变量和/data；不读取或导出服务器凭据。

`site/` 沿用虚实叙事页设计，提供当前DMG、四模块介绍、三步安装和折叠帮助。详细阅读帮助为 `开始使用.html`；`site/agent-guide.html` 已对齐只读Agent状态、自定义JSON与主动导出待办。旧网页工作台、材料/AI派单、Dot隧道、项目/外观MCP、签到与网页收录不再作为当前版功能宣传。服务保留旧授权协议兼容；授权页明确当前桌面版只需消息接收。

当前安装包为0.9.0 build52，与本机已验收的DMG保持同一哈希 `fea253722acf87bd23f474609ae59b13f501b6189c76bac823f3d966c766c161`。此次中台发布不重编译或改动安装包，包内应用仍叫“你的飞包”，页面已明确安装名称。DMG只展示App与Applications拖入目标；仅包含官方CLI、中台授权与Agent状态三个helper。未完成Developer ID签名或Apple公证，各同事的真实授权和长期运行仍需本人设备核对。

```sh
python3 apps/island/scripts/package-pilot.py /absolute/path/to/application.app
python3 apps/island/scripts/package-download-site.py /absolute/path/to/feishu-island-0.9.0-build52-arm64.dmg .build/new-download-output
python3 apps/island/scripts/package-auth-service.py .build/new-download-output .build/new-service-output
```

输出目录必须尚不存在。第一步白名单审计、检查全部 helper 架构和签名、构建 DMG、只读挂载核对文件哈希与 Finder 布局后卸载，输出旁置 `package-manifest.json` 和 `SHA256SUMS`；第二步核对版本、清单、DMG 哈希与页面，再复制公开文件；第三步加入既有授权服务源码。只经 virxact MCP `deploy_app` 发布最后的服务输出目录，不上传仓库、本机工作区、profile、Dot 配对或 .env，沿用全公司可见范围。

验证入口：`python3 apps/island/Tests/package-auth-service-test.py`、`node --test apps/island/AuthService/*.test.cjs`。27项服务、3项托管帮助/打包检查和设计扫描通过；实际核对桌面/390px、下载及哈希、托管帮助的21/23px字号切换。托管帮助仅使用外部CSS/JS，保持CSP的self限制。发布后还需打开真实入口与下载核验；合成和开发者检查不替代同事实际账号和设备验收。
