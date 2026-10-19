// Read-only capability probe. Never prints message text, names, IDs or credentials.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
const run = promisify(execFile);
const cli = fileURLToPath(new URL('../tools/lark-cli/bin/lark-cli', import.meta.url));
const mode = process.argv[2] ?? '--check';
if (!['--check', '--probe'].includes(mode)) throw new Error('Use --check or --probe');
const profile = process.env.DANMU_LARK_PROFILE;
async function call(args) {
  try {
    const result = await run(cli, [...(profile ? ['--profile', profile] : []), ...args], {
      timeout: 30000, maxBuffer: 8 * 1024 * 1024,
      env: { ...process.env, LARKSUITE_CLI_NO_UPDATE_NOTIFIER: '1', LARKSUITE_CLI_NO_SKILLS_NOTIFIER: '1' }
    });
    const body = JSON.parse(result.stdout);
    if (body.ok !== true && !(args[0] === 'auth' && body.identities)) throw { stderr: result.stdout };
    return body;
  } catch (error) {
    let failure;
    try { failure = JSON.parse(error.stderr || '{}').error; } catch {}
    console.log(JSON.stringify({ ok: false, stage: args.slice(0, 2).join(' '), type: failure?.type ?? 'local', reason: failure?.subtype ?? 'command_failed', code: failure?.code ?? null }));
    process.exit(1);
  }
}
const status = await call(['auth', 'status', '--json']);
console.log(JSON.stringify({ ok: true, stage: 'local_auth_status', note: 'Local status only; API access is not yet proven.' }));
if (mode === '--probe') {
  // A bounded diagnostic sample, never presented as complete account coverage.
  const chats = await call(['im', '+chat-list', '--as', 'user', '--types=p2p,group', '--sort', 'active_time', '--page-size', '50', '--format', 'json']);
  if (chats.identity !== 'user' || !Array.isArray(chats.data?.chats)) throw new Error('Unexpected identity or chat schema; stop');
  console.log(JSON.stringify({ ok: true, stage: 'chat_sample', count: chats.data.chats.length, morePages: chats.data.has_more === true }));
  for (const type of ['p2p', 'group']) {
    const chat = chats.data.chats.find(c => c.chat_mode === type && /^oc_[A-Za-z0-9]+$/.test(c.chat_id));
    if (!chat) { console.log(JSON.stringify({ ok: false, stage: type, reason: 'no_chat_in_sample' })); continue; }
    const result = await call(['im', '+chat-messages-list', '--as', 'user', '--chat-id', chat.chat_id, '--page-size', '1', '--no-reactions', '--format', 'json']);
    if (result.identity !== 'user' || !Array.isArray(result.data?.messages)) throw new Error('Unexpected identity or message schema; stop');
    console.log(JSON.stringify({ ok: true, stage: type, messageCount: result.data.messages.length, contentPresent: result.data.messages.some(m => typeof m.content === 'string' && m.content.length > 0) }));
  }
}
