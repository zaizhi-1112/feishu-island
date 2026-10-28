# 一切在岛 0.10.0 build82

macOS桌面APP：飞书消息、Agent状态、待办与提醒、中台入口和原生设置。当前只使用悬浮模式。

本目录为APP完整源码：原生代码、资源、依赖源码与许可证、测试和构建打包脚本。没有聊天记录、个人配置、任务数据、修复备份、逐轮工作记录、旧弹幕项目或协作平台。独立网页授权服务、浏览器扩展及历史宣传网站不属于本源码包。

## 构建

macOS 15+，Swift工具链与兼容macOS SDK。本机验证使用macOS 26.5 SDK；按本机实际环境设置路径。

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
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks
python3 Tests/package-pilot-test.py
python3 scripts/package-pilot.py dist/一切在岛.app --output releases
shasum -a 256 -c SOURCE-MANIFEST.sha256
```

主程序与build82已验证的原生代码、资源一致；本源码包只调整了构建时许可证和图标输出的路径，使其可独立构建。此前产品、融合、Agent、待办及飞书检查已通过；多日运行、Intel及其他同事首次授权仍待验证。
