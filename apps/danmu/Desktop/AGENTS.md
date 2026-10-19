# 跨平台同事版
沿用根目录的隐私与授权边界。Electron 为 Windows 与 Mac 提供桌面覆盖层，不替换已验证的 Swift 实现。
- core/reader.cjs：官方 CLI 只读接收、时间校准、未读筛选与重连；ui/：文豪野犬面板和卡片；main.cjs：本地凭证交接、托盘、休眠与窗口。
- npm test：合成消息/故障/压力/阅读完整性测试；npm run pack:mac、npm run pack:win：安装包。
- vendor 只包含经官方 SHA-256 核验的 CLI 与许可证；安装包禁止包含用户 profile、token、App Secret、真实消息或本机日志。
- Windows 安装包构建与 Windows 真机验收分开标注。用户自己的扫码授权及管理员审核不能代操作或伪造。
