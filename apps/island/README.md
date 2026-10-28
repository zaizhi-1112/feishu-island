# 一切在岛 0.10.2 build84

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
python3 scripts/package-pilot.py dist/一切在岛.app --output releases

```

本轮基于柚子的 build82 修复会话打开、接收调度、长消息弹幕、日程同步、待办历史与设置交互。普通用户点击「连接飞书」直接进入本人授权，日历使用只读的 `schedule` 用途。原本已绑定的本机账号保持可用。

当前事实、验收边界与安装结果见 ../../docs/build82-refinements.md；面向用户的离线说明为 Distribution/开始使用.html。SOURCE-MANIFEST.sha256 是 build82 导入快照，不能用作修改后源码的校验清单。

build84 修复完整展开时向上移入硬件刘海导致误收回的问题；点击区域不覆盖两侧菜单栏。新增向上移动、停在顶边、侧向离开和快速重复进出的原生回归检查。
