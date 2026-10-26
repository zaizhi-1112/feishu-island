'use strict';
const agentBrief = `帮我安装、连接或调整你的飞包。先阅读这个操作指南：https://feishu-island.virxact.net/agent-guide.html 。
公司安装入口：https://feishu-island.virxact.net/ 。请在我自己的 Mac 上检查安装和连接状态，按我的具体需求继续。已正常运行的飞书接收、项目材料和连接要保留，不重复配对、不读取真实聊天来测试。
我想定制首页或数据时，用我自己的虚实中台 MCP，先读 get_spec 和 get_page，再按我的需求调整；灵动岛卡片在“中台”里选择，外观使用本机设置“接入 Agent”的受限接口，核心功能由项目维护者管理。
需要扫码、系统确认或新授权时告诉我点哪里，不索取密码，不复制其他人的凭据。用明确的合成材料验证，只报告实际通过的环节。`;
const copyButton = document.querySelector('#copy-agent');
const feedback = document.querySelector('#agent-feedback');
const fallback = document.querySelector('#copy-fallback');
const text = document.querySelector('#agent-text');
text.value = agentBrief;
copyButton.addEventListener('click', async () => {
  if (copyButton.disabled) return;
  copyButton.disabled = true;
  feedback.hidden = false;
  feedback.textContent = '正在复制…';
  try {
    await navigator.clipboard.writeText(agentBrief);
    fallback.hidden = true;
    copyButton.querySelector('span').textContent = '已复制';
    feedback.textContent = '已复制。粘贴给你的 Codex 或其他 Agent，再告诉它你想怎么用。';
  } catch {
    fallback.hidden = false;
    feedback.textContent = '没有复制成功，请手动复制下方文字。';
    text.focus(); text.select();
  } finally { copyButton.disabled = false; }
});
document.querySelector('#close-copy').addEventListener('click', () => { fallback.hidden = true; copyButton.focus(); });
document.querySelector('#download').addEventListener('click', () => {
  document.querySelector('#download-feedback').hidden = false;
});

// Native SwiftUI exports from synthetic stores. No real accounts or desktop bridge.
const demo = document.querySelector('#desktop-demo');
const island = document.querySelector('#demo-island');
const compact = document.querySelector('#demo-compact');
const panel = document.querySelector('#demo-panel');
const expanded = document.querySelector('#demo-expanded');
const caption = document.querySelector('#demo-caption');
const danmu = document.querySelector('#demo-danmu');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const demoStates = {
  feishu: { compact: 'demo-feishu-compact.png', expanded: 'demo-feishu-expanded.png', alt: '软件内的飞书消息阅读界面', text: '合成演示 · 讨论改到下午3点，方便时确认。', caption: '鼠标放到顶部展开，移开收回。消息以白字描边飘过桌面。' },
  agent: { compact: 'demo-agent-working.png', expanded: 'demo-materials.png', alt: '软件内的 Agent 材料输入界面', text: 'Codex · 合成任务已完成。', caption: '运行 → 等你确认 → 已完成。真实确认仍由你本人操作。' },
  result: { compact: 'demo-agent-idle.png', expanded: 'demo-materials.png', alt: '软件内的材料输入与结果界面', text: 'Codex · 两条反馈已整理，回到待办查看。', caption: '输入材料 → 后台处理 → 结果回到待办。这里使用原生界面的合成任务。' }
};
let demoMode = 'feishu';
let timers = [];
let sceneVersion = 0;
let pointerInside = false;
let focusInside = false;
function openPanel(value) { panel.hidden = !value; island.setAttribute('aria-expanded', String(value)); }
function later(ms, run) { timers.push(setTimeout(run, ms)); }
function emitDanmu(text) {
  danmu.textContent = text;
  danmu.style.setProperty('--danmu-travel', `-${demo.clientWidth + danmu.scrollWidth + 4}px`);
  danmu.classList.remove('playing');
  const version = sceneVersion;
  requestAnimationFrame(() => requestAnimationFrame(() => { if (version === sceneVersion) danmu.classList.add('playing'); }));
}
function showDemo(mode) {
  timers.forEach(clearTimeout); timers = []; sceneVersion++;
  demoMode = mode;
  const state = demoStates[mode];
  compact.src = state.compact; compact.alt = mode === 'feishu' ? '飞书消息：1条，中间为摄像头留空' : 'Codex 状态与额度，摄像头在中间';
  expanded.src = state.expanded; expanded.alt = state.alt;
  caption.textContent = state.caption;
  openPanel(pointerInside || focusInside);
  document.querySelectorAll('[data-demo]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.demo === mode)));
  if (reducedMotion.matches || mode === 'feishu') { emitDanmu(state.text); return; }
  danmu.classList.remove('playing');
  if (mode === 'agent') {
    later(2000, () => { compact.src = 'demo-agent-waiting.png'; emitDanmu('Codex · 等你确认。'); });
    later(5300, () => { compact.src = 'demo-agent-completed.png'; emitDanmu(state.text); });
  } else {
    openPanel(true);
    later(2600, () => { openPanel(false); compact.src = 'demo-agent-working.png'; });
    later(5200, () => { compact.src = 'demo-agent-completed.png'; expanded.src = 'demo-result.png'; openPanel(true); emitDanmu(state.text); });
    later(9800, () => { if (!pointerInside && !focusInside) openPanel(false); });
  }
}
island.addEventListener('mouseenter', () => { pointerInside = true; openPanel(true); });
island.addEventListener('mouseleave', () => { pointerInside = false; later(180, () => { if (!pointerInside && !focusInside) openPanel(false); }); });
island.addEventListener('focusin', () => { focusInside = true; openPanel(true); });
island.addEventListener('focusout', () => { focusInside = false; if (!pointerInside) openPanel(false); });
island.addEventListener('click', () => openPanel(true));
document.addEventListener('pointerdown', event => { if (!island.contains(event.target)) openPanel(false); });
island.addEventListener('keydown', event => { if (event.key === 'Escape') { openPanel(false); island.blur(); } else if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); openPanel(panel.hidden); } });
document.querySelectorAll('[data-demo]').forEach(button => button.addEventListener('click', () => showDemo(button.dataset.demo)));
document.querySelector('#replay-demo').addEventListener('click', () => showDemo(demoMode));
showDemo('feishu');
