'use strict';
// Runs the official lark-cli with a token-only environment and parses its JSON.
// Mirrors AccountReader.call: bounded time, stdout or stderr JSON, no body logging.
const { spawn } = require('node:child_process');
const { AccountFailure } = require('./feishu/reader.cjs');

function runCLI({ executable, args, env, cwd, timeout = 8000, maxBytes = 32 * 1024 * 1024 }) {
  return new Promise((resolve, reject) => {
    let child;
    try { child = spawn(executable, args, { env, cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch (error) { reject(new AccountFailure('飞书组件无法启动，请重新安装一切在岛。')); return; }
    const out = [], err = []; let size = 0, killed = false;
    const collect = (list) => chunk => { size += chunk.length; if (size > maxBytes) { killed = true; child.kill(); } else list.push(chunk); };
    child.stdout.on('data', collect(out)); child.stderr.on('data', collect(err));
    const timer = setTimeout(() => { killed = true; child.kill(); setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, 1000); }, timeout);
    child.on('error', () => { clearTimeout(timer); reject(new AccountFailure('飞书组件无法启动，请重新安装一切在岛。')); });
    child.on('close', code => {
      clearTimeout(timer);
      if (killed) { reject(new AccountFailure('飞书接口超时，稍后自动重试')); return; }
      const bytes = Buffer.concat(out).length ? Buffer.concat(out) : Buffer.concat(err);
      let result;
      try { result = JSON.parse(bytes.toString('utf8')); } catch { reject(new AccountFailure(`接口未有效返回（退出码 ${code}，返回 ${bytes.length} 字节）`)); return; }
      if (code !== 0 || (result && result.ok === false)) {
        const e = result && result.error && typeof result.error === 'object' ? result.error : {};
        const errCode = e.code !== undefined ? String(e.code) : '未知';
        reject(new AccountFailure(`飞书接口错误 ${errCode}，请检查账号授权或网络`));
        return;
      }
      resolve(result);
    });
  });
}

module.exports = { runCLI };
