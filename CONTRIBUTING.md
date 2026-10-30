# 参与贡献

先查看[项目首页](README.md)、对应平台说明和正在进行的[合并请求](https://github.com/zaizhi-1112/feishu-island/pulls)，避免从旧源码重复实现已有改动。

## 提交问题

说明系统、芯片架构、应用版本、复现步骤和期望结果。截图先遮盖聊天、姓名和账号；不要上传凭据、个人数据目录或完整诊断日志。安全问题使用[安全反馈](SECURITY.md)。

## 修改代码

1. 从确认过的基线创建功能分支，先阅读AGENTS.md及修改目录的规则。
2. 使用合成数据完成必要检查；测试通过不代表真实账号或Windows真机验收通过。
3. 提交简洁的英文commit message，在PR中用中文说明用户影响、检查结果和未验证项。
4. 不提交个人配置、授权、消息、安装包、依赖缓存或签名私钥。第三方来源与许可证必须保留。

### 常用检查

```sh
npm test --prefix apps/windows
bash scripts/check.sh web
node --test apps/island/Tests/deepseek-balance.test.cjs
node --test apps/island/AuthService/*.test.cjs
```

Mac原生检查与打包见[应用开发说明](apps/island/README.md)。只改文档时检查链接、版本和实际仓库页面；不为文档变更重新发布安装包。

## 审核与发布

正式合入main仍需宰治、柚子两位负责人批准同一版本。代码合并、GitHub安装包发布、中台部署和用户实际安装是不同步骤；Agent不得代投票。CI及CODEOWNERS本身不证明已经取得双人批准。

旧PR与分支不因新整理被自动删除或关闭。合并新的整合PR后，再由维护者核对哪些旧PR已完全被包含。

## 授权边界

项目自有代码和文档采用[MIT许可证](LICENSE)，范围见[NOTICE.md](NOTICE.md)。提交项目自有代码的贡献沿用MIT授权；提交前请确认你拥有相应权利，不把第三方代码或素材按项目自己的代码重新授权。详情见[来源与许可](docs/来源与许可.md)。
