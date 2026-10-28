# 一切在岛 0.11.1 build90

macOS桌面APP：飞书消息、Agent状态、待办与提醒、中台入口和原生设置。当前只使用悬浮模式。

本目录为APP完整源码：原生代码、资源、依赖源码与许可证、测试和构建打包脚本。没有聊天记录、个人配置、任务数据、修复备份、逐轮工作记录、旧弹幕项目或协作平台。AuthService 提供现有公司登录下的飞书业务授权；不含凭据和下载安装包。

## 构建

macOS 15+，Swift工具链与兼容macOS SDK。本轮验证使用macOS 26.4 SDK；按本机实际环境设置路径。

```sh
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
# 编译APP主程序
swift build --disable-sandbox --sdk "$ISLAND_SDK" -j 2 -c release --product YuIsland
# 打包.app：需要从官方渠道取得lark-cli可执行文件（build82安装包内置1.0.98）
export ISLAND_LARK_CLI="/absolute/path/to/official/lark-cli"
bash scripts/build.sh
```

输出为`dist/一切在岛.app`。Vendor包含所需Swift依赖与第三方许可证，构建不依赖弹幕子项目、网页服务或个人文件。安装包适用于Apple芯片Mac，尚未做Apple公证；每位使用者需要自己的账号授权。

## 检查与打包

```sh
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks --skin-preview
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 FusionChecks --skin-preview
node --test AuthService/*.test.cjs
python3 Tests/package-pilot-test.py
# 打包工具需 ds_store==1.3.1、mac_alias==2.2.2（建议在独立 venv 中安装）
python3 scripts/package-pilot.py dist/一切在岛.app --output releases
# 网站发布准备：包内容、SHA、版本与内置说明必须一致；不上传个人数据
python3 scripts/package-download-site.py /path/to/audited.dmg .build/site-release

```

本轮基于柚子的 build82 修复会话打开、接收调度、长消息弹幕、日程同步、待办历史与设置交互。普通用户点击「连接飞书」直接进入本人授权，日历使用只读的 `schedule` 用途。原本已绑定的本机账号保持可用。

当前事实、验收边界与安装结果见 ../../docs/build82-refinements.md；面向用户的离线说明为 Distribution/开始使用.html。SOURCE-MANIFEST.sha256 是 build82 导入快照，不能用作修改后源码的校验清单。

build84 修复完整展开时向上移入硬件刘海导致误收回的问题；点击区域不覆盖两侧菜单栏。新增向上移动、停在顶边、侧向离开和快速重复进出的原生回归检查。


build85 使用 openChatId 打开飞书会话。快捷轮盘为透明圆盘，默认首页、OKR、资料、数据、异常项、应用、Skill、审批；设置中拖动入口分配方向，支持本人中台常用应用和本机设置。计划卡片只保留一个“工作计划”标题；弹幕支持直接选色以及独立的背景、边线开关。中台 helper 新增只读 list_home_applications，应用入口仅在内存缓存，凭据仍由原独立 helper 服务持有。


build86 补齐快捷键轮盘手势：轻按唤出后滑出目标方向外圈打开；按住快捷键滑向目标，松开打开；保留点击和按住鼠标拖选。方向高亮与鼠标/快捷键共用几何，回中央松键取消；屏幕边缘初始落点、重复事件和鼠标拖选不会误触发。鼠标监听只在轮盘显示期间存在。build85 会话跳转已由本人确认能进入正确聊天。


build87 新增默认 DeepSeek Harness 入口与 DeepSeek 官方蓝色鲸鱼主题。复用本人 Harness 的既有登录，只读账户余额和赠送余额，每3分钟刷新；不读取对话、不派发任务、不存储或输出凭据。新入口不会自动替换已有岛上位置，也不会在其他使用者电脑上自动启用。


build88 新增首次使用的六步原生引导：移入方式、外观、飞书连接、桌面弹幕、提醒预览、Agent 选择。图标跟随当前操作，支持返回、跳过和重新体验。升级保留已有设置，新安装未选择的 Agent 不会自动读取。DMG 下方包含 macOS 26.4.1 实际拦截截图和「仍要打开」位置示意；打包时根据实际磁盘生成 Finder 背景引用。安装实测和发布记录见 ../../docs/build88-installation.html。


build89 将默认冲屏素材换为用户提供的透明「猫咪走动」，新增 What a Day 与 Gemini 人物视频。内置和导入素材均可删除；使用中的引用自动换用剩余素材，删空后保留原时间并改为岛内文字提醒。删除状态持久保存，内置素材仅手动恢复；原下载文件不变。

build90 将内置视频副本压缩至中台50 MB发布限制以内，保留完整时长与透明通道；原始素材不改动。下载打包增加体积预检，避免上传后才失败。
