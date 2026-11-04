# Reply pacing, answered state and follow-ups

Feature: keep the reply workflow honest about Reddit's account rate limit, stop re-offering threads already
answered, and track threads that may get a reply back.

## Specs

- **S1** — The user's request, verbatim: "non so perché su reddit posso inviare un commento o post ogni 10'. è
  un limite del mio account? bisogna gestirlo sulla pubblicazione automatica nel Chrome widget o dove devi.
  inoltre devo poter segnare una risposta come inviata per evitare di perdere tempo su commenti e post a cui
  ho già risposto. devo però monitorare eventuali risposte degli utenti per poter rispondere nuovamente"
- **S2** — Reddit's rate limit is an account condition (karma, account age, per-subreddit rules). The system
  never claims to bypass it and never retries silently. It records the next allowed time and shows it: the
  configured floor `REPLY_MIN_INTERVAL_MINUTES` (default 10) after a recorded publication, or the exact wait
  reported by Reddit itself when the browser widget detects "you're doing that too much / try again in N
  minutes".
- **S3** — A lead whose reply was recorded as published no longer appears in the default reply queue; it is
  listed only with `?include_answered=1` (carrying `answered_at`), and `stats` reports `answered`.
- **S4** — Follow-ups exist per lead with state `waiting`, `answered` or `closed`. Only threads where a reply
  was recorded can be followed. The browser widget reports new replies it sees on the page; the server records
  the count and the timestamp. Server-side Reddit polling is out of scope because unauthenticated JSON returns
  403 (verified 2026-11-04 from a local machine and rejected in design), so nothing pretends to monitor Reddit
  without the user's browser.
- **S5** — The reply queue shows a pacing notice with the remaining wait and a switch between "To reply" and
  "Answered"; a follow-ups page lists threads waiting for an answer with the last reporter, the count and the
  actions `open`, `answered`, `closed`.
- **S6** — The extension reports the two signals the server cannot observe: the rate-limit wait and new replies
  on a followed thread. It never posts and never retries.

## Tasks

- [x] T1 · S2, S3, S4 · backend: migration, pacing in `/reply-console`, answered filter, follow-up endpoints and tests · commit 7d20590 (backend)
- [x] T2 · S3, S5 · frontend: pacing banner, To reply/Answered switch, `/follow-ups` page and Playwright coverage · commit 29aee2a
- [x] T3 · S6 · extension: rate-limit detection, countdown, new-reply reporting · commit 679aef1
- [x] T4 · S5 · docs: operations and reply-console pages, Reddit limit explanation · commit 8c7f5a4

## Log

- L1 (user): see S1.
- L2 (evidence): `https://www.reddit.com/r/<sub>/comments/<id>.json` returns `403` from this machine (2026-11-04),
  so server-side polling of Reddit is not implemented; the widget reports from the page the human opened.
- L3 (decision): the 10-minute wait is an account condition, not a product limit; the app records the floor and
  the wait Reddit announces, and never retries.
