# mixchamb — real-time collaborative studio

A real-time collaborative music studio. One global studio,
anyone with the URL joins a single shared jam; pick up an
instrument — guitar, keyboard, or drums — and play alongside
everyone else online. Built on **Vue + Elixir/Phoenix/LiveView**.

**Non-goal**: studio-quality timing sync. Real musical performance
needs <30 ms end-to-end; WebSocket round-trips can't hit that
without WebRTC. mixchamb is a best-effort jam-along — visual
presence + fast-but-not-instant audio fanout — and the UI
acknowledges it openly.

## 1. The Stack and What Each Layer Brings (revised)

| Layer | Flagship feature |
| --- | --- |
| **Vue 3.5** | Three instrument pads — GuitarPad, KeyboardPad, DrumPad — touch + key-down input with press animations |
| **Tone.js** | Client-side audio synthesis. `MembraneSynth` for drums, `PolySynth` for keyboard, `PluckSynth` for guitar chords. ~30 KB; smaller than the howler+samples we'd ship otherwise |
| **LiveView** | Room shell — presence sidebar, instrument switcher, latency-hint footer; hosts the Vue islands |
| **Phoenix.PubSub** | Sub-100 ms fanout of note events to all connected players. The "everyone hears everyone" backbone |
| **Phoenix.Presence** | "Who's in the room, what instrument they have" — sidebar list, updates live on join/leave/switch |
| **OTP fault tolerance** | A `Mixchamb.Studio.Room` GenServer holds room state (recent events for join-time replay). On the v2 supervisor LiveView, the chaos button kills it → supervisor restarts in <100 ms → users see a brief "reconnecting" → the jam resumes |
| **BEAM distribution (v3)** | Multi-node Fly deploy. Players on node 1 + node 2 jam together; PubSub + Presence cross-node fanout is native — no Redis, no Kafka, no message broker |

Real-time many-user collaboration is the canonical "what BEAM
was built for" story.

## 2. Tech Choices

### Frontend
- **Vue 3.5** + TypeScript (strict, `verbatimModuleSyntax`) + Vite 8
- **Tailwind v4** + **shadcn-vue** (Reka UI primitives, Lucide icons)
- **`live_vue` 1.2** — `<.vue v-component="…">` islands inside LV
- **Tone.js** — audio synthesis for all three instruments

### Backend
- **Elixir 1.18+** with **Phoenix 1.8** + **LiveView 1.1**
- **Ecto + Postgres** (just for `anonymous_users`)
- **Phoenix.PubSub** + **Phoenix.Presence** — the realtime backbone
- **`dns_cluster`** for v3 multi-node on Fly
- **Bandit** as the HTTP server

### Dropped from v1
- ❌ R2 / `ex_aws*` / `sweet_xml` / `hackney` — no audio files to store
- ❌ `howler` — replaced by Tone.js
- ❌ `songs` and `comments` schemas — jams are ephemeral
- ❌ `LibraryLive`, `UploadLive`, `SongLive`, `ManageLive`,
  `Player.vue` — replaced by a single `StudioLive`

### Hosting (unchanged)
- **Fly.io**. v3 multi-node via `fly scale count 2` + `dns_cluster`
- Postgres: Fly Postgres (low LV latency)
- Domain: Fly default subdomain through v3

## 3. Layout (revised)

```
mixchamb/
├── BRAINSTORM.md (this file)
├── README.md
├── mix.exs
├── lib/
│   ├── mixchamb/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── accounts/                  (kept verbatim from v1)
│   │   │   ├── anonymous_user.ex
│   │   │   ├── name_generator.ex
│   │   │   └── sweeper.ex
│   │   ├── accounts.ex                (kept)
│   │   ├── studio/
│   │   │   └── room.ex                GenServer — supervised, holds recent events for join replay
│   │   └── studio.ex                  context (broadcast_note, list_recent_events)
│   └── mixchamb_web/
│       ├── components/                layouts.ex, core_components.ex (kept, mostly)
│       ├── live/
│       │   └── studio_live.ex         the whole app
│       ├── plugs/
│       │   └── ensure_anon_user.ex    (kept)
│       ├── presence.ex                Phoenix.Presence module
│       ├── router.ex
│       └── user_auth.ex               (kept)
├── assets/
│   ├── css/app.css
│   ├── js/app.js
│   ├── vue/
│   │   ├── components/ui/             shadcn-vue (kept)
│   │   ├── instruments/
│   │   │   ├── DrumPad.vue            v1 step 1 — simplest pad
│   │   │   ├── KeyboardPad.vue        v1 step 2
│   │   │   └── GuitarPad.vue          v1 step 3
│   │   ├── PresenceBar.vue            optional — could stay in HEEX
│   │   ├── lib/
│   │   │   ├── audio.ts               Tone.js helpers (load synths once, play notes on demand)
│   │   │   └── utils.ts               cn() (kept)
│   │   └── index.ts                   live_vue entry (kept)
│   ├── vendor/heroicons.js
│   └── vite.config.mjs
├── priv/repo/migrations/
│   └── 20260508003052_create_anonymous_users.exs   (only this one survives)
├── config/
└── test/
```

## 4. Database Schema

Just `anonymous_users`. The jam is ephemeral — no songs, no
comments, no R2 storage. v2's "save the last 30 seconds" feature
will add a `jams` table at that point, not before.

## 5. Versions

### v1 — the studio works

1. ✅ **Scaffolding cleanup**: songs/comments migrations rolled back,
   v1 LiveViews + schemas + R2 wrapper + Player + howler all deleted.
2. ✅ **Chambers.Server GenServer** (renamed from Studio.Room) —
   supervised, holds the last 200 note events for join replay.
3. ✅ **Mixchamb.Chambers context** (renamed from Studio) — note
   broadcast + subscribe helpers wrapping Phoenix.PubSub.
4. ✅ **Phoenix.Presence module** at `mixchamb_web/channels/presence.ex`
   + tracking on join/instrument-switch from `ChamberLive`.
5. ✅ **ChamberLive at /:slug** (renamed from StudioLive) — page
   shell, instrument tabs, presence sidebar, "tap to enter" gate
   for `Tone.start()`. (Latency hint footer — see #11.)
6. ✅ **DrumPad.vue** — full drum kit (kick / snare / toms / hats /
   crashes / ride) across multiple style flavors. `MembraneSynth`
   for kick, `NoiseSynth` for snare/hat. Tap or keys.
7. ✅ **KeyboardPad.vue** — one octave with octave-shift. `PolySynth`
   over `Tone.Synth`. Click or `a–p` keys.
8. ✅ **GuitarPad.vue** — common chord buttons across style flavors.
   `PluckSynth` per string in a chord.
9. ✅ **PubSub wire-up** — Vue islands push notes to LV via
   `pushEvent`; LV broadcasts on `chamber:<slug>`; receives push
   back to Vue via `play_remote_note` JS commands; Vue plays via Tone.
10. ✅ **1-second cooldown** on instrument switch (`@switch_cooldown_ms`
    in `chamber_live.ex`).
11. ✅ **Latency hint copy** — small "Best-effort sync · distant
    players may sound a beat off" line sits directly above the
    floating dock on sm+ (hidden on mobile where the dock already
    fills the bottom strip).

### v2 — chaos button + recording + polish

12. ✅ Session recording + audio export — creator-opt-in REC
    toggle persists every note event to `chamber_events`
    (Postgres). "Play recording" replays via the same
    `replay_burst` Vue handler as the live 30 s request_replay,
    flagged `recordable: true` so the client taps `Tone.Recorder`
    on the master output. When the replay finishes (last note +
    1.5 s reverb tail) the captured Blob lights a "Download
    audio" button — file is `.webm` on Chrome/Firefox, `.mp4`
    on Safari (browser-chosen MIME, not re-encoded). Strict
    WAV needs `Tone.Offline` + a WAV encoder; deferred.
13. ✅ Supervisor LiveView with the chaos button — `/admin/system`
    kills a ChamberServer, watches it restart, tracks the count
    via `Mixchamb.RestartWatcher`. Every kill writes to the audit log.
14. ✅ Animation when others play — `remoteHit` prop on each pad
    flashes a CSS pulse driven by `play_remote_note` PubSub events.
15. ✅ Per-user volume control — master output slider on `Chamber.vue`
    sets `Tone.Destination.volume`; persisted per-user in localStorage.
16. ✅ More instruments — Bass, Synth, Kendang (Sundanese drum),
    Suling (bamboo flute) all shipped on top of the original three.
    Seven instruments total, each with multiple style flavors.

### v3 — multi-node + public release

17. ✅ Fly deploy scaffolded — `fly.toml` sets `DNS_CLUSTER_QUERY`,
    IPv6 distribution, kill-signal/timeout for graceful drain;
    `:dns_cluster` dep wired in `application.ex`. Actual
    `fly scale count 2` deploy is a deployment step, not code.
18. ✅ Cluster LiveView — `/admin/cluster` shows nodes, RTT
    (per-tick `:erpc.call` round-trip to `:erlang.node/0`,
    rendered next to each peer), process counts, memory,
    schedulers, OTP release, plus the drain button.
19. ✅ "Drain node N" button — `/admin/cluster` row action kills the
    target `MixchambWeb.Endpoint` via `:rpc.call`; `Mixchamb.Drain`
    broadcasts `system:drain` on SIGTERM so clients see the amber
    "Server restarting" banner and reconnect to the survivor.
20. ⏳ README + GIF + open-source — README is comprehensive (479
    lines, brand assets, badge plumbing). Coverage badge URLs now
    point at `danceinthefake/mixchamb` (resolve once CI is back on).
    README has an `<img>` slot reserved for `docs/walkthrough.gif`
    with capture instructions inline; the asset itself still has
    to be recorded. See Punch list.
21. ⏳ Public URL — `fly.toml` configures `mixchamb.fly.dev` but
    we haven't actually pushed a deploy yet. User-action item.

## 5a. Audit punch list (2026-05-19)

One thread of v1–v3 is still genuinely open (one more is paused
on a non-code decision):

- **README walkthrough GIF** (v3 #20) — capture a short loop of
  two browsers jamming and drop it into `docs/walkthrough.gif`
  (the README already points there with capture instructions
  inline). Badge URLs are already fixed.
- ⏸ **First deploy / public URL** (v3 #21) — paused: hosting
  platform not picked yet; CI is currently set to
  `workflow_dispatch` only in `.github/workflows/ci.yml`.

Done since the original audit:

- ✅ **Cross-node latency in ClusterLive** (v3 #18) — `:erpc.call`
  ping to `:erlang.node/0` per tick, microsecond delta via
  `:erlang.monotonic_time/1`, rendered as an RTT column next to
  each peer node (self row shows "—").

Everything else from the original scope (v1 jam loop, v2 recording
+ chaos + extra instruments, v3 cluster + drain) is shipped.

## 6. Build Order (high-level)

The original v1 build order — all complete except for the latency
hint, which is now tracked in §5a Punch list:

1. ✅ Rewrite BRAINSTORM.
2. ✅ Roll back songs + comments migrations; delete the migration files.
3. ✅ Delete v1 code: Library/Upload/Song/Manage LiveViews; Storage;
   Library context; `Library.Song` / `Library.Comment`; `VueDemo.vue`;
   `Player.vue`.
4. ✅ Drop deps: `ex_aws`, `ex_aws_s3`, `sweet_xml`, `hackney`, plus
   the npm `howler` + `@types/howler`.
5. ✅ Drop the audio MIME-type config in `config/config.exs`.
6. ✅ Add Tone.js (npm).
7. ✅ Chambers.Server GenServer + Mixchamb.Chambers context + Presence
   module. (Renamed from Studio.Room / Mixchamb.Studio.)
8. ✅ ChamberLive shell — empty room, presence sidebar, "tap to
   enter" overlay.
9. ✅ DrumPad.vue + full event roundtrip (push → broadcast →
   receive → play).
10. ✅ KeyboardPad.vue.
11. ✅ GuitarPad.vue.
12. ✅ Cooldown + latency hint both shipped.
13. ✅ Smoke test with multiple browsers.
14. ✅ **v1 shipped.**

## 7. Decisions (locked)

- **Audio**: Tone.js synthesis (synth, polysynth, membrane, pluck).
- **Instruments v1**: guitar + keyboard + drums — all three.
- **Switching**: free, with **1-second cooldown** between switches.
- **Held notes on switch**: cut off when the user changes
  instrument. Cleaner than letting them ring through the change.
- **Mobile keyboard pad**: horizontal scroll for the full octave.
  Acceptable in v1.
- **Anti-spam**: ✅ shipped — `Mixchamb.RateLimiter` caps each user
  at 20 note events/sec/chamber via an ETS fixed-window bucket;
  drops past budget emit `[:mixchamb, :chamber, :note_dropped]`
  which the admin Dashboard surfaces as "Notes — dropped".
- **CSP**: ✅ shipped — `MixchambWeb.Plugs.SecurityHeaders` emits a
  per-request Content-Security-Policy header. Prod is nonce-based
  with no `'unsafe-inline'` for scripts; dev is permissive enough
  for Vite HMR + LiveReloader.
- **Touch ergonomics**: ✅ shipped — `.pad-touch` utility kills
  iOS long-press callout, blue tap-highlight overlay, and stray
  text selection on every pad button; the floating dock and stage
  padding use `env(safe-area-inset-bottom)` so the home indicator
  doesn't cover controls; the dock collapses instrument tabs to
  their colored dot below `sm:` so all 7 fit a 360 px viewport.
- **Instrument composables**: ✅ shipped — extracted the two
  patterns every pad was duplicating into `assets/vue/lib/instrument.ts`:
  `useInstrumentFlash<L, R>` owns the local/remote pulse refs,
  timers, and the `watch` on `remoteHit`; `useInstrumentKeyboard`
  owns the window keydown/keyup listener pair, the
  `isTypingInForm` + `event.repeat` guards, and the AbortController
  lifecycle. All 7 pad components consume them — net **-270 lines**
  (378 deleted, 108 added) and per-instrument client chunks 8-16%
  smaller. GuitarPad still keeps its own tiny `onMounted`/
  `onUnmounted` for the window-level `pointerup` listener that
  releases drag-off chords.
- **Lazy Vue islands**: ✅ shipped — `assets/vue/index.ts` resolver
  drops `eager: true` from the `import.meta.glob` calls. live_vue
  already accepts `Promise<Component>` in its `ComponentMap`
  (`deps/live_vue/assets/types.ts:27-28`), so Vite splits each
  `.vue` file into its own chunk and bundles Tone.js + `audio.ts`
  + `tonejs-instruments` into a shared chunk that loads only when
  a chamber actually mounts an instrument. Entry bundle dropped
  from 583 KB / 163 KB gzipped to **162 KB / 51 KB gzipped**
  (-72% raw, -69% gzipped). The audio chunk is ~290 KB / 70 KB
  gzipped and ships lazily.
- **A11y baseline**: ✅ shipped — every instrument-pad button
  carries an `aria-label` with the pad's name plus its keyboard
  shortcut hint; style-flavor buttons announce selection via
  `aria-pressed`; the floating dock's instrument tabs expose
  `aria-label` (so the mobile-collapsed dots are still announced)
  and `aria-pressed` for the active tab; the REC button is
  `aria-pressed` + `aria-label`, paired with a polite live region
  that announces "Recording started / stopped" on toggle;
  decorative dots (presence sidebar, dock tabs, REC indicator)
  are marked `aria-hidden="true"` so they don't double-read.
- **A11y tier-3 (reduced motion + visible focus)**: ✅ shipped —
  `assets/css/app.css` gained a `.pad-touch:focus-visible` rule
  (`outline: 2px solid var(--ring); outline-offset: 2px`) so the
  dock instrument tabs and every instrument pad show a clear
  keyboard-navigation ring without firing on mouse / touch focus.
  A `@media (prefers-reduced-motion: reduce)` block at the file
  bottom collapses every `animation-duration` and
  `transition-duration` to ~0 ms, silencing the REC pulse and the
  admin chamber kill-flash for motion-sensitive users. CSS bundle
  grew by 0.4 KB raw / ~10 B gzipped.
- **A11y tier-2 (touch targets + dock-presence labels)**: ✅
  shipped — dock instrument tabs gained `min-h-11 min-w-11
  justify-center` so the mobile dot-only state clears WCAG 2.5.5's
  44×44 minimum; keyboard black keys widened from `w-9` (36 px) to
  `w-11` (44 px) with a matching `1.375rem` positioning offset;
  the bottom-of-dock presence-avatar initials now carry an
  `aria-label` with `<primary-name> · <display-name> on
  <instrument>` so screen readers identify each jammer instead of
  reading "J" "K" "L" (the avatars were `title=`-only before,
  which AT can't reliably surface).
- **User alias**: ✅ shipped — additive nickname on top of the
  auto-generated `display_name`. Inline editor at the bottom of
  the Jamming panel; alias renders above the anon name, never
  replaces it. 32-char cap; blank input clears.
- **Admin Ops tab**: ✅ shipped — `/admin/ops` combines an audit
  log (every kill / drain / force-expire / sweep / broadcast
  writes a row to `admin_actions`) with a Broadcast banner form
  (5/15/30/60 min). The banner stores in `banners`, broadcasts on
  `system:banner` PubSub, and a `BannerHook` on_mount plants it on
  every browser LV so the message live-updates without polling.
- **Per-chamber drill-down**: ✅ shipped — clicking a row in the
  Chambers tab goes to `/admin/chambers/:slug` with live note feed,
  presence list, recording status, GenServer uptime + restart
  count, and Kill / Delete actions (both audited). The Chambers
  sidebar tab stays highlighted via `current_view` override.
- **Per-user admin auth**: ✅ shipped — `admins` table with
  bcrypt-hashed passwords + a new Admins section on the Ops tab
  for add / delete. AdminSessionController first tries
  `Admins.authenticate/2`; on miss falls back to the env
  `ADMIN_USER` / `ADMIN_PASSWORD` (kept as a break-glass route
  if every DB row's password is lost). Each login stashes
  `:admin_username` in the session, the admin `live_session`
  pulls it into `:current_admin`, and audit rows now use
  `Audit.log_as/4` so they attribute to a real person instead
  of all reading "admin".
- **Graceful shutdown / drain**: ✅ shipped — `Mixchamb.Drain`
  sits at the tail of the supervision tree so it's the first
  process terminated on SIGTERM. Its `terminate/2` broadcasts
  `{:node_draining, Node.self()}` on `system:drain` PubSub, then
  sleeps a 3 s grace window while PubSub + Endpoint are still
  alive. Every browser LV subscribes via `BannerHook` and the
  layout paints an amber "Server restarting — reconnecting…"
  strip the moment the message lands. ChamberServer.terminate/2
  was already flushing the recording queue, so an in-progress
  recording is preserved across rolling deploys.
- **System health tab**: ✅ shipped — `/admin/health` surfaces a
  one-glance snapshot via `Mixchamb.SystemHealth` — BEAM (processes,
  atoms, run queue, schedulers, reductions, ports), memory
  breakdown by segment (processes, binary, code, ETS, atom,
  system), our two ETS tables' size + memory, and Postgres
  connections (via `pg_stat_activity`). Refreshes every 2 s; no
  graphs (LiveDashboard at `/dev/dashboard` is the time-series
  view).
- **Rate limits dashboard**: ✅ shipped — `/admin/rate-limits` is
  fed by a new `Mixchamb.Telemetry.RateLimitDrops` GenServer that
  subscribes to `[:mixchamb, :chamber, :note_dropped]`. Two
  sections: "Saturated right now" (ETS bucket walk for users at
  ≥80% of the 20/sec cap in the current window) and "Lifetime
  drops" (per-(user × chamber) counters since BEAM start).
  Resolves user_ids → display_name + alias via a new
  `Accounts.list_users_by_ids/1` bulk fetch.
- **`anonymous_users` retention**: keep the 24-hour idle threshold
  unchanged for v1.
- **Recording**: not in v1; planned for v2.
- **Latency UX**: a small footer hint —
  *"Best-effort sync — distant users may sound a beat off."*
- **v1 code**: deleted now. We haven't deployed; no migration
  burden. Phoenix scaffold + anon-auth + sweeper + name generator
  + scaffold of live_vue / shadcn-vue / Tailwind survive verbatim.
