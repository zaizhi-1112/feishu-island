'use strict';
const agentBrief = `帮我安装、连接或调整飞书工作岛。先阅读这个操作指南：https://feishu-island.virxact.net/agent-guide.html 。
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
