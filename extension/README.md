# Lead Radar Reply — Chrome extension (MV3)

Brings the prepared reply for the thread you are reading into the Reddit page, so replying costs one
paste and one click instead of a copy/paste round trip across tabs.

## Install (unpacked, ~1 minute)

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → select this `extension/` directory.
3. Open the extension **Options** and fill in:
   - API base URL: `https://backend-production-138f.up.railway.app` (or `http://localhost:8080`);
   - API token: the same `BOOTSTRAP_API_TOKEN` the dashboard uses.
4. Click **Test connection**: it lists provider statuses.
5. Open any Reddit thread that is in the queue. A panel appears bottom-right with the three drafts.

## What it does and does not do

- Reads your reply queue through the Lead Radar API (the token stays in `chrome.storage.local`, never in
  the page).
- Shows the drafts for the thread, lets you edit, copy, or **pre-fill Reddit's comment box**.
- **Never submits.** You press Reddit's Reply button yourself. Auto-posting is intentionally out of scope
  for this product: it violates Reddit's terms and the account risk lands on you.
- **Mark as posted** records the publication and closes the review in Lead Radar, exactly like the
  dashboard's "I posted it".

## Ban risk, honestly

Pre-filling is assistance, not automation, but Reddit's spam systems look at patterns: fast, similar
replies across many threads get filtered or the account restricted. Keep volume low, edit each reply to
the thread, never paste a link where the community forbids self-promotion, and prefer the `helpful`
variant. "Warmed-up" accounts and automatic upvotes/DMs — what tools like Bazzly sell — are exactly what
gets accounts banned; this extension does none of that.

## Reddit rate limits

If Reddit answers "you're doing that too much, try again in N minutes", that wait belongs to your Reddit
account (karma, account age, per-subreddit rules). The extension does not work around it: it reads the wait
Reddit itself announced, reports it to Lead Radar so the queue shows the same countdown, and shows it in the
panel. Nothing is retried, nothing is resubmitted, and no second account is involved.

## Follow-ups

On a thread where you already replied as posted, the panel shows the follow-up state and a **Mark answered**
button, and it reports new replies it can date from the page. When the DOM does not expose timestamps, it
reports nothing instead of guessing. The `Follow-ups` page in the dashboard lists what it received.

## Limits

- Reddit's DOM changes: the pre-fill uses best-effort selectors (new and old Reddit). If it cannot find
  the comment box, use **Copy**.
- The extension needs the API reachable from your browser; the token is a production credential.
