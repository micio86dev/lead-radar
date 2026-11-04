// All API traffic happens here: an extension service worker is not bound by the page's CORS rules,
// thanks to host_permissions, and the bearer token never reaches the page context.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.type !== 'api') return false;
  (async () => {
    const { apiBase, token } = await chrome.storage.local.get(['apiBase', 'token']);
    if (!apiBase || !token) {
      sendResponse({ ok: false, status: 0, error: 'Configure the API URL and token in the extension options.' });
      return;
    }
    try {
      const response = await fetch(`${String(apiBase).replace(/\/$/, '')}${message.path}`, {
        method: message.method || 'GET',
        headers: {
          authorization: `Bearer ${token}`,
          'content-type': 'application/json',
        },
        body: message.body === undefined ? undefined : JSON.stringify(message.body),
      });
      const text = await response.text();
      sendResponse({
        ok: response.ok,
        status: response.status,
        data: text ? JSON.parse(text) : null,
      });
    } catch (error) {
      sendResponse({ ok: false, status: 0, error: String(error) });
    }
  })();
  return true; // keep the message channel open for the async response
});
