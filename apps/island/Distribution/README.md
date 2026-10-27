# 一切在岛安装入口

公司入口为 https://feishu-island.virxact.net/ ，中台名称“一切在岛”、通用分类、宰治和柚子共同发布，沿用全公司可见，需公司飞书登录。使用本人新指定的云朵插画透明图标，提取提示词与来源见 `artwork/README.md`。下载页与既有公司授权服务同站部署，沿用环境变量和/data；不读取或导出服务器凭据。

`site/` 是一切在岛的产品介绍与下载页。当前采用明亮留白、居中下载、首屏动态演示的布局。页面先说明“Mac 顶部工作台”和四个功能，再用单个演示框展示收起、展开、消息阅读、Agent 进度完成、待办完成与中台入口。功能可以自动轮播，也可直接选择；没有独立安装区块，详细内容从“使用指南”进入。当前中台发布为 release 416。

本次研究参考：[Things](https://culturedcode.com/things/) 的产品说明与留白、[CleanShot](https://cleanshot.com/) 的主行动与用途演示、[Alcove](https://tryalcove.com/) 的可交互灵动岛；另阅读 [Screen Studio](https://screen.studio/) 的首屏产品/下载结构，浏览器访问该站失败，不把它记为视觉验收。实现使用自己的品牌、文案和合成示例，未复制参考站的媒体或源码。没有用户量、评分等未经证实的宣传信息；尚无转化率提升的测量结论。

当前浅色下载页覆盖早先的中台卡片及 DeepSeek 深色方案；仍复用虚实字体、图标与颜色变量。演示只用页面本地状态，不连接真实聊天或账号。减少动态效果时展示静态内容并隐藏自动播放按钮；切换到后台或演示离开可视区时停止计时。旧网页工作台、材料/AI 派单、Dot 隧道、项目/外观 MCP 不作为当前版功能宣传。

当前安装包为 0.9.0 build 53，与本机交付的 DMG 保持同一哈希 `24b16dca2415b88f705b9b8d652c020bd243030717b732cca56034cf073da87c`；包内应用名为“一切在岛”。DMG 只展示 App 与 Applications 拖入目标；仅包含官方 CLI、中台授权与 Agent 状态三个 helper。未完成 Developer ID 签名或 Apple 公证，各同事的真实授权和长期运行仍需本人设备核对。

```sh
python3 apps/island/scripts/package-pilot.py /absolute/path/to/application.app
python3 apps/island/scripts/package-download-site.py /absolute/path/to/feishu-island-0.9.0-build53-arm64.dmg .build/new-download-output
python3 apps/island/scripts/package-auth-service.py .build/new-download-output .build/new-service-output
```

输出目录必须尚不存在。第一步白名单审计、检查全部 helper 架构和签名、构建 DMG、只读挂载核对文件哈希与 Finder 布局后卸载，输出旁置 `package-manifest.json` 和 `SHA256SUMS`；第二步核对版本、清单、DMG 哈希与页面，再复制公开文件；第三步加入既有授权服务源码。只经 virxact MCP `deploy_app` 发布最后的服务输出目录，不上传仓库、本机工作区、profile、Dot 配对或 .env，沿用全公司可见范围。

验证：设计检查 0 错误/0 提醒，JavaScript 语法与本次文件的 Git 空白检查通过。1440 px 桌面与 390 px 手机无横向溢出，首屏可见下载和演示；收起 180×32、展开、自动换页、暂停、重播、方向键、减少动态效果均在浏览器核对。使用正式服务的 CSP 和合成身份进行本地浏览器检查，安装包、帮助与校验链接均返回 200。真实用户的消息接收、授权与多日运行不属于网页演示验收。

本次发布以已上线 release 414 的冻结服务为基线，只替换 `public/index.html`、`public/landing.css`、`public/install.js`。安装包 SHA-256、授权服务、环境和 /data 不变，未带入并行开发中的原生及日历授权改动。服务器安装包全量下载并重新计算哈希仍沿用此前未完成的状态；本次不以网页/HEAD 验证代替全量下载核验。
