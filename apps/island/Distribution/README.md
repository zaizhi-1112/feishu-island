# 飞书工作岛下载入口

发布目标：feishu-island.virxact.net，名称飞书工作岛，通用分类，用户指定的蓝绿工作岛图标（brand/work-island-original.png）。本人已确认仅宰治和柚子（史天佑）可见。纯静态下载页，不是账号授权后台，不处理消息或凭据。

源文件在 site/；virxact-ui.css 与 vx.js 来自 virxact-design，保持原样。安装包来自 package-pilot.py 的独立产物。运行：

```sh
python3 apps/island/scripts/package-download-site.py /absolute/path/to/pilot.zip .build/new-download-output
```

输出目录必须尚不存在；脚本检查 ZIP CRC、版本/架构清单，复制网站、试用说明、版本化 ZIP 与 SHA256SUMS。发布只打包这个输出目录，经 virxact MCP deploy_app 获取一次性上传地址；在上传前 set_app_access 为 people/柚子。禁止整个仓库、个人材料、CLI profile、Dot 配对或 .env 混入。

本页明确首次授权与同事 Dot 连接引导仍未完成。上线下载入口不等于同事已经接通或飞书工作台应用入口已配置。本轮独立分发包为 build27（更新图标），本人运行版本仍为 build26，不能以静态页上线冒充新版运行逻辑。

图标原图由宰治提供，保留原始样式。`bash apps/island/scripts/build-app-icon.sh` 生成 Mac ICNS 和入口 PNG，不替换运行中的应用。build27 仅包含图标更新，飞书、Dot 和归档实现保持 build26；首次无命令行授权仍依赖待配置的公司授权服务，不能宣称同事已接通。

实际发布：release245 为 live；授权范围仍仅作者和柚子，无设备凭据、无服务环境变量。公网登录后页面实际显示 build27 和指定 PNG。当前 ZIP SHA-256：3400b00fa0268de7f18ffe32574ed1e0531636d025aa4db8596cbe29bb44caee。
浏览器实际点击下载，文件 SHA-256 与原包一致、ZIP CRC 全部通过。
