# 一切在岛 Windows 测试版

Windows 10/11 x64，Electron 44.7.0，版本0.12.16。以Mac build110及Agent提醒修复为移植基线，不代表已经具有Mac build111的全部功能。

[下载安装包](https://github.com/zaizhi-1112/feishu-island/releases/tag/v0.12.16-windows) · [实现与验收范围](../../docs/windows-port.md)

## 本地开发

需要Node.js和npm，依赖版本以package-lock.json为准。CI使用Node.js 24。

```sh
npm ci --prefix apps/windows
npm test --prefix apps/windows
npm run demo --prefix apps/windows
```

demo只使用合成数据，不读取本机Codex或Claude资料。真实使用需要本人授权；现成分发包的公司连接受虚实传媒服务访问范围限制。

## 构建

```sh
npm run pack:win --prefix apps/windows
```

脚本从官方发布下载lark-cli.exe并核对SHA-256，随后生成NSIS x64安装包并检查包内容。输出位于本目录dist/，不提交Git。构建需要网络。

Mac交叉构建、合成测试和Mac上Electron演示已验证；Windows真机的安装、DPI、置顶/穿透、快捷键、托盘、登录启动以及真实账号连接尚未验收。安装包未签名。

## 目录

- main/：主进程、窗口、授权、接收和存储。
- core/：可独立测试的纯逻辑。
- renderer/：界面与白名单preload接口。
- tests/：合成测试。
- scripts/：CLI校验、构建及包检查。
- assets/：素材；原权利及声明单独保留。

消息只读，本机历史按账号隔离，默认保留7天；Windows凭据通过safeStorage加密保存。不要把userData、登录资料、真实消息或安装包提交到仓库。
