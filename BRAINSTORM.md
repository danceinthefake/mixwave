# mixwave — real-time collaborative studio

A real-time collaborative music studio. One global studio,
anyone with the URL joins a single shared jam; pick up an
instrument — guitar, keyboard, or drums — and play alongside
everyone else online. Built on **Vue + Elixir/Phoenix/LiveView**.

**Non-goal**: studio-quality timing sync. Real musical performance
needs <30 ms end-to-end; WebSocket round-trips can't hit that
without WebRTC. mixwave is a best-effort jam-along — visual
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
| **OTP fault tolerance** | A `Mixwave.Studio.Room` GenServer holds room state (recent events for join-time replay). On the v2 supervisor LiveView, the chaos button kills it → supervisor restarts in <100 ms → users see a brief "reconnecting" → the jam resumes |
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
mixwave/
├── BRAINSTORM.md (this file)
├── README.md
├── mix.exs
├── lib/
│   ├── mixwave/
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
│   └── mixwave_web/
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
3. ✅ **Mixwave.Chambers context** (renamed from Studio) — note
   broadcast + subscribe helpers wrapping Phoenix.PubSub.
4. ✅ **Phoenix.Presence module** at `mixwave_web/channels/presence.ex`
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
    via `Mixwave.RestartWatcher`. Every kill writes to the audit log.
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
    target `MixwaveWeb.Endpoint` via `:rpc.call`; `Mixwave.Drain`
    broadcasts `system:drain` on SIGTERM so clients see the amber
    "Server restarting" banner and reconnect to the survivor.
20. ⏳ README + GIF + open-source — README is comprehensive (479
    lines, brand assets, badge plumbing) but **no embedded GIF or
    screenshot** of the app in action. Coverage badge URLs still
    say `OWNER/REPO`. See Punch list.
21. ⏳ Public URL — `fly.toml` configures `mixwave.fly.dev` but
    we haven't actually pushed a deploy yet. User-action item.

## 5a. Audit punch list (2026-05-19)

One thread of v1–v3 is still genuinely open (one more is paused
on a non-code decision):

- **README walkthrough media** (v3 #20) — capture a short loop
  of two browsers jamming, drop it into README, fix the
  `OWNER/REPO` badge URLs.
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
7. ✅ Chambers.Server GenServer + Mixwave.Chambers context + Presence
   module. (Renamed from Studio.Room / Mixwave.Studio.)
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
- **Anti-spam**: ✅ shipped — `Mixwave.RateLimiter` caps each user
  at 20 note events/sec/chamber via an ETS fixed-window bucket;
  drops past budget emit `[:mixwave, :chamber, :note_dropped]`
  which the admin Dashboard surfaces as "Notes — dropped".
- **CSP**: ✅ shipped — `MixwaveWeb.Plugs.SecurityHeaders` emits a
  per-request Content-Security-Policy header. Prod is nonce-based
  with no `'unsafe-inline'` for scripts; dev is permissive enough
  for Vite HMR + LiveReloader.
- **Touch ergonomics**: ✅ shipped — `.pad-touch` utility kills
  iOS long-press callout, blue tap-highlight overlay, and stray
  text selection on every pad button; the floating dock and stage
  padding use `env(safe-area-inset-bottom)` so the home indicator
  doesn't cover controls; the dock collapses instrument tabs to
  their colored dot below `sm:` so all 7 fit a 360 px viewport.
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
- **Graceful shutdown / drain**: ✅ shipped — `Mixwave.Drain`
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
  one-glance snapshot via `Mixwave.SystemHealth` — BEAM (processes,
  atoms, run queue, schedulers, reductions, ports), memory
  breakdown by segment (processes, binary, code, ETS, atom,
  system), our two ETS tables' size + memory, and Postgres
  connections (via `pg_stat_activity`). Refreshes every 2 s; no
  graphs (LiveDashboard at `/dev/dashboard` is the time-series
  view).
- **Rate limits dashboard**: ✅ shipped — `/admin/rate-limits` is
  fed by a new `Mixwave.Telemetry.RateLimitDrops` GenServer that
  subscribes to `[:mixwave, :chamber, :note_dropped]`. Two
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
