# Engagement playbook: how a reply stays welcome

A removed comment costs one thread. A ban costs the account, and with it every community at once.
This page records the rules the system now enforces, and the operating discipline that no prompt can
enforce for you.

## What happened on 2026-11-04 (evidence)

A reply to `r/EventProduction` ("Live Translation Apps and AI?") was removed by a moderator. The
thread explicitly asked for cheaper alternatives to Wordly, so recommending a product was on topic —
the problem was not the topic, it was the shape of the reply:

- It opened with the disclosure and then described the product: *"is designed for…"*, *"It accepts
  live audio input…"*, *"It supports multiple languages simultaneously and operates without requiring
  speakers to change how they present"*. That is a spec sheet, not a person answering a question.
- It never said what a person would actually do, and never admitted a limit or a trade-off.
- The same subreddit also runs an account-age gate (`AutoModerator`: *"Your account must be at least
  2 days old to comment in this subreddit"*), which means the moderators are actively filtering for
  low-trust accounts.

Both signals point the same way: the reply looked automated and promotional, and the community is
already defensive about exactly that.

## Rules the system enforces

| Rule | Where | Effect |
| --- | --- | --- |
| A pitch cannot be recorded as published unless the community's `self_promotion` is `allowed` | `comments::record_publication` | `409` with `self-promotion_status=unknown: …`. `unknown` is not permission. |
| `ask_mods` is not permission either | same | Ask first, record `allowed`, then publish. |
| The helpful variant may not name the product | `domain::comment::validate` | Rejected draft, regenerated without the product. |
| Machine phrasing is rejected | `domain::comment::validate` (`MACHINE_PHRASES`) | "I hope this helps", "it's important to note", "leverage", "seamless", "game-changer", "furthermore", "in conclusion", emoji, `!!` — all rejected. |
| Missing affiliation disclosure on a pitch | `domain::comment::validate` | Rejected draft. |
| The prompt states the community's recorded rules and the voice rules | `modules::generative::engagement_rules` | Drafts stop sounding like marketing before a human reads them. |

The policy fields live on the community (`PATCH /api/v1/communities/{id}`, and the Communities page):
`self_promotion`, `min_account_age_days`, `min_comment_karma`, `flair_required`,
`promo_cooldown_days`, `rules_summary`. Record what you actually read, with the rule's wording.

## Operating discipline

1. **Answer the question first, product never in the opening sentence.** If the answer is complete
   without naming the product, stop there. That is the default outcome, not a failure.
2. **One sentence about the product, at most, and only when the thread asks for options.** No
   features, no prices, no capability lists, no "it supports…". First person, plain words.
3. **Earn the right to mention it.** In a new community, contribute at least a handful of genuinely
   useful, product-free replies before the first pitch. Record `allowed` only after reading the rules
   or hearing back from the moderators.
4. **Respect the clocks.** `min_account_age_days` for the account, `promo_cooldown_days` between
   promotional replies in the same community. Both are visible in the UI; neither is a suggestion.
5. **Never argue with a removal in the thread.** One polite message to the moderators, once. No
   re-posting the same comment, no second account: ban evasion is a sitewide ban, not a subreddit one.
6. **Never claim experience you do not have.** The validator rejects the usual phrases; it cannot
   catch a rewritten claim. That judgement is yours.
7. **Read `rules_summary` before every pitch.** If it is empty, the community's rule was never read,
   and `unknown` blocks the publication by design.

## If a comment is removed

1. Open the removal notice and read the exact rule quoted. Do not guess.
2. Message the moderators once, short and specific: what was removed, that you work on the product,
   that you will keep replies non-promotional in their subreddit, and ask what they prefer.
3. Record `self_promotion` as `forbidden` unless they say otherwise. Leave it recorded: a later
   session must not re-learn it the hard way.
4. Do not publish the same text anywhere else in the same subreddit. Rewrite from scratch or skip the
   thread.

## What the system cannot do

- It cannot verify your account's age or karma, or whether a subreddit requires flair. It stores what
  you recorded and shows it next to the draft.
- It cannot tell whether a specific thread's culture tolerates a recommendation. When in doubt, the
  helpful variant is always available and never needs the product.
- It cannot undo a removal. It can stop the next one.
