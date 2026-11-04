# Reply console: fast, still human

## The problem it solves

The normal flow (open an opportunity → generate → go to the review queue → open the comment → approve →
copy → open Reddit → post → record publication → record engagement) is correct but slow: nine screens for
one reply. The reply console collapses it into one screen and one action, without giving up the human
decision.

## How it works

- `GET /api/v1/reply-console` returns a compact queue: every active lead that is `qualified` or
  `needs_review`, qualified first, then by score, each with a 700-character content snippet and its
  existing drafts.
- Each card has variant tabs (helpful, soft pitch, direct pitch), an inline editor pre-filled with the
  draft, and four actions: **Copy**, **Open thread**, **Generate drafts** (when missing), **I posted it**.
- `POST /api/v1/opportunities/:id/reply` performs one audited step: it saves the edited text as a new
  version, approves the comment, records the manual publication and, optionally, the engagement, then
  marks the lead's review as resolved. The same draft cannot be recorded twice.
- `POST /api/v1/reply-console/prepare` queues draft generation for the next leads without drafts (at most
  ten per call) so the queue is ready when you sit down.
- Keyboard: `j`/`k` next/previous, `1`/`2`/`3` variant, `c` copy, `o` open thread, `p` posted,
  `g` generate.

## What we deliberately do not do

Bazzly (and similar tools) scan Reddit, write the reply, **post it through warmed-up accounts** and add
votes — no human step, plus a browser extension that posts from your own session. That is exactly what
this product forbids by design:

1. `PROMPT.md` §14 and §29: "Never publish content automatically, even if an API or Actor appears capable
   of doing so"; human approval and manual publication are mandatory.
2. Posting through other accounts or automating your own session violates Reddit's terms, and the account
   risk lands on the operator, not on a vendor.

So the console removes the friction (no page hopping, no copy/paste chain, one action to record), but the
last click stays human: you copy, you post, you press **I posted it**.

If you want to go further, the honest next step is a **browser extension that opens the thread and
pre-fills the comment box** with the approved draft — the human still presses Reddit's Reply button. That
keeps the manual-publication rule while cutting the copy/paste step. It is not implemented yet.
