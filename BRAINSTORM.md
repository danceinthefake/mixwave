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

1. **Scaffolding cleanup**: roll back the songs/comments migrations,
   delete the v1 LiveViews + schemas + R2 wrapper + Player + howler.
2. **Studio.Room GenServer** — supervised, holds the last N note
   events for replay when a new client joins.
3. **Mixwave.Studio context** — `broadcast_note/2`, subscription
   helpers wrapping Phoenix.PubSub.
4. **Phoenix.Presence module** + tracking on join/instrument-switch.
5. **StudioLive at /** — page shell, instrument tabs, presence
   sidebar, latency-hint footer, "tap to enter" overlay for
   `Tone.start()`.
6. **DrumPad.vue** — five pads (kick / snare / hi-hat / open hat /
   crash). `Tone.MembraneSynth` for kick, `Tone.NoiseSynth` for
   snare/hat. Tap or `1–5` keys.
7. **KeyboardPad.vue** — one octave (12 keys). `Tone.PolySynth`
   over `Tone.Synth`. Click or `a–p` keys.
8. **GuitarPad.vue** — eight common chord buttons (C / Am / Dm / G
   / E / Em / F / B7). `Tone.PluckSynth` per string in a chord.
9. **PubSub wire-up** — Vue islands push notes to LV via
   `pushEvent`; LV broadcasts on `studio:lobby`; receives + pushes
   back to Vue via JS commands; Vue plays via Tone.
10. **1-second cooldown** on instrument switch.
11. **Latency hint copy** in the footer.

### v2 — chaos button + recording + polish

12. ✅ Session recording — creator-opt-in REC toggle persists
    every note event to `chamber_events` (Postgres). "Play
    recording" button materialises a full-session replay via the
    same `replay_burst` Vue handler used for the live 30s
    request_replay. Server-side batched flush (2s / 50 events /
    on terminate). Audio-file export (Tone.Recorder → WAV) still
    pending if needed.
13. Supervisor LiveView with the chaos button: kill Studio.Room,
    watch it restart, count restarts.
14. Animation when others play — instrument panel highlights
    briefly (CSS-driven via PubSub events).
15. Per-user volume control (Tone.Gain on the receive side).
16. More instruments (bass, synth pad, vocal sample bank).

### v3 — multi-node + public release

17. Fly deploy with `fly scale count 2`; `dns_cluster` autoclusters.
18. Cluster LiveView (nodes / process counts / cross-node latency).
19. "Drain node N" button — Presence rebalances; users on the
    drained node reconnect to the survivor.
20. README + GIF + open-source.
21. Public URL (Fly default subdomain).

## 6. Build Order (high-level)

1. Rewrite BRAINSTORM (this commit).
2. Roll back songs + comments migrations; delete the migration files.
3. Delete v1 code: Library/Upload/Song/Manage LiveViews; Storage;
   Library context; `Library.Song` / `Library.Comment`; `VueDemo.vue`;
   `Player.vue`.
4. Drop deps: `ex_aws`, `ex_aws_s3`, `sweet_xml`, `hackney`, plus
   the npm `howler` + `@types/howler`.
5. Drop the audio MIME-type config in `config/config.exs`.
6. Add Tone.js (npm).
7. `Studio.Room` GenServer + `Mixwave.Studio` context + Presence module.
8. StudioLive shell — empty room, presence sidebar, "tap to enter"
   overlay.
9. DrumPad.vue + the full event roundtrip (push → broadcast →
   receive → play). Once this works for one instrument, the others
   are mechanical.
10. KeyboardPad.vue.
11. GuitarPad.vue.
12. Cooldown + latency hint.
13. Smoke test with multiple browsers.
14. **Ship v1.**

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
- **User alias**: ✅ shipped — additive nickname on top of the
  auto-generated `display_name`. Inline editor at the bottom of
  the Jamming panel; alias renders above the anon name, never
  replaces it. 32-char cap; blank input clears.
- **`anonymous_users` retention**: keep the 24-hour idle threshold
  unchanged for v1.
- **Recording**: not in v1; planned for v2.
- **Latency UX**: a small footer hint —
  *"Best-effort sync — distant users may sound a beat off."*
- **v1 code**: deleted now. We haven't deployed; no migration
  burden. Phoenix scaffold + anon-auth + sweeper + name generator
  + scaffold of live_vue / shadcn-vue / Tailwind survive verbatim.
