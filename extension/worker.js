// 33rpm service worker: owns the WebSocket to the Mac app and routes messages between it and the tab.
const PORT = 33333; // fixed: the app always listens here
const PING_MS = 20000;
const MAX_BACKOFF_MS = 30000;

let ws = null;
let ready = false;
let authFailed = false;
let backoff = 1000;
let retryTimer = null;
let pingTimer = null;

let activeTabId = null;
let lastState = null;
let lastQueue = null;

async function loadConfig() {
  const c = await chrome.storage.local.get('token');
  return { token: (c.token || '').trim(), port: PORT };
}

function setStatus(status, detail = '') {
  chrome.storage.session.set({ status, detail, at: Date.now() }).catch(() => {});
}

function rawSend(obj) {
  if (ws && ready && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
}

function pushCurrent() {
  rawSend(lastState ? lastState : { type: 'idle' });
  if (lastState && lastQueue) rawSend(lastQueue);
}

async function connect() {
  if (ws || authFailed) return;
  clearTimeout(retryTimer);
  const { token, port } = await loadConfig();
  if (ws) return; // another connect() won the race while we awaited storage
  if (!token) {
    setStatus('no_token', 'Paste the pairing token from the 33rpm app.');
    return;
  }

  let sock;
  try {
    sock = new WebSocket(`ws://127.0.0.1:${port}`);
  } catch (e) {
    scheduleRetry();
    return;
  }
  ws = sock;
  setStatus('connecting');

  sock.onopen = () => {
    sock.send(JSON.stringify({
      type: 'hello',
      token,
      client: '33rpm-extension',
      version: chrome.runtime.getManifest().version,
    }));
  };

  sock.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.type === 'welcome') {
      ready = true;
      backoff = 1000;
      setStatus('connected');
      clearInterval(pingTimer);
      pingTimer = setInterval(() => rawSend({ type: 'ping' }), PING_MS);
      pushCurrent();
      // Ask the tab for a fresh snapshot in case we were asleep.
      if (activeTabId != null) chrome.tabs.sendMessage(activeTabId, { type: 'resync' }).catch(() => {});
    } else if (msg.type === 'error' && msg.reason === 'bad_token') {
      authFailed = true;
      setStatus('bad_token', 'The app rejected the token. Copy it again from the 33rpm menu.');
    } else if (msg.type === 'command' && (msg.action === 'playVideo' || msg.action === 'search')) {
      openInMusicTab(msg);
    } else if (msg.type === 'command' && activeTabId != null) {
      const command = { type: 'command', action: msg.action };
      if (typeof msg.videoId === 'string' && /^[A-Za-z0-9_-]{6,20}$/.test(msg.videoId)) command.videoId = msg.videoId;
      chrome.tabs.sendMessage(activeTabId, command).catch(() => {});
    }
  };

  sock.onclose = () => {
    if (ws !== sock) return;
    ws = null;
    ready = false;
    clearInterval(pingTimer);
    if (!authFailed) {
      setStatus('disconnected', 'Is the 33rpm app running?');
      scheduleRetry();
    }
  };

  sock.onerror = () => {}; // onclose always follows
}

// Plays a song from the crate inside the YouTube Music tab we're tracking (or any open one), using YouTube Music's
// own in-page navigation: no page reload, so no "Leave site?" prompt and playback switches straight over.
async function openInMusicTab(msg) {
  let value;
  if (msg.action === 'playVideo' && /^[A-Za-z0-9_-]{6,20}$/.test(msg.videoId || '')) {
    value = msg.videoId;
  } else if (msg.action === 'search' && typeof msg.query === 'string' && msg.query.trim()) {
    value = msg.query.trim().slice(0, 200);
  } else {
    return;
  }

  let tabId = activeTabId;
  if (tabId == null) {
    const [tab] = await chrome.tabs.query({ url: 'https://music.youtube.com/*' });
    tabId = tab?.id ?? null;
  }
  if (tabId == null) {
    const url = msg.action === 'playVideo'
      ? `https://music.youtube.com/watch?v=${value}`
      : `https://music.youtube.com/search?q=${encodeURIComponent(value)}`;
    chrome.tabs.create({ url });
    return;
  }
  chrome.scripting.executeScript({
    target: { tabId },
    world: 'MAIN',
    func: navigateInPage,
    args: [msg.action, value],
  }).catch(() => {});
}

// Runs in the YouTube Music page itself.
function navigateInPage(action, value) {
  const app = document.querySelector('ytmusic-app');
  const navigate = (endpoint) =>
    app.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true, detail: { endpoint } }));
  const watch = (id) => navigate({
    commandMetadata: { webCommandMetadata: { url: `/watch?v=${id}`, webPageType: 'WEB_PAGE_TYPE_WATCH' } },
    watchEndpoint: { videoId: id },
  });
  if (!app) return;
  if (action === 'playVideo') {
    watch(value);
    return;
  }

  // Older sleeves have no video ID: search, then play the top result.
  navigate({
    commandMetadata: {
      webCommandMetadata: { url: `/search?q=${encodeURIComponent(value)}`, webPageType: 'WEB_PAGE_TYPE_SEARCH' },
    },
    searchEndpoint: { query: value },
  });
  const started = Date.now();
  let urlMatchedAt = 0;
  const timer = setInterval(() => {
    if (Date.now() - started > 10000) return clearInterval(timer);
    if (new URLSearchParams(location.search).get('q') !== value) return;
    urlMatchedAt ||= Date.now();
    if (Date.now() - urlMatchedAt < 700) return; // let the old results clear
    const link = document.querySelector('ytmusic-search-page a[href*="watch?v="]');
    const id = link && new URL(link.getAttribute('href'), location.origin).searchParams.get('v');
    if (id) {
      clearInterval(timer);
      watch(id);
    }
  }, 250);
}

function scheduleRetry() {
  clearTimeout(retryTimer);
  retryTimer = setTimeout(connect, backoff);
  backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
}

function goIdle() {
  activeTabId = null;
  lastState = null;
  lastQueue = null;
  rawSend({ type: 'idle' });
}

chrome.runtime.onMessage.addListener((msg, sender) => {
  const tabId = sender.tab?.id;
  if (tabId == null) return;

  if (msg.type === 'state') {
    // The playing tab wins; a paused tab only reports if it's already the active one or nothing is.
    if (activeTabId == null || tabId === activeTabId || msg.state === 'playing') {
      activeTabId = tabId;
      lastState = msg.track ? msg : null;
      pushCurrent();
    }
  } else if (msg.type === 'queue' && tabId === activeTabId && Array.isArray(msg.items)) {
    lastQueue = { type: 'queue', items: msg.items.slice(0, 12) };
    rawSend(lastQueue);
  } else if (msg.type === 'gone' && tabId === activeTabId) {
    goIdle();
  }
  connect();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabId === activeTabId) goIdle();
});

chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (tabId === activeTabId && info.url && !info.url.startsWith('https://music.youtube.com/')) goIdle();
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local' || !changes.token) return;
  authFailed = false;
  backoff = 1000;
  if (ws) ws.close();
  else connect();
});

// Alarms wake the worker if Chrome put it to sleep while the app was down.
chrome.alarms.create('keepalive', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener((a) => { if (a.name === 'keepalive') connect(); });

async function injectIntoOpenTabs() {
  const tabs = await chrome.tabs.query({ url: 'https://music.youtube.com/*' });
  for (const t of tabs) {
    chrome.scripting.executeScript({ target: { tabId: t.id }, files: ['content.js'] }).catch(() => {});
  }
}

// Earlier versions let people pick a port; the app only listens on 33333, so forget any saved one.
chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.remove('port').catch(() => {});
  injectIntoOpenTabs();
  connect();
});
chrome.runtime.onStartup.addListener(connect);
connect();
