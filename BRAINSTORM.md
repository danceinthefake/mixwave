# mixwave — real-time collaborative studio

A Vue + Elixir/Phoenix/LiveView showcase. **One global studio**:
anyone who hits the URL joins a single shared jam. Pick up an
instrument — guitar, keyboard, or drums — and play alongside
everyone else online in real time. No accounts. No separate rooms
(in v1). The point is to make the case for **Vue + Elixir** by
building the kind of app this stack was made for: live, multi-user,
fault-tolerant, distributable.

## 1. Audience & Goal

- **v1–v2 audience**: my team during sharing sessions. The talk is
  my tech-learning journey — Vue and Elixir/Phoenix/LiveView, the
  two stacks I picked up over the last year, finally meeting in one
  app.
- **v3 audience**: the wider dev community. Public deploy on a real
  domain, GitHub repo, writeup. The pitch: *"show the world what
  this stack can do that other stacks make hard."*
- **Primary goal**: a single project where each stack layer (Vue,
  Tone.js, LiveView, Phoenix Channels/PubSub, OTP fault-tolerance,
  BEAM distribution) has a concrete, demoable feature.
- **Non-goal**: studio-quality timing sync. Real musical
  performance needs <30 ms end-to-end; WebSocket round-trips can't
  hit that without WebRTC. We sell a **best-effort jam-along** —
  visual presence + fast-but-not-instant audio fanout — and
  acknowledge it openly in the UI.

## 2. The Stack and What Each Layer Brings (revised)

| Layer | Flagship feature |
| --- | --- |
| **Vue 3.5** | Three instrument pads — GuitarPad, KeyboardPad, DrumPad — touch + key-down input with press animations |
| **Tone.js** | Client-side audio synthesis. `MembraneSynth` for drums, `PolySynth` for keyboard, `PluckSynth` for guitar chords. ~30 KB; smaller than the howler+samples we'd ship otherwise |
| **LiveView** | Room shell — presence sidebar, instrument switcher, latency-hint footer; hosts the Vue islands |
| **Phoenix.PubSub** | Sub-100 ms fanout of note events to all connected players. The "everyone hears everyone" backbone |
| **Phoenix.Presence** | "Who's in the room, what instrument they have" — sidebar list, updates live on join/leave/switch |
| **OTP fault tolerance** | A `Mixwave.Studio.Room` GenServer holds room state (recent events for join-time replay). On the v2 supervisor LiveView, the chaos button kills it → supervisor restarts in <100 ms → users see a brief "reconnecting" → the jam resumes |
| **BEAM distribution (v3)** | Multi-node Fly deploy. Players on node 1 + node 2 jam together; PubSub + Presence cross-node fanout is native — no Redis, no Kafka, no message broker |

This is honestly a **better** stack-showcase than the original
upload-app product. Real-time many-user collaboration is the
canonical "what BEAM was built for" story.

## 3. Demo Flow on Stage (5 minutes)

1. **Open the studio.** Page renders: instrument tabs (Drums /
   Keyboard / Guitar), presence sidebar showing only `ayu-merak-42`,
   a small footer line: *"best-effort sync — distant users may
   sound a beat off."*
2. **Tap to begin.** A "tap to enter the studio" overlay starts the
   Tone.js audio context (required by browser autoplay policy).
3. **Hit the drums.** Kick + snare + hi-hat. Sound plays locally
   with ~zero latency.
4. **Open a second tab** as `wani-macan-17`. They appear in the
   sidebar. Switch to keyboard, hold a chord.
5. **Both tabs hear both sounds.** Tab 1 plays its own drums
   instantly; receives + plays tab 2's keyboard via PubSub.
6. **(v2) Chaos button.** On the supervisor LiveView, kill the
   `Studio.Room` GenServer. Both tabs see "reconnecting" — the
   supervisor restarts the room within 100 ms — Presence
   re-converges — the jam resumes.
7. **(v3) Cross-node demo.** Open a third tab against a *second*
   Fly machine. Plays guitar. Tabs 1 + 2 — on the *first* machine —
   hear it. No code that says "talk to other nodes."

## 4. Tech Choices

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

## 5. Layout (revised)

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

## 6. Database Schema

Just `anonymous_users`. The jam is ephemeral — no songs, no
comments, no R2 storage. v2's "save the last 30 seconds" feature
will add a `jams` table at that point, not before.

## 7. Versions

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

12. Save last 30s of the jam (recent-events buffer extended →
    `Tone.Recorder` export → playback widget).
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
20. README + writeup + GIF + open-source.
21. Public URL (Fly default subdomain).

## 8. Build Order (high-level)

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

## 9. Decisions (locked)

- **Audio**: Tone.js synthesis (synth, polysynth, membrane, pluck).
- **Instruments v1**: guitar + keyboard + drums — all three.
- **Switching**: free, with **1-second cooldown** between switches.
- **Held notes on switch**: cut off when the user changes
  instrument. Cleaner than letting them ring through the change.
- **Mobile keyboard pad**: horizontal scroll for the full octave.
  Acceptable in v1.
- **Anti-spam**: defer — BEAM handles 2500 events/sec from 50
  spammers without breaking. Add throttling if it becomes an actual
  problem.
- **`anonymous_users` retention**: keep the 24-hour idle threshold
  unchanged for v1.
- **Recording**: not in v1; planned for v2.
- **Latency UX**: a small footer hint —
  *"Best-effort sync — distant users may sound a beat off."*
- **v1 code**: deleted now. We haven't deployed; no migration
  burden. Phoenix scaffold + anon-auth + sweeper + name generator
  + scaffold of live_vue / shadcn-vue / Tailwind survive verbatim.
