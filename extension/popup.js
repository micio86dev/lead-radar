const queue = document.getElementById('queue');
const consoleLink = document.getElementById('console');

async function load() {
  queue.innerHTML = '<li class="muted small">Loading…</li>';
  const response = await chrome.runtime.sendMessage({ type: 'api', path: '/api/v1/reply-console?limit=5' });
  if (!response.ok) {
    queue.innerHTML = `<li class="muted small">${response.error || `HTTP ${response.status}`}</li>`;
    return;
  }
  const { apiBase } = await chrome.storage.local.get(['apiBase']);
  consoleLink.href = `${String(apiBase || '').replace(/\/$/, '')}/reply-queue`;
  const items = response.data.items || [];
  if (items.length === 0) {
    queue.innerHTML = '<li class="muted small">Nothing ready: prepare drafts from the queue.</li>';
    return;
  }
  queue.innerHTML = '';
  for (const item of items) {
    const lead = item.lead;
    const li = document.createElement('li');
    li.className = 'item';
    const title = document.createElement('p');
    title.className = 'lead-title';
    title.textContent = lead.title || '(no title)';
    const meta = document.createElement('p');
    meta.className = 'muted small';
    meta.textContent = `${lead.score ?? 'unknown'} ${lead.score_category ?? ''} · ${item.comments.length} drafts`;
    const link = document.createElement('a');
    link.href = lead.url || '#';
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.textContent = 'Open thread →';
    li.append(title, meta, link);
    queue.append(li);
  }
}

document.getElementById('refresh').addEventListener('click', load);
load();
