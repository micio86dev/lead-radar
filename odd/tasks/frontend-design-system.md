# Frontend design system, sidebar shell and logo

Feature: replace the hand-written page CSS with a Tailwind-based design system on CSS variables, move
navigation into a left vertical menu, and give the product a logo. Scope is presentation only: routes,
API calls, data and copy stay as they are.

## Specs

- **S1** — The user's request, verbatim: "migliora la UI/UX, menu verticale a sinistra, cursor pointer su tutti
  gli elementi cliccabili, CSS ben progettato con tailwind, componenti riutilizzabili con shadcn, un bel
  design, con il logo (inventalo tu) colori in variabili css... cura usabilità e accessibilità."
- **S2** — Navigation is a left vertical menu on viewports from 1024px, sticky and grouped by task
  (Inbox, Reply, Sources, System). Every one of the 15 existing routes stays reachable, the current route
  carries `aria-current="page"`, and below 1024px the same single `<nav>` becomes a horizontal scroll strip
  instead of a second copy or a JS drawer.
- **S3** — Every clickable element shows `cursor: pointer`: `a[href]`, enabled `button`, `summary`,
  `select`, `label[for]`, checkbox and radio inputs and their labels. Disabled controls and
  `[aria-disabled="true"]` show `cursor: not-allowed` instead.
- **S4** — Tailwind CSS is the styling architecture. Colors, radii and shadows are CSS custom properties
  declared in one place; no component hardcodes a hex color. Both light and dark are served from the same
  tokens, dark following `prefers-color-scheme`.
- **S5** — Reusable components follow the shadcn contract: one component per primitive, variants declared
  with `class-variance-authority`, a `class` prop merged through `tailwind-merge`, and no per-page styling
  in the page. Primitives are `Button`, `Card`, `Badge`, `Notice`, `Field` and `EmptyState`, plus `@layer
  components` classes for markup-heavy structures (tables, description lists) that would lose readability
  as utility soup.
- **S6** — The logo is invented here: a quarter radar sweep (two arcs, an origin dot and a signal dot) drawn
  as inline SVG in `currentColor`, with the wordmark as real text next to it. The mark is `aria-hidden`;
  the favicon is the same geometry on an accent tile.
- **S7** — Accessibility and usability are part of the work, not a follow-up: visible focus ring on every
  interactive element, AA contrast for text and badges in both schemes, interactive targets of at least
  24×24 CSS px, working skip link, keyboard reachable navigation, `prefers-reduced-motion` respected, and
  no information carried by color alone.
- **S8** — Existing behavior is preserved. The Playwright contract stays green without editing it: skip
  link focused first, brand link second, the same level-1 headings and accessible names, and
  `aria-current="page"` on the queue switch. Pages stay server-rendered; no client JavaScript is added to
  read-only views.

- **S9** — The inbox starts a search from a `Start a search` panel on `/opportunities`: one form per
  validated and enabled Actor, an items field, an explicit confirmation checkbox and a submit button that
  stays disabled until the box is ticked. With no validated Actor the panel says so and links to `/apify`
  instead of offering a button that cannot work. Starting a run spends Apify credit under the existing
  server-side cost guard; the UI never bypasses it.
- **S10** — `/opportunities` shows only leads with score ≥ 60 by default. The floor is visible and
  editable in the filter form, the header states how many leads it hides (`N leads with score ≥ 60 of M`),
  and `Show all scores` removes it without touching the other filters. An empty `score_min` means no
  minimum.

## Tasks

- [x] T1 · S4, S7 · Tailwind 4 via `@tailwindcss/vite`, `@theme` tokens, base layer with cursor rules, focus
      ring, reduced motion, dark scheme, and `@layer components` carrying the legacy semantic classes so the
      unmigrated pages keep rendering
- [x] T2 · S6 · `Logo.astro` and `public/favicon.svg`
- [x] T3 · S2, S8 · `Layout.astro` shell: skip link, brand, grouped vertical nav, `aria-current`, sticky
      aside, mobile scroll strip, footer
- [x] T4 · S5 · `Button`, `Card`, `Badge`, `Notice`, `Field`, `EmptyState` primitives with CVA variants and
      a `cn` helper
- [x] T5 · S5, S8 · migrate `/` (dashboard) to the primitives as the reference page, leaving the other
      routes on the component layer
- [x] T6 · S7, S8 · verification: `bun run typecheck`, `bun run lint`, `bun run test`, `bun run build`,
      `bun run test:e2e`, plus a keyboard and contrast pass

## Log

- L1 (user): see S1.
- L2 (decision): the requested stack has three routes and the user answered "ok vai", so this follows the
  recommended route A — Tailwind plus Astro-native primitives with the shadcn variant contract, and
  shadcn-vue only where a Vue island already exists. shadcn/ui itself is React; converting the 19
  server-rendered pages into Vue islands would add client JavaScript and lose server-side token handling.
- L3 (constraint): `AGENTS.md` requires application artifacts in English, and the user's global rule forbids
  committing without an explicit request, so tasks record files and checks instead of commit hashes.
- L4 (evidence): before this feature there is no Tailwind, no shadcn and no `public/` directory in
  `lead-radar-frontend`; the only stylesheet is the 532-line hand-written `src/styles/global.css` with
  partial tokens and three hardcoded hex values at lines 301, 448 and 454.

- L5 (evidence): verification on 2026-11-04 from `lead-radar-frontend` — `bun run typecheck` 0 errors/0
  warnings over 44 files, `bun run lint` clean, `bun run test` 11/11 Vitest, `bun run build` complete, and
  Playwright 11 passed / 1 skipped against the built server on port 4399 (the skip is the suite's own
  "no lead with drafts in this environment" path). Port 4321 is held by the Docker frontend container, so
  the first Playwright run silently tested the stale container instead of this build; the rerun with
  `E2E_BASE_URL=http://localhost:4399` is the one that counts. The Docker image needs a rebuild because
  `package.json` and `bun.lock` gained tailwindcss, @tailwindcss/vite, class-variance-authority, clsx and
  tailwind-merge.
- L6 (scope): T5 migrated `/` only. The other 18 routes keep their markup and render through the component
  layer, so they inherit the new tokens, cursors and dark scheme without being rewritten. Migrating them is
  follow-up work, one slice per group of pages.
- L7 (user): "importiamo le opportunities con un pulsante che posso cliccare per avviare la ricerca e poi
  mostriamo solo quelle con percentuale maggiore di N (60 mettiamo di default)". Implemented as S9 and S10:
  the floor is inclusive (`score >= 60`, the API's `score_min`), and the header + `Show all scores` link
  make the default honest instead of silently hiding 174 of 196 leads.
- L8 (bug found): `ConfirmSubmit.vue` rendered its checkbox without `name="confirm"`, so the two
  server-guarded operations that require that field (`apify.run.start`, `opportunity.delete`) always
  answered `422 confirmation required` from the UI, and every instance reused `id="confirm-checkbox"`.
  Fixed in the same change; the checkbox now carries the field and a per-instance `useId`.
- L9 (blocked decision): production has no validated Actor, so the deployed panel would only show the
  honest "no validated Actor" branch. Registering one there needs the operator's verified `actor_id` and
  its input template; the local stack has two (`harshmaur`, `trudax`) but the template is not rendered
  anywhere in the UI, and inventing one would break the no-invented-integrations rule.
- L10 (delivery): the feature shipped as five frontend commits on `feature/lead-radar-mvp`
  (tailwind+tokens, logo/primitives/shell, dashboard migration, inbox floor + start-search panel +
  ConfirmSubmit fix, singular lead count) plus one backend commit for the deleted-content rule and two
  root commits (docs, submodule bump). The advisory counted 1545 authored lines since `main` across those
  commits, past the ~400-line slice: the boundaries above are the smallest reviewable units, because the
  stylesheet rewrite is one indivisible change and the remaining pages stay on the component layer
  instead of being rewritten. Further splitting would mean rewriting history for no review benefit.
- L11 (deploy): `railway up` run from inside a submodule uploads the **parent repository root**, so
  Railpack analyzes the wrong tree and the build fails before it starts (production untouched). The
  deployment that works is a `git archive HEAD` export into a scratch directory, `railway link -p
  <project> -e production -s <service>` there, then `railway up --ci -s <service>`. Both services
  deployed from their own committed tree that way.
