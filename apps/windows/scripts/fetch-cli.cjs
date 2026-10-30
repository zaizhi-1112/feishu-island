'use strict';
// Downloads the official lark-cli Windows build and verifies it against the
// checksums.txt shipped inside the official @larksuite/cli npm package.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const pkg = require(path.join(root, 'node_modules/@larksuite/cli/package.json'));
const version = pkg.version;
const archive = `lark-cli-${version}-windows-amd64.zip`;
const url = `https://github.com/larksuite/cli/releases/download/v${version}/${archive}`;
const target = path.join(root, 'vendor/win-x64');
const exe = path.join(target, 'lark-cli.exe');
const stamp = path.join(target, '.verified');

function expected() {
  const text = fs.readFileSync(path.join(root, 'node_modules/@larksuite/cli/checksums.txt'), 'utf8');
  const line = text.split('\n').find(l => l.trim().endsWith('  ' + archive));
  if (!line) throw new Error('checksums.txt 中没有 ' + archive);
  const hash = line.split(/\s+/)[0];
  if (!/^[0-9a-f]{64}$/.test(hash)) throw new Error('官方校验值格式异常');
  return hash;
}

async function main() {
  const hash = expected();
  if (fs.existsSync(exe) && fs.existsSync(stamp) && fs.readFileSync(stamp, 'utf8').trim() === `${archive} ${hash}`) {
    console.log('lark-cli.exe 已核对：' + archive);
    return;
  }
  fs.mkdirSync(target, { recursive: true });
  console.log('下载官方 CLI：' + url);
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok) throw new Error('下载失败 HTTP ' + response.status);
  const bytes = Buffer.from(await response.arrayBuffer());
  const actual = crypto.createHash('sha256').update(bytes).digest('hex');
  if (actual !== hash) throw new Error(`SHA-256 不一致：期望 ${hash}，实际 ${actual}`);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'lark-cli-'));
  try {
    const zip = path.join(work, archive);
    fs.writeFileSync(zip, bytes);
    execFileSync('tar', ['-xf', zip, '-C', work]);
    const found = [];
    (function walk(dir) {
      for (const name of fs.readdirSync(dir)) {
        const file = path.join(dir, name);
        if (fs.statSync(file).isDirectory()) walk(file);
        else found.push(file);
      }
    })(work);
    const binary = found.find(f => path.basename(f) === 'lark-cli.exe');
    if (!binary) throw new Error('压缩包中没有 lark-cli.exe');
    fs.copyFileSync(binary, exe);
    const license = found.find(f => /^LICENSE/i.test(path.basename(f)));
    if (license) fs.copyFileSync(license, path.join(target, 'LICENSE'));
    fs.writeFileSync(stamp, `${archive} ${hash}\n`);
    console.log('已核对并放入 vendor/win-x64：' + hash);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error.message); process.exit(1); });
