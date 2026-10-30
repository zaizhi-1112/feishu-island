'use strict';
// Port of Danmu/AppearanceMCP.swift whitelist validation for danmu appearance.

const DEFAULTS = Object.freeze({ version: 1, name: '中台默认', background: null, foreground: null, border: null, fontSize: 28, corner: 12, motion: 'scroll', speed: 100, bubble: 'none', backgroundEnabled: true, borderEnabled: true });

function luminance(hex) {
  const rgb = parseInt(hex.slice(1), 16);
  const c = [16, 8, 0].map(s => { const x = ((rgb >> s) & 255) / 255; return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); });
  return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}

function validate(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  if (!Object.keys(input).every(k => Object.prototype.hasOwnProperty.call(DEFAULTS, k))) return null;
  const a = { ...DEFAULTS, ...input };
  const integer = (k, lo, hi) => Number.isInteger(a[k]) && a[k] >= lo && a[k] <= hi;
  if (!integer('version', 1, 1) || !integer('fontSize', 22, 44) || !integer('corner', 0, 24) || !integer('speed', 40, 240)) return null;
  if (!['none', 'dark', 'light', 'custom'].includes(a.bubble) || !['scroll', 'static'].includes(a.motion)) return null;
  if (typeof a.name !== 'string' || !a.name.trim() || a.name.length > 40) return null;
  if (typeof a.backgroundEnabled !== 'boolean' || typeof a.borderEnabled !== 'boolean') return null;
  for (const k of ['background', 'foreground', 'border']) {
    if (a[k] === null) continue;
    if (typeof a[k] !== 'string' || !/^#[0-9A-Fa-f]{6}$/.test(a[k])) return null;
  }
  if ((a.background === null) !== (a.foreground === null)) return null;
  if (a.bubble !== 'none' && a.backgroundEnabled !== false && a.background && a.foreground) {
    const x = luminance(a.background), y = luminance(a.foreground);
    if ((Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05) < 4.5) return null;
  }
  return a;
}

/** Resolved colors for the renderer, mirroring DanmuPlayback.applyAppearance. */
function resolve(a) {
  let background = a.background, foreground = a.foreground, border = a.border;
  if (a.bubble === 'dark') { background = background || 'rgba(20,23,28,0.90)'; foreground = foreground || '#ffffff'; }
  if (a.bubble === 'light') { background = background || 'rgba(255,255,255,0.94)'; foreground = foreground || '#1a1f26'; }
  const backdrop = a.bubble !== 'none' && a.backgroundEnabled !== false;
  if (a.bubble === 'none' || a.borderEnabled === false) border = null;
  return { fontSize: a.fontSize, corner: a.corner, speed: a.speed, motion: a.motion, background: backdrop ? (background || 'rgba(0,0,0,0.76)') : null, foreground: foreground || '#ffffff', border, outline: a.bubble === 'none' };
}

module.exports = { DEFAULTS, validate, resolve, luminance };
