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

async function loadFollowups() {
  const slot = document.getElementById('followups');
  const response = await chrome.runtime.sendMessage({
    type: 'api',
    path: '/api/v1/followups?state=waiting&limit=5',
  });
  const items = response.ok ? response.data?.items ?? [] : [];
  if (items.length === 0) {
    slot.hidden = true;
    return;
  }
  const withReplies = items.filter((item) => Number(item.new_replies) > 0).length;
  slot.textContent =
    withReplies > 0
      ? `${items.length} follow-up${items.length === 1 ? '' : 's'} waiting · ${withReplies} with new replies`
      : `${items.length} follow-up${items.length === 1 ? '' : 's'} waiting`;
  slot.hidden = false;
}

document.getElementById('refresh').addEventListener('click', () => {
  void load();
  void loadFollowups();
});
load();
loadFollowups();
