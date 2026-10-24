'use strict';
(() => {
  const form = document.querySelector('#todo-settings-form');
  const minutes = document.querySelector('#todo-minutes');
  const sound = document.querySelector('#todo-sound');
  const status = document.querySelector('#todo-settings-status');
  const save = document.querySelector('#todo-save');
  const reload = document.querySelector('#todo-reload');
  let snapshot = null, busy = false, dirty = false;
  const message = (text, error = false) => { status.textContent = text; status.classList.toggle('error', error); };
  const controls = () => { minutes.disabled = sound.disabled = busy || !snapshot; save.disabled = busy || !snapshot || !dirty; reload.disabled = busy; };
  const request = async (payload) => {
    const response = await fetch('/api/todos/settings', {
      method: payload ? 'POST' : 'GET', cache: 'no-store', signal: AbortSignal.timeout(5000),
      headers: payload ? {'Content-Type':'application/json','X-Island-Settings':'1'} : {},
      body: payload ? JSON.stringify(payload) : undefined
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || '设置未保存');
    return body;
  };
  async function load() {
    if (busy) return;
    busy = true; controls();
    try {
      snapshot = await request(); minutes.value = snapshot.defaultMinutes; sound.checked = snapshot.soundEnabled;
      dirty = false; message('设置已载入');
    } catch (error) { message(error.message, true); }
    finally { busy = false; controls(); }
  }
  form.addEventListener('input', () => { dirty = true; message('有未保存的修改'); controls(); });
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || !snapshot || !form.reportValidity()) return;
    const value = Number(minutes.value);
    if (!Number.isInteger(value) || value < 1 || value > 10080) return;
    busy = true; controls();
    try {
      snapshot = await request({revision: snapshot.revision, defaultMinutes: value, soundEnabled: sound.checked});
      dirty = false; message('已保存，应用于新建待办');
    } catch (error) { message(error.message, true); }
    finally { busy = false; controls(); }
  });
  reload.addEventListener('click', load);
  window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
  load();
})();
