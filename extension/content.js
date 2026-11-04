// Floating panel on a Reddit thread: shows the prepared reply for this URL, lets you pre-fill Reddit's
// comment box, and records the publication. It never submits anything: you press Reddit's Reply button.
(() => {
  const PANEL_ID = 'lead-radar-panel';
  if (document.getElementById(PANEL_ID)) return;

  const variants = ['helpful', 'soft_pitch', 'direct_pitch'];
  const labels = { helpful: 'Helpful', soft_pitch: 'Soft pitch', direct_pitch: 'Direct pitch' };
  const state = {
    item: null,
    variant: 'helpful',
    texts: {},
    busy: false,
    followup: null,
    rateLimitUntil: null,
    limitReported: '',
    followupReported: false,
  };

  const call = (path, method = 'GET', body) =>
    chrome.runtime.sendMessage({ type: 'api', path, method, body });

  const pageUrl = () => {
    const canonical = document.querySelector('link[rel="canonical"]');
    const raw = canonical?.href || `${location.origin}${location.pathname}`;
    return raw.split('#')[0].split('?')[0].replace(/\/$/, '');
  };

  function panel() {
    let root = document.getElementById(PANEL_ID);
    if (root) return root;
    root = document.createElement('section');
    root.id = PANEL_ID;
    root.setAttribute('aria-label', 'Lead Radar reply');
    document.body.appendChild(root);
    return root;
  }

  function textFor() {
    return state.texts[state.variant] ?? '';
  }

  function renderError(message) {
    const root = panel();
    root.innerHTML = '';
    const title = document.createElement('h2');
    title.textContent = 'Lead Radar Reply';
    const paragraph = document.createElement('p');
    paragraph.className = 'muted';
    paragraph.textContent = message;
    const row = document.createElement('div');
    row.className = 'row';
    const close = document.createElement('button');
    close.className = 'secondary';
    close.textContent = 'Close';
    close.addEventListener('click', () => root.remove());
    row.append(close);
    root.append(title, paragraph, row);
  }

  // Reddit announces its own account throttle in the page ("you're doing that too much, try again in 8
  // minutes"). We only report the wait it states: nothing is retried or resubmitted.
  const RATE_LIMIT_PATTERN =
    /(doing that too much|try again in)[^\d]{0,40}(\d{1,4})\s*(minute|min|second|sec|hour|hr)/i;

  function minutesFrom(match) {
    const value = Number(match[2]);
    const unit = match[3].toLowerCase();
    const minutes = unit.startsWith('sec')
      ? Math.ceil(value / 60)
      : unit.startsWith('hour') || unit === 'hr'
        ? value * 60
        : value;
    return Math.min(1440, Math.max(1, minutes));
  }

  async function reportRateLimit(minutes) {
    const key = String(minutes);
    if (state.limitReported === key) return;
    state.limitReported = key;
    state.rateLimitUntil = Date.now() + minutes * 60_000;
    const response = await call('/api/v1/reply-console/rate-limit', 'POST', { minutes });
    if (response.ok && typeof response.data?.retry_after_seconds === 'number') {
      state.rateLimitUntil = Date.now() + response.data.retry_after_seconds * 1000;
    }
    renderRateLimit();
  }

  function watchRateLimit() {
    const scan = (root) => {
      const text = root?.innerText;
      if (!text) return;
      const match = text.match(RATE_LIMIT_PATTERN);
      if (match) void reportRateLimit(minutesFrom(match));
    };
    scan(document.body);
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) scan(node);
        }
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  function renderRateLimit() {
    const slot = document.getElementById('lead-radar-limit');
    if (!slot || !state.rateLimitUntil) return;
    const tick = () => {
      const remaining = Math.round((state.rateLimitUntil - Date.now()) / 1000);
      if (remaining <= 0) {
        slot.textContent = 'Reddit throttle ended: you can reply again.';
        return;
      }
      const minutes = Math.floor(remaining / 60);
      const seconds = String(remaining % 60).padStart(2, '0');
      slot.textContent = `Reddit is limiting this account: wait ${minutes}:${seconds} before the next reply.`;
      requestAnimationFrame(() => setTimeout(tick, 1000));
    };
    tick();
  }

  // Comment timestamps are the only reliable signal that someone answered. When the page does not expose
  // them, we report nothing instead of guessing.
  function commentTimes() {
    const values = [];
    for (const element of document.querySelectorAll('time[datetime], faceplate-timeago[ts]')) {
      const raw = element.getAttribute('datetime') || element.getAttribute('ts');
      const parsed = raw ? Date.parse(raw) : NaN;
      if (!Number.isNaN(parsed)) values.push({ at: parsed, element });
    }
    return values.sort((left, right) => right.at - left.at);
  }

  function commentText(element) {
    const container = element.closest('shreddit-comment, .comment, article, li') || element.parentElement;
    return (container?.innerText || '').trim().slice(0, 400);
  }

  async function reportNewReplies() {
    if (state.followupReported || !state.followup || !state.item) return;
    const baselineRaw = state.followup.published_at || state.followup.last_reply_at;
    const baseline = baselineRaw ? Date.parse(baselineRaw) : NaN;
    if (Number.isNaN(baseline)) return;
    const newer = commentTimes().filter((entry) => entry.at > baseline + 60_000);
    if (newer.length === 0) return;
    state.followupReported = true;
    const latest = newer[0];
    await call(`/api/v1/opportunities/${encodeURIComponent(state.item.lead.id)}/followup`, 'POST', {
      state: 'waiting',
      new_replies: newer.length,
      last_reporter: (latest.element.closest('[data-testid], shreddit-comment')?.getAttribute('author') || '').slice(0, 80) || undefined,
      latest_excerpt: commentText(latest.element) || undefined,
      latest_reply_at: new Date(latest.at).toISOString(),
    });
  }

  function render() {
    if (!state.item) return;
    const root = panel();
    root.innerHTML = '';
    const lead = state.item.lead;

    const title = document.createElement('h2');
    title.textContent = lead.title || '(no title)';

    const meta = document.createElement('p');
    meta.className = 'muted';
    meta.textContent = `${lead.community ?? 'unknown community'} · ${lead.score ?? 'unknown'} ${lead.score_category ?? ''} · ${lead.qualification_status}`;

    const tabs = document.createElement('div');
    tabs.className = 'tabs row';
    for (const variant of variants) {
      const draft = state.item.comments.find((comment) => comment.variant === variant);
      if (!draft) continue;
      const button = document.createElement('button');
      button.type = 'button';
      button.setAttribute('role', 'tab');
      button.setAttribute('aria-selected', String(state.variant === variant));
      button.textContent = labels[variant] || variant;
      button.addEventListener('click', () => {
        state.variant = variant;
        render();
      });
      tabs.append(button);
    }

    const editor = document.createElement('textarea');
    editor.value = textFor();
    editor.setAttribute('aria-label', 'Reply text');
    editor.addEventListener('input', () => {
      state.texts[state.variant] = editor.value;
    });

    const status = document.createElement('p');
    status.className = 'muted';
    status.setAttribute('role', 'status');

    const followupLine = document.createElement('p');
    followupLine.className = 'muted';
    if (state.followup) {
      const stateLabel = state.followup.state;
      const replies = Number(state.followup.new_replies || 0);
      followupLine.textContent =
        replies > 0
          ? `Follow-up ${stateLabel} · ${replies} new repl${replies === 1 ? 'y' : 'ies'}${state.followup.last_reporter ? ` from ${state.followup.last_reporter}` : ''}`
          : `Follow-up ${stateLabel} · no new replies seen yet`;
    } else {
      followupLine.hidden = true;
    }

    const rateLine = document.createElement('p');
    rateLine.id = 'lead-radar-limit';
    rateLine.className = 'muted';
    rateLine.hidden = !state.rateLimitUntil;

    const row = document.createElement('div');
    row.className = 'row';
    const prefill = document.createElement('button');
    prefill.type = 'button';
    prefill.textContent = 'Pre-fill Reddit box';
    prefill.addEventListener('click', async () => {
      const ok = await prefillRedditEditor(editor.value.trim());
      status.textContent = ok
        ? 'Text put into the Reddit comment box. Check it and press Reply.'
        : 'Comment box not found: copy the text and paste it manually.';
    });

    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'secondary';
    copy.textContent = 'Copy';
    copy.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(editor.value.trim());
        status.textContent = 'Copied.';
      } catch {
        status.textContent = 'Clipboard blocked by the browser.';
      }
    });

    const mark = document.createElement('button');
    mark.type = 'button';
    mark.textContent = 'Mark as posted';
    mark.addEventListener('click', async () => {
      if (state.busy) return;
      state.busy = true;
      const response = await call(`/api/v1/opportunities/${encodeURIComponent(lead.id)}/reply`, 'POST', {
        variant: state.variant,
        body: editor.value.trim(),
        note: 'posted from the Lead Radar extension',
      });
      state.busy = false;
      status.textContent = response.ok
        ? 'Recorded as posted.'
        : `Not recorded: ${response.data?.error?.message || response.error || response.status}`;
    });

    const open = document.createElement('a');
    open.className = 'muted';
    open.target = '_blank';
    open.rel = 'noopener noreferrer';
    open.textContent = 'Open in Lead Radar';
    open.href = state.consoleBase ? `${state.consoleBase}/opportunities/${lead.id}` : '#';
    if (!state.consoleBase) open.hidden = true;

    const answered = document.createElement('button');
    answered.type = 'button';
    answered.className = 'secondary';
    answered.textContent = 'Mark answered';
    answered.hidden = !state.followup;
    answered.addEventListener('click', async () => {
      const response = await call(
        `/api/v1/opportunities/${encodeURIComponent(lead.id)}/followup`,
        'POST',
        { state: 'answered' },
      );
      status.textContent = response.ok
        ? 'Follow-up marked answered.'
        : `Not recorded: ${response.data?.error?.message || response.error || response.status}`;
      if (response.ok && state.followup) state.followup = { ...state.followup, state: 'answered' };
    });

    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'secondary';
    close.textContent = 'Close';
    close.addEventListener('click', () => root.remove());

    row.append(prefill, copy, mark, answered, close);
    root.append(title, meta, followupLine, rateLine, tabs, editor, row, status, open);
    if (state.rateLimitUntil) renderRateLimit();
  }

  function deepQuery(selector, root = document) {
    const direct = root.querySelector(selector);
    if (direct) return direct;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (node.shadowRoot) {
        const found = deepQuery(selector, node.shadowRoot);
        if (found) return found;
      }
    }
    return null;
  }

  async function prefillRedditEditor(text) {
    if (!text) return false;
    let editor = deepQuery('div[contenteditable="true"], textarea[name="text"], textarea');
    if (!editor) {
      const trigger = [...document.querySelectorAll('button, a, [role="button"]')].find((element) =>
        /add a comment|comment/i.test(element.textContent || ''),
      );
      trigger?.click();
      await new Promise((resolve) => setTimeout(resolve, 800));
      editor = deepQuery('div[contenteditable="true"], textarea[name="text"], textarea');
    }
    if (!editor) return false;
    editor.focus();
    if (editor.tagName === 'TEXTAREA') {
      editor.value = text;
    } else {
      document.execCommand('insertText', false, text);
      if (!editor.textContent?.includes(text.slice(0, 20))) {
        editor.textContent = text;
      }
    }
    editor.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }

  (async () => {
    const stored = await chrome.storage.local.get(['consoleBase']);
    state.consoleBase = String(stored.consoleBase || '').replace(/\/$/, '');
    const response = await call(`/api/v1/reply-console/match?url=${encodeURIComponent(pageUrl())}`);
    if (!response.ok) {
      // A thread outside the queue is the normal case: stay invisible instead of adding noise.
      if (response.status !== 404) {
        renderError(response.error || 'Could not reach Lead Radar. Check the extension options.');
      }
      return;
    }
    state.item = response.data;
    state.followup = response.data.followup ?? null;
    for (const comment of state.item.comments) {
      state.texts[comment.variant] = comment.body;
    }
    state.variant = state.item.comments[0]?.variant || 'helpful';
    render();
    watchRateLimit();
    void reportNewReplies();
  })();
})();
