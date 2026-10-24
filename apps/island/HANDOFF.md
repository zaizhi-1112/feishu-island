# 当前共同基线

本次已在 `codex/integrate-youzi-075` 整合双方代码，版本0.8.0 build35。当前接续与真实验证边界以仓库根 README 和 `docs/双人融合说明-0.8.0.html` 为准。下文保留双方历史交接；其中“AI尚未实现”、旧SDK默认值、原安装路径及30天删除是历史独立版事实，不代表当前共同版。

# 0.6.0 融合预览补充

当前功能分支新增独立融合应用，单接收器供列表和弹幕，本机设置与外观 MCP。先读根 docs/预览版使用说明.html。以下为 0.5.0 原始交接背景，不代表当前应用已安装或新账号已获授权。

# 柚子岛源码交接说明

同步日期：2026-10-24；当前版本：0.7.5（build23）。原始0.5.0交接说明保留如下。

这是用于双方代码协作的源码包，不是可直接双击运行的安装包。功能包括原生Mac灵动岛外壳、飞书重要消息提醒、Agent状态与额度、四套皮肤、临时待办与30天归档、网页设置面板、应用图标与桌面替身脚本。AI任务和Skill接入仍在讨论阶段，尚未实现。

## 建立GitHub仓库

建议先建立 **Private（私有）** 仓库，再邀请协作者。`Sources/IslandShell/Feishu/SOURCE.md`记载飞书接收器来自伙伴交接源码，未授予公开再分发许可；本次交接不新增开源授权。保留所有来源说明和第三方许可证。

推荐流程：朋友在GitHub创建一个空的私有仓库（先不自动添加README、许可证或.gitignore），将源码解压到本机，终端进入包含`Package.swift`的目录后执行：

```sh
git init -b main
git add .
git status --short
git commit -m "Initial import of YuIsland 0.5.0"
```

然后复制GitHub新仓库页面提供的`git remote add origin ...`命令，执行后运行：

```sh
git push -u origin main
```

不要直接上传整个ZIP作为唯一仓库文件，应上传解压后的源码。`Vendor/OpenNook`必须作为普通目录完整提交，不需要额外克隆子模块。`SettingsWeb/dist`的3个文件也必须提交，它们是当前直接维护的网页源码。

创建者在仓库设置中邀请协作者。收到仓库链接及邀请后，另一方克隆同一个仓库，以这个仓库为后续共同来源。日常从更新后的main新建`codex/功能名`分支，提交、推送并通过Pull Request合并，避免两人同时直接覆盖main。

## 开发环境与构建

- Mac；项目最低声明macOS 15，当前仅在Apple Silicon Mac上验证过。
- 安装Apple Command Line Tools或Xcode，能够运行`swift`和`codesign`；飞书模拟测试还需要`python3`。
- 构建脚本默认使用`/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`，这是原开发机验证过的版本。其他电脑若没有该SDK，应显式选择已安装、与Swift编译器兼容的SDK。
- 原开发机的macOS 27 SDK与当时的Command Line Tools存在宏插件兼容问题，不代表所有新版Xcode都会失败。不要复制不存在的SDK路径。

在项目根目录运行：

```sh
# 本机已有脚本默认的26.5 SDK时：
./scripts/check.sh
./scripts/check-feishu.sh
./scripts/build.sh
```

如果使用开发机当前选中的SDK，可显式指定后运行；能否兼容仍以该机器的实际构建为准：

```sh
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
./scripts/check.sh
./scripts/check-feishu.sh
./scripts/build.sh
```

生成应用在`dist/柚子岛.app`。采用本地临时签名，没有做Developer ID分发签名与公证。不要把缓存或构建产物提交到源码仓库。

## 飞书接入与演示

源码包不包含任何人的登录凭据、会话数据或CLI程序。真实消息接收需要每位使用者自行安装兼容的`lark-cli`，放在`~/.local/bin/lark-cli`，并用自己的飞书账号完成所需授权。可用范围取决于自己的账号权限；不要复制原作者的授权文件。CLI安装来源及公司应用权限需按所在环境确认。

接收器的模拟测试使用包内`Tests/FeishuReaderChecks/fake-cli.py`，无需登录飞书。构建后，可在没有其他柚子岛实例运行时启动合成消息演示：

```sh
"dist/柚子岛.app/Contents/MacOS/YuIsland" --feishu-demo
```

应用窗口自检也要求先退出已有实例：

```sh
"dist/柚子岛.app/Contents/MacOS/YuIsland" --self-test
```

这些自检不能代替真实刘海屏、鼠标悬停、显示器热插拔和休眠唤醒验收。

## 源码地图

| 路径 | 用途 |
| --- | --- |
| Sources/YuIsland | 应用入口 |
| Sources/IslandShell | 外壳、设计主题、模块注册 |
| Sources/IslandShell/Feishu | 飞书消息与提醒 |
| Sources/IslandShell/Settings | 本机网页设置服务、联系人与群聊查询 |
| SettingsWeb/dist | 设置网页HTML、CSS、JS；不是可丢弃缓存 |
| Vendor/OpenNook | 固定版本的上游源码及本地补丁、许可证 |
| Tests、scripts | 逻辑检查、模拟接收器检查、构建 |
| Examples | 新模块示例 |

## 交接范围与验收

保留源码、资源、网页、测试、构建脚本、README、来源及许可证。排除`.git`、`.build`、根目录`dist`、原始调研包、历史截图和运行日志。README与来源说明中指向`research/`、`verification/`或原开发机桌面的链接仅用于说明历史出处，相关材料留在原作者电脑，不在本包内。

包内`PACKAGE-MANIFEST.sha256`列出其余交接文件的SHA-256。未修改源码前可在项目根目录运行`shasum -a 256 -c PACKAGE-MANIFEST.sha256`校验；开始开发后文件散列会改变，这是正常现象。

本次交接验证结果见`PACKAGING-CHECKS.md`。真实飞书登录和新电脑实机运行仍需接收方在自己的环境确认。


## 0.5.1 Agent模块补充

在回滚后的0.5.0上加入Codex、WorkBuddy状态与额度接入，说明及限制见[Agent接入说明](AGENT-INTEGRATION.md)。Claude桌面版没有可用账号，任务状态与实时额度尚未完成接入。新增逻辑检查运行`swift run --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk AgentChecks`。旧版备份保留在本机更新备份目录；未提交或发布到远程仓库。

## 0.7.5协作同步

本次将独立迭代的本机版本同步到协作分支，仅更新`apps/island`。不包含对方`codex/collaboration-panel`分支的个人中台、Dot连接或弹幕融合；这些功能需单独比较后合并。主分支、弹幕目录、授权边界及其他开发分支不受本次上传影响。

桌面入口：构建并安装到`~/Applications/柚子岛.app`后，运行`swift scripts/install-desktop-shortcut.swift`；图标随正常打包装入。脚本支持显式指定安装包及桌面替身路径。

`PACKAGE-MANIFEST.sha256`与`PACKAGING-CHECKS.md`是2026-10-19原始0.5.0交接记录，不能用于校验本次0.7.5改动。当前验证与同步范围见`SYNC-20261024.md`。
