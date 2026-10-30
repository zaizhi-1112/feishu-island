'use strict';
// Post-build check: the installer exists, carries the verified official CLI, and the
// unpacked app contains no personal credentials, profiles, message history or logs.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.join(__dirname, '..');
const dist = path.join(root, 'dist');
const version = require(path.join(root, 'package.json')).version;
const installer = path.join(dist, `FeishuIsland-Setup-${version}-x64.exe`);
const unpacked = path.join(dist, 'win-unpacked');
const fail = m => { console.error('✗ ' + m); process.exitCode = 1; };
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');

if (!fs.existsSync(installer)) fail('缺少安装包 ' + installer);
const cli = path.join(unpacked, 'resources', 'cli', 'lark-cli.exe');
const stamp = fs.readFileSync(path.join(root, 'vendor/win-x64/.verified'), 'utf8').trim();
if (!fs.existsSync(cli)) fail('安装包内缺少 lark-cli.exe');
else if (sha(cli) !== sha(path.join(root, 'vendor/win-x64/lark-cli.exe'))) fail('包内 lark-cli.exe 与已核对文件不一致');

const forbidden = [/\.data$/i, /auth\.json$/i, /hub-grant/i, /preferences\.json$/i, /workspace\.json$/i, /MessageHistory/i, /CompanyCLI/i, /\.log$/i, /\.pem$/i, /\.key$/i, /\.env/i];
const secrets = [/LARKSUITE_CLI_USER_ACCESS_TOKEN\s*=\s*['"]?[A-Za-z0-9_-]{20,}/, /\bu-[A-Za-z0-9_-]{40,}/, /\bsk-[A-Za-z0-9]{20,}/, /ghp_[A-Za-z0-9]{30,}/];
let files = 0;
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { walk(p); continue; }
    files++;
    const rel = path.relative(unpacked, p);
    if (forbidden.some(r => r.test(rel))) fail('包内出现不应打包的文件：' + rel);
  }
})(unpacked);
// The app's own sources live in app.asar; scan them as text.
const asar = path.join(unpacked, 'resources', 'app.asar');
const text = fs.readFileSync(asar).toString('latin1');
for (const r of secrets) if (r.test(text)) fail('app.asar 中发现疑似凭据：' + r);
if (/\/Users\/zaizhi/.test(text)) fail('app.asar 中出现本机个人目录路径');

if (!process.exitCode) {
  const size = (fs.statSync(installer).size / 1048576).toFixed(1);
  console.log(`✓ ${path.basename(installer)}  ${size} MB  SHA-256 ${sha(installer)}`);
  console.log(`✓ lark-cli.exe 官方校验一致（${stamp.split(' ')[0]}）；扫描 ${files} 个文件，未发现凭据、个人配置或消息记录`);
}
