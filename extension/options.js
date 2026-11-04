const apiBase = document.getElementById('apiBase');
const token = document.getElementById('token');
const consoleBase = document.getElementById('consoleBase');
const status = document.getElementById('status');

chrome.storage.local.get(['apiBase', 'token', 'consoleBase']).then(({ apiBase: base, token: saved, consoleBase: dashboard }) => {
  if (base) apiBase.value = base;
  if (saved) token.value = saved;
  if (dashboard) consoleBase.value = dashboard;
});

document.getElementById('save').addEventListener('click', async () => {
  const base = apiBase.value.trim();
  const value = token.value.trim();
  if (!base || !value) {
    status.textContent = 'Both fields are required.';
    return;
  }
  await chrome.storage.local.set({
    apiBase: base,
    token: value,
    consoleBase: consoleBase.value.trim(),
  });
  status.textContent = 'Saved locally.';
});

document.getElementById('test').addEventListener('click', async () => {
  status.textContent = 'Testing…';
  const response = await chrome.runtime.sendMessage({ type: 'api', path: '/api/v1/providers' });
  status.textContent = response.ok
    ? `Connected (${response.status}). Providers: ${(response.data || []).map((p) => `${p.provider}=${p.status}`).join(', ')}`
    : `Failed: ${response.error || `HTTP ${response.status}`}`;
});
