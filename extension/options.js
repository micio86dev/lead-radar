const apiBase = document.getElementById('apiBase');
const token = document.getElementById('token');
const status = document.getElementById('status');

chrome.storage.local.get(['apiBase', 'token']).then(({ apiBase: base, token: saved }) => {
  if (base) apiBase.value = base;
  if (saved) token.value = saved;
});

document.getElementById('save').addEventListener('click', async () => {
  const base = apiBase.value.trim();
  const value = token.value.trim();
  if (!base || !value) {
    status.textContent = 'Both fields are required.';
    return;
  }
  await chrome.storage.local.set({ apiBase: base, token: value });
  status.textContent = 'Saved locally.';
});

document.getElementById('test').addEventListener('click', async () => {
  status.textContent = 'Testing…';
  const response = await chrome.runtime.sendMessage({ type: 'api', path: '/api/v1/providers' });
  status.textContent = response.ok
    ? `Connected (${response.status}). Providers: ${(response.data || []).map((p) => `${p.provider}=${p.status}`).join(', ')}`
    : `Failed: ${response.error || `HTTP ${response.status}`}`;
});
