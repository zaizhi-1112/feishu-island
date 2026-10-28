# build82完整源码同步

## 来源与范围

- 应用源码与资源：本机已安装并验证的0.10.0/build82项目。
- 补齐的仓库文档与协作脚本：`codex/integrate-youzi-075`提交`e0a0a4814e7d244c4f6dea5693c0fd7da6a14710`，GitHub ZIP完整性已检查。
- 目标：`zaizhi-1112/feishu-island`的`codex/youzi-island-0.7.5-sync`；同步前版本`ea8255541123cdddcb13be7c13bf7dfb493db8c9`。
- 保留应用、弹幕、服务、网页、所有依赖声明/锁文件、Vendor源码及许可证、音视频/图标资源、测试、打包脚本和协作脚本。
- 不含个人任务、偏好、登录态、密钥、私有备份、日志、缓存、安装包及CLI二进制。官方CLI需从官方发行渠道恢复，不复制他人配置。

## 构建

适用macOS 15+，需Swift工具链和兼容SDK。本机验证使用macOS 26.5 SDK；请按本机实际安装路径设置，不能照搬路径。

```sh
cd apps/island
export ISLAND_SDK="$(xcrun --sdk macosx --show-sdk-path)"
swift build --disable-sandbox --sdk "$ISLAND_SDK" -j 2 -c release --product YuIsland
# 完整.app打包还需要官方CLI可执行文件；本机build82使用官方CLI 1.0.98。
export ISLAND_LARK_CLI="/absolute/path/to/official/lark-cli"
bash scripts/build.sh
```

构建默认输出`apps/island/dist/一切在岛.app`，不会安装应用、同步个人配置或部署服务。源码包含helper构建入口；既有安装的helper保全属于本机升级行为，不作为源码构建前提。AuthService、BrowserBridge、Dot/Tunnel和旧工作流的源码保留不表示默认启用。

## 验证

```sh
shasum -a 256 -c SOURCE-MANIFEST.sha256
bash scripts/check.sh web
node --test scripts/collab-runner.test.cjs
cd apps/island
swift run --disable-sandbox --sdk "$ISLAND_SDK" -j 2 UnifiedProductChecks
```

更多实际检查结果和未验边界见`docs/build82/验证记录.md`。历史`PACKAGE-MANIFEST.sha256`描述原来的打包阶段；当前完整源树使用根目录的`SOURCE-MANIFEST.sha256`校验。
