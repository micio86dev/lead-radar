# Reply queue: skip a lead, and a screen that can be read

Feature: let the operator say "I am not replying to this one" and get it out of the queue, and rebuild the
reply console so the workflow is legible. The page currently renders with a token vocabulary that does not
exist in this project, so most of its spacing, borders and colours are undefined.

## Specs

- **S1** — The user's request, verbatim: "in pagina reply-queue devi poter settare anche la possibilità di
  non voler rispondere al post, marcarlo per ignorarlo. Migliora la UI/UX di questa pagina perchè si capisce
  davvero poco. Usa una kill per esperto UX/UI".
- **S2** — `ReplyConsole.vue` and `FollowupList.vue` use `var(--surface)`, `var(--surface-alt)`,
  `var(--border)`, `var(--text)`, `var(--text-muted)`, `var(--space-2..5)`, `var(--radius)`, `var(--good*)`,
  `var(--warn*)`, `var(--bad*)`, `var(--accent*)` and `var(--focus)`: 21 names that are defined nowhere in
  `src/`. Every declaration that reads them is invalid at computed-value time, so gaps, padding, borders and
  colours fall back to the browser default. Both components must be written against the tokens that exist
  (`bg-raised`, `bg-sunken`, `border-line`, `text-ink`, `text-ink-muted`, `rounded-panel`, `rounded-control`,
  and the `.badge`, `.notice`, `.card`, `.page-head` component classes).
- **S3** — A lead can be marked as *not replying* with one of a fixed set of reasons
  (`not_relevant`, `no_product_fit`, `community_rules`, `already_handled`, `other`). The mark is persisted,
  audited, and reversible: "undo" returns the lead to the queue. The reason and the date stay visible in the
  Ignored view. An unknown reason answers `422`; skipping a lead whose reply was already recorded answers
  `409 lead_already_answered`.
- **S4** — `GET /api/v1/reply-console` accepts `view=to_reply` (default), `view=ignored`, `view=answered`,
  `view=all`, and always returns `stats` with `to_reply`, `ready`, `needs_drafts`, `answered`, `skipped`. The
  previous `include_answered=1` keeps working and means `view=all`, because the Chrome extension and the
  existing links use it. The three views are disjoint: a published lead is answered, a skipped lead that was
  never published is ignored.
- **S5** — On a wide screen the page is a master/detail queue: a list of every lead in the view (community,
  score band, state, and a per-row skip action) beside the workspace for the selected lead. Below `lg` the
  list stacks above the workspace. The single "Card 1 of 25" carousel with no overview goes away, and the
  count of each view is a tab with its number, so an empty queue and a filtered queue look different.
- **S6** — The workspace keeps the reading order the tests rely on: the post (title link, community, score,
  snippet) then `Your reply` immediately after it, in one `<article>`. Its actions are: `Copy reply`
  (primary), `Open on Reddit`, `I posted it`, and `Not replying`. Tone tabs (helpful, soft pitch, direct
  pitch) and the keyboard shortcuts (`j`/`k` move, `1`/`2`/`3` tone, `c` copy, `o` open, `p` posted, `g`
  generate) keep working; `s` marks the selected lead as not replying.
- **S7** — Copy for the screen is plain and states the constraint once: nothing is published by this system.
  The engagement recorder stays available but behind a disclosure, not in the main flow.
- **S8** — `docs/reply-console.md`, `docs/api.md` and the operations notes describe the skip state and the
  views. The features the product forbids do not change: no automatic publication, no retries.

## Tasks

- [x] T1 · S3, S4 · backend: migration `reply_skipped_at` / `reply_skip_reason`, skip endpoint, view
      filtering and stats, API tests · commit 300cb5c (backend)
- [x] T2 · S2, S5, S6, S7 · frontend: reply console rewritten on the real tokens, master/detail queue, skip
      action, tabs with counts · commit fc87d2e (frontend)
- [x] T3 · S2 · frontend: `FollowupList.vue` ported to the same tokens (same bug, sibling screen) · commit fc87d2e
- [x] T4 · S8 · docs and the Playwright expectations for the new structure · this commit

## Log

- L1 (user): see S1.
- L2 (evidence, 2026-11-05): `grep -rn 'var(--' src/components` returns only `ReplyConsole.vue` and
  `FollowupList.vue`; `grep -rn -- '--surface:\|--space-3:' src/` returns nothing, so the variables have no
  definition anywhere in the frontend. This is the most likely reason the page "si capisce davvero poco": it
  is largely unstyled, not merely dense.
- L3 (decision): the queue becomes a master/detail list instead of a carousel. A queue of 25 leads with no
  visible list gives no sense of what is waiting, and the familiar pattern for a queue is exactly a list
  beside a workspace.
- L4 (design source): `impeccable` skill, product register. The repo has no `PRODUCT.md`/`DESIGN.md` in the
  skill's format, so the design system in `src/styles/global.css` (`@theme` tokens plus the component layer)
  is the source of truth instead of running the interactive `teach` flow.
- L5 (evidence): the before/after screenshots at 1280px and 390px confirm the diagnosis. Before: no
  surfaces, no borders, no spacing, everything in one column under a "Card 1 of 3" label. After: tabs
  with counts, a visible list of what is waiting, and one workspace beside it.
- L6 (evidence): the global component layer styles a bare `button` as the primary filled button, so the
  first render of the list showed solid blue rows. Every non-primary button in the console now sets its
  own surface explicitly.
- L7 (decision): the countdown moved from `role="status"` to `role="timer"`. A live region that updates
  every second reads the whole throttle sentence again on each tick.
- L8 (forward): the API keeps `include_answered=1` as an alias for `view=all` because the Chrome
  extension and the existing links use it; `popup.js` only reads the first five items and does not care
  about the view.
