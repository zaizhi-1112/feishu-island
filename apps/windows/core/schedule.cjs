'use strict';
// Port of Todos/FeishuSchedule.swift: read-only primary-calendar events, parsed
// from calendar/v4 instance_view. Times are epoch seconds.

class ScheduleError extends Error {}

function offsetText(v) {
  if (v === 0) return '开始时';
  if (v % 1440 === 0) return `提前${v / 1440}天`;
  if (v % 60 === 0) return `提前${v / 60}小时`;
  return `提前${v}分钟`;
}
const reminderDates = e => e.offsets.map(o => e.start - o * 60);

function parseDate(value, isEnd) {
  if (typeof value.date === 'string') {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.date);
    if (!m) throw new ScheduleError('全天日程日期无效。');
    const [y, mo, da] = [Number(m[1]), Number(m[2]) - 1, Number(m[3])];
    const d = new Date(y, mo, da);
    if (d.getFullYear() !== y || d.getMonth() !== mo || d.getDate() !== da) throw new ScheduleError('全天日程日期无效。');
    return (isEnd ? new Date(y, mo, da + 1) : d).getTime() / 1000;
  }
  const seconds = Number(value.timestamp);
  if (typeof value.timestamp !== 'string' || !Number.isFinite(seconds) || seconds <= 0 || seconds >= 253402300800) throw new ScheduleError('日程时间无效。');
  return seconds;
}

function parseEvent(row) {
  if (!row || typeof row.event_id !== 'string' || !row.event_id || row.event_id.length >= 1024 || !row.start_time || !row.end_time) throw new ScheduleError('某条日程缺少时间，本次同步未覆盖已有记录。');
  const allDay = typeof row.start_time.date === 'string';
  const start = parseDate(row.start_time, false), end = parseDate(row.end_time, true);
  if (end < start) throw new ScheduleError('日程起止时间无效。');
  const title = typeof row.summary === 'string' && row.summary ? row.summary : '未命名日程';
  if (title.length >= 10000) throw new ScheduleError('日程标题过长。');
  return { id: row.event_id, title, start, end, allDay, appLink: typeof row.app_link === 'string' && row.app_link.startsWith('https://') ? row.app_link : null, status: 'confirmed', offsets: [1440, 15], consumed: [] };
}

/** Merge a complete remote snapshot; never replay reminders whose time has passed. */
function applyEvents(existing, remote, now) {
  const old = new Map(existing.map(e => [e.id, e]));
  return remote.map(r => {
    const e = { ...r };
    const prev = old.get(e.id);
    if (prev) { e.offsets = prev.offsets; e.consumed = prev.consumed; }
    if (!prev || prev.start !== e.start) e.consumed = [...new Set([...e.consumed, ...reminderDates(e).filter(d => d <= now)])].sort((a, b) => a - b);
    return e;
  }).filter(e => e.end > now).sort((a, b) => a.start - b.start);
}

/** Calendar requests via the official CLI (read-only GET/POST query endpoints). */
async function fetchEvents(request, from, to) {
  const cal = await request('POST', 'calendars/primary', { user_id_type: 'open_id' });
  const row = Array.isArray(cal.calendars) ? cal.calendars[0] : null;
  const calendar = row && row.calendar;
  if (!calendar || calendar.type !== 'primary' || typeof calendar.calendar_id !== 'string' || !calendar.calendar_id) throw new ScheduleError('无法确认本人主日历。');
  const id = calendar.calendar_id;
  async function range(a, b, depth) {
    const data = await request('GET', 'calendars/' + encodeURIComponent(id) + '/events/instance_view', { start_time: String(Math.floor(a)), end_time: String(Math.floor(b)), user_id_type: 'open_id' });
    const rows = Array.isArray(data.items) ? data.items : (Object.keys(data).length === 0 ? [] : null);
    if (!rows) throw new ScheduleError('未收到完整的日程列表，请重试。');
    if (rows.length >= 1000) {
      if (depth >= 12 || b - a <= 120) throw new ScheduleError('日程过于密集，本次同步未完成。');
      const mid = a + (b - a) / 2;
      return [...await range(a, mid, depth + 1), ...await range(mid, b, depth + 1)];
    }
    return rows.filter(r => r && r.status !== 'cancelled').map(parseEvent).filter(e => e.end > a && e.start < b);
  }
  const all = await range(from, to, 0);
  return { calendarID: id, events: [...new Map(all.map(e => [e.id, e])).values()] };
}

module.exports = { parseEvent, applyEvents, fetchEvents, reminderDates, offsetText, ScheduleError };
