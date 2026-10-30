'use strict';
// Window factory for the Windows build. Every page is a local file with the shared
// preload; no window loads remote content (the company login view lives in company.cjs).
const path = require('node:path');
const { BrowserWindow, screen } = require('electron');

const RENDERER = path.join(__dirname, '..', 'renderer');
const PRELOAD = path.join(__dirname, 'preload.cjs');
const ICON = path.join(__dirname, '..', 'assets', 'icon.png');

const secure = (extra = {}) => ({ preload: PRELOAD, sandbox: true, contextIsolation: true, nodeIntegration: false, spellcheck: false, backgroundThrottling: false, ...extra });

function lockNavigation(win) {
  win.webContents.on('will-navigate', e => e.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
}

// ---- top island ----
const ISLAND_W = 460, ISLAND_H = 470;
function islandDisplay(preference) {
  if (preference === 'cursor') return screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  return screen.getPrimaryDisplay();
}
function createIsland(preference) {
  const d = islandDisplay(preference);
  const win = new BrowserWindow({
    width: ISLAND_W, height: ISLAND_H, x: Math.round(d.bounds.x + (d.bounds.width - ISLAND_W) / 2), y: d.bounds.y,
    frame: false, transparent: true, resizable: false, movable: false, minimizable: false, maximizable: false, fullscreenable: false,
    skipTaskbar: true, hasShadow: false, alwaysOnTop: true, show: false, focusable: true, backgroundColor: '#00000000', title: '一切在岛',
    webPreferences: secure()
  });
  win.setAlwaysOnTop(true, 'pop-up-menu');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });
  lockNavigation(win);
  win.loadFile(path.join(RENDERER, 'island.html'));
  return win;
}
function placeIsland(win, preference) {
  if (!win || win.isDestroyed()) return;
  const d = islandDisplay(preference);
  win.setBounds({ width: ISLAND_W, height: ISLAND_H, x: Math.round(d.bounds.x + (d.bounds.width - ISLAND_W) / 2), y: d.bounds.y });
}

// ---- desktop danmu overlay ----
function createDanmu() {
  const d = screen.getPrimaryDisplay();
  const win = new BrowserWindow({
    ...d.bounds, frame: false, transparent: true, resizable: false, movable: false, skipTaskbar: true, hasShadow: false,
    alwaysOnTop: true, focusable: false, show: false, backgroundColor: '#00000000', title: '一切在岛 · 弹幕',
    webPreferences: secure()
  });
  win.setAlwaysOnTop(true, 'screen-saver');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });
  lockNavigation(win);
  win.loadFile(path.join(RENDERER, 'danmu.html'));
  return win;
}

// ---- settings / onboarding ----
function createSettings(section) {
  const win = new BrowserWindow({
    width: 1020, height: 760, minWidth: 860, minHeight: 600, title: '一切在岛 · 设置', icon: ICON, show: false,
    backgroundColor: '#14171c', autoHideMenuBar: true, webPreferences: secure()
  });
  win.setMenu(null);
  lockNavigation(win);
  win.loadFile(path.join(RENDERER, 'settings.html'), { hash: section || 'messages' });
  win.once('ready-to-show', () => win.show());
  return win;
}
function createOnboarding() {
  const win = new BrowserWindow({
    width: 1040, height: 760, minWidth: 900, minHeight: 680, title: '欢迎使用一切在岛', icon: ICON, show: false,
    backgroundColor: '#14171c', autoHideMenuBar: true, webPreferences: secure()
  });
  win.setMenu(null);
  lockNavigation(win);
  win.loadFile(path.join(RENDERER, 'onboarding.html'));
  win.once('ready-to-show', () => win.show());
  return win;
}

// ---- shortcut wheel ----
const WHEEL = 380;
function createWheel() {
  const p = screen.getCursorScreenPoint();
  const win = new BrowserWindow({
    width: WHEEL, height: WHEEL, x: Math.round(p.x - WHEEL / 2), y: Math.round(p.y - WHEEL / 2),
    frame: false, transparent: true, resizable: false, movable: false, skipTaskbar: true, hasShadow: false,
    alwaysOnTop: true, show: false, focusable: true, backgroundColor: '#00000000', title: '一切在岛 · 快捷轮盘', webPreferences: secure()
  });
  win.setAlwaysOnTop(true, 'screen-saver');
  lockNavigation(win);
  win.loadFile(path.join(RENDERER, 'wheel.html'));
  return win;
}

// ---- full-screen reminder ----
function createReminder() {
  const d = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const win = new BrowserWindow({
    ...d.bounds, frame: false, transparent: true, resizable: false, movable: false, skipTaskbar: true, hasShadow: false,
    alwaysOnTop: true, show: false, focusable: true, backgroundColor: '#00000000', title: '一切在岛 · 提醒', webPreferences: secure()
  });
  win.setAlwaysOnTop(true, 'screen-saver');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });
  lockNavigation(win);
  win.loadFile(path.join(RENDERER, 'reminder.html'));
  return win;
}

module.exports = { createIsland, placeIsland, createDanmu, createSettings, createOnboarding, createWheel, createReminder, PRELOAD, RENDERER, ICON, ISLAND_W, ISLAND_H };
