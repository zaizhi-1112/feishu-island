'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { TodoStore } = require('../core/todos.cjs');
const { parseEvent, applyEvents, fetchEvents } = require('../core/schedule.cjs');

const temp = () => path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'island-todos-')), 'workspace.json');

test('new todos go first, default reminder in 20 minutes, order persists', () => {
  let now = 1_800_000_000;
  const file = temp();
  const store = new TodoStore({ file, now: () => now });
  const a = store.add('第一件'); now += 1; const b = store.add('第二件');
  assert.deepEqual(store.pending.map(i => i.id), [b, a]);
  assert.equal(store.pending[0].due, now + 1200);
  store.move(b, 1);
  const reloaded = new TodoStore({ file, now: () => now });
  assert.deepEqual(reloaded.pending.map(i => i.id), [a, b]);
  assert.throws(() => store.add(''), /160字/);
});

test('complete records history, reopen keeps history, delete goes to trash and restores', () => {
  let now = 1_800_000_000;
  const store = new TodoStore({ file: temp(), now: () => now });
  const id = store.add('写周报');
  store.complete(id);
  assert.equal(store.completed.length, 1); assert.equal(store.history.length, 1);
  store.reopen(id);
  assert.equal(store.pending.length, 1); assert.equal(store.history.length, 1, 'completion event is immutable');
  store.remove(id); assert.equal(store.pending.length, 0);
  store.restore(id); assert.equal(store.pending.length, 1);
});

test('due reminders fire once, advance repeating plans, and respect onboarding gate', () => {
  let now = 1_800_000_000, allowed = false;
  const store = new TodoStore({ file: temp(), now: () => now, canRemind: () => allowed });
  const id = store.add('喝水');
  store.update(id, { dates: [now + 60], repeatMinutes: 30, repeatUntil: now + 3600 });
  const notes = []; store.on('notify', n => notes.push(n.title));
  now += 61; store.tick(); assert.deepEqual(notes, [], 'gated before onboarding');
  allowed = true; store.tick(); assert.deepEqual(notes, ['喝水']);
  store.tick(); assert.deepEqual(notes, ['喝水'], 'not replayed');
  assert.equal(store.pending[0].due, now + 1800);
  now += 1801; store.tick(); assert.equal(notes.length, 2);
});

test('screen-style todo reminders route to the screen presenter, light ones to the island', () => {
  let now = 1_800_000_000;
  const store = new TodoStore({ file: temp(), now: () => now });
  store.setDefaultScreen({ materialID: 'cat', durationSeconds: 15 });
  store.add('冲屏');
  const screens = []; store.on('screen', s => screens.push(s.title));
  now += 1201; store.tick();
  assert.deepEqual(screens, ['冲屏']);
  assert.throws(() => store.setDefaultScreen({ materialID: 'nope', durationSeconds: 15 }));
});

test('rest reminder fires after interval, pauses while away and keeps remaining time', () => {
  let now = 1_800_000_000;
  const store = new TodoStore({ file: temp(), now: () => now });
  store.setRestEnabled(true); store.setRestInterval(5);
  const screens = []; store.on('screen', s => screens.push(s));
  now += 200; store.setAway(true); store.tick();
  now += 1000; store.tick(); assert.equal(screens.length, 0);
  store.setAway(false); store.tick();
  assert.ok(Math.abs(store.rest.fireAt - (now + 100)) < 1);
  now += 101; store.tick();
  assert.equal(screens.length, 1); assert.equal(screens[0].rest, true);
});

test('week range is Monday to Sunday', () => {
  const store = new TodoStore({ now: () => new Date(2026, 9, 30, 15).getTime() / 1000 }); // Friday
  const [a, b] = store.weekRange();
  assert.equal(new Date(a * 1000).getDay(), 1); assert.equal(new Date(a * 1000).getDate(), 26);
  assert.equal((b - a) / 86400, 7);
});

test('calendar events parse, merge without replaying past reminders, and fire once', async () => {
  const now = new Date(2026, 9, 30, 9).getTime() / 1000;
  const timed = parseEvent({ event_id: 'e1', summary: '周会', start_time: { timestamp: String(now + 3600) }, end_time: { timestamp: String(now + 7200) } });
  const allDay = parseEvent({ event_id: 'e2', start_time: { date: '2026-10-31' }, end_time: { date: '2026-10-31' } });
  assert.equal(allDay.allDay, true); assert.equal(allDay.title, '未命名日程'); assert.equal(allDay.end - allDay.start, 86400);
  assert.throws(() => parseEvent({ event_id: 'x', start_time: { date: '2026-02-30' }, end_time: { date: '2026-02-30' } }));
  const merged = applyEvents([], [timed], now);
  assert.deepEqual(merged[0].consumed, [now + 3600 - 86400], 'day-before reminder already passed');
  let clock = now;
  const store = new TodoStore({ file: temp(), now: () => clock });
  store.setSchedule({ enabled: true });
  store.replaceScheduleEvents('本人', 'cal', [timed]);
  clock = now + 3600 - 900 + 1;
  const notes = []; store.on('notify', n => notes.push(n.title));
  store.tick(); store.tick();
  assert.deepEqual(notes, ['日程 · 周会']);
  const request = async (method, p) => method === 'POST' ? { calendars: [{ calendar: { type: 'primary', calendar_id: 'c@x' } }] } : { items: [{ event_id: 'e1', status: 'cancelled', start_time: { timestamp: '1' }, end_time: { timestamp: '2' } }] };
  assert.deepEqual((await fetchEvents(request, now, now + 86400)).events, []);
});
