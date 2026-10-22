# 飞书工作岛下载入口

发布目标：feishu-island.virxact.net，名称飞书工作岛，通用分类，胶囊图标。本人已确认仅宰治和柚子（史天佑）可见。纯静态下载页，不是账号授权后台，不处理消息或凭据。

源文件在 site/；virxact-ui.css 与 vx.js 来自 virxact-design，保持原样。安装包来自 package-pilot.py 的独立产物。运行：

```sh
python3 apps/island/scripts/package-download-site.py /absolute/path/to/pilot.zip .build/new-download-output
```

输出目录必须尚不存在；脚本检查 ZIP CRC、版本/架构清单，复制网站、试用说明、版本化 ZIP 与 SHA256SUMS。发布只打包这个输出目录，经 virxact MCP deploy_app 获取一次性上传地址；在上传前 set_app_access 为 people/柚子。禁止整个仓库、个人材料、CLI profile、Dot 配对或 .env 混入。

本页明确首次授权与同事 Dot 连接引导仍未完成。上线下载入口不等于同事已经接通或飞书工作台应用入口已配置。主程序仍为 build26，不能以静态页上线冒充新版运行逻辑。
