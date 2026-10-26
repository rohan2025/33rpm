const tokenEl = document.getElementById('token');
const portEl = document.getElementById('port');
const statusEl = document.getElementById('status');

const LABELS = {
  connected: 'Connected to 33rpm',
  connecting: 'Connecting…',
  disconnected: 'Not connected',
  bad_token: 'Token rejected',
  no_token: 'No token set',
};

function renderStatus({ status, detail }) {
  statusEl.className = status || '';
  statusEl.textContent = (LABELS[status] || 'Unknown') + (detail ? ` — ${detail}` : '');
}

chrome.storage.local.get(['token', 'port']).then(({ token, port }) => {
  tokenEl.value = token || '';
  portEl.value = port || '';
});
chrome.storage.session.get(['status', 'detail']).then(renderStatus);
chrome.storage.onChanged.addListener((_changes, area) => {
  if (area === 'session') chrome.storage.session.get(['status', 'detail']).then(renderStatus);
});

document.getElementById('save').addEventListener('click', async () => {
  const port = Number(portEl.value) || 33333;
  await chrome.storage.local.set({ token: tokenEl.value.trim(), port });
  renderStatus({ status: 'connecting' });
});
