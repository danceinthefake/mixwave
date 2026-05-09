# mixwave

Real-time collaborative music chambers — pick a chamber, pick an
instrument, jam alongside everyone else who has the link. Built as
a deliberate showcase for the **Vue + Elixir + Phoenix + LiveView**
stack: every layer's flagship capability is wired to a concrete,
demoable feature on the page.

> One project, every layer pulls its weight.
> WebSocket fan-out, hot-restartable rooms, cross-node clustering,
> client-side audio synthesis, fault-tolerant chaos demos — none of
> it bolted on, all native.

See [BRAINSTORM.md](./BRAINSTORM.md) for the talk-shape framing
and the original v1/v2/v3 cuts; this README is the as-shipped
snapshot.

---

## What's in the box

### Chambers

Two flavors of room, both backed by the same per-slug GenServer:

- **Chaos chamber** — public, always-on, anyone can wander in.
  Singleton. Default audio character is "echo" so overlapping
  players turn into a wash.
- **Secret chambers** — link-only, you create one. Closes itself
  if nobody but the creator joins within 30 minutes.

Each chamber has an **audio character** (one of *anechoic, room,
live, hall, cathedral, plate, spring, echo, vacuum*) — applied via
a master FX bus on the client so every instrument respects the
chamber's space. The creator can change the kind on the fly and
every connected user hears the room flip.

### Instruments

Seven instruments, each with multiple style flavors. All synthesis
runs client-side via **Tone.js** — the server only fans out note
metadata.

| Instrument | Style flavors |
|---|---|
| **Drums** (full kit, 11 pads, drummer's-eye layout) | Synth · 808 · Acoustic |
| **Keyboard** (3 octaves, scrollable on mobile) | Synth · Lead · Grand *(sampled)* |
| **Guitar** (8-chord pad with mini fingerings) | Synth · Electric · Rock · Nylon · Acoustic *(sampled)* · Mandolin |
| **Bass** (4-string × 6-fret board) | Synth · Sub · Slap |
| **Pad** (chord pad with octave shift) | Synth · Lush · Drone |
| **Suling** (Indonesian bamboo flute, 12-note chromatic row) | Synth · Bamboo *(sampled)* · Sweet |
| **Kendang** (Indonesian two-headed hand drum, 6-tone pad) | Synth · Wood |

Two of those styles stream real samples lazily from the
`tonejs-instruments` CDN on first selection. The rest are pure
DSP. Every pad shows its keyboard shortcut inline (hidden below
`sm:` on touch devices).

### Realtime jam

- **Phoenix.PubSub** fans note events from the playing client to
  every other connected user on the chamber's topic. Listeners
  hear the *sender's* chosen flavor, so the kit / piano / suling
  sound is coherent across the room.
- **Phoenix.Presence** powers the side panel ("who's in this
  chamber") and updates live on join / leave / instrument-switch.
- **Replay last 30 s** — the chamber's GenServer keeps a rolling
  events buffer; click the button and your client schedules every
  recent note to play back locally.
- **Volume slider** persists per-browser via localStorage.

### Admin (`/admin`)

Session-backed Basic Auth via `ADMIN_USER` / `ADMIN_PASSWORD` env
vars. Seven tabs, each its own LiveView:

| Tab | Surface |
|---|---|
| **Dashboard** | Live counters (chambers / users / running pids) + custom telemetry (notes/sec, totals, restart count, instrument breakdown) |
| **System** | Supervised singletons (Chambers.Supervisor, sweepers) + every running per-chamber GenServer; **Kill** flashes the row red and the supervisor brings it back |
| **Chambers** | Every chamber row with state badge (system / active / grace), presence count, last-activity, force-delete |
| **Users** | Anonymous users with last-active time + force-expire |
| **Activity** | Live firehose of every note across every chamber via a `Chambers.activity_topic/0` echo; pause + clear; capped at 200 events |
| **Sweepers** | Chambers + Users sweeper status (last run, last deleted, threshold) with **Run now** |
| **Cluster** | Connected BEAM nodes (Node.self() + Node.list()) with per-node uptime / processes / memory via `:rpc.call/4`; manual Connect form; **Drain** cycles the target's Endpoint via `Supervisor.terminate_child` + `restart_child` |

---

## Stack capability tour

Each row's "Where to look" is a feature you can poke at running locally.

| Layer | What it shows | Where to look |
|---|---|---|
| **Vue 3.5** + TypeScript strict | 7 instrument pads, edge-case mobile UX, transitions, single-island Vue tree to avoid live_vue's destroyed-hook quirk | `assets/vue/Chamber.vue` and `assets/vue/instruments/*.vue` |
| **Tone.js** | PolySynth + MembraneSynth + MonoSynth + NoiseSynth + Sampler + Reverb + Chorus + Distortion + Filter + Tremolo + master FX bus per chamber | `assets/vue/lib/audio.ts` |
| **Phoenix LiveView** | Chamber LV + 7-tab admin shell; HEEX components + streams; `kill-flash` keyframes triggered by data alone | `lib/mixwave_web/live/` |
| **Phoenix.PubSub** | Chamber audio fan-out, global activity firehose, restart-watcher topic — all cross-node native | `Mixwave.Chambers.broadcast_note/2` |
| **Phoenix.Presence** | "Who's jamming" panel + dock avatars; CRDT means cross-node converge with no extra wiring | `MixwaveWeb.Presence` |
| **OTP / GenServer / DynamicSupervisor + Registry** | One Server per chamber, supervised; transient restart strategy; chaos kill demo with red-flash recovery | `Mixwave.Chambers.Server` |
| **ETS** | Per-slug restart counter survives the very process it's counting | `:chamber_restart_counts` table, init in `Mixwave.Application` |
| **`:telemetry`** | Custom events `[:mixwave, :chamber, :note / :created / :deleted / :restarted]` feeding `Mixwave.Telemetry.Counters` for live dashboard cards + `Telemetry.Metrics` for LiveDashboard | `lib/mixwave/telemetry/counters.ex` + `lib/mixwave_web/telemetry.ex` |
| **BEAM distribution** | Cluster LV, manual `Node.connect/1` form, drain cycles a peer's Endpoint via `:rpc.call/4`; `dns_cluster` ready for prod auto-discovery | `MixwaveWeb.Admin.ClusterLive` |
| **Ecto + Postgres** | Anonymous users + chambers schemas; admin force-delete; sweepers aging out idle rows | `Mixwave.Accounts`, `Mixwave.Chambers` |

---

## Run it locally

### Prerequisites

- **Elixir 1.18+ / OTP 27+**
- **Node 22+**
- **Postgres 15+** (Docker is easiest):
  ```sh
  docker run -d --name mixwave-pg \
    -e POSTGRES_PASSWORD=postgres -e POSTGRES_USER=postgres \
    -p 5432:5432 postgres:16-alpine
  ```

The app uses no external API keys or storage — Tone.js samples
come from public CDN URLs the browser fetches directly.

### First-time setup

```sh
mix setup        # install deps, create DB, run migrations, build assets
mix phx.server   # start the server (Phoenix on 4000, Vite on 5173)
```

Visit [`http://localhost:4000`](http://localhost:4000). Pick
**Chaos chamber** to land in the public room, or **Secret
chamber** to spin up a private one with a sharable link.

### Useful commands

```sh
mix setup            # install deps + db + assets
mix ecto.reset       # drop + recreate db
mix phx.server       # dev server with Vite hot reload
mix assets.build     # one-shot Vite build (ONLY for prod prep — clears Vite dev mode)
mix assets.deploy    # production asset build + digest
mix test             # run the test suite
mix precommit        # compile --warnings-as-errors + format + test
```

> **Heads up:** running `mix assets.build` writes a manifest that
> the layout reads in production mode. In dev that breaks Vite's
> dynamic source serving. If you accidentally do this and chambers
> stop loading assets, run:
> ```sh
> rm -rf priv/static/.vite priv/static/assets priv/static/server.mjs
> ```
> and restart Phoenix.

### Multi-machine LAN testing

For testing with another device on your LAN:

1. Find this machine's LAN IP: `hostname -I`
2. Open ports 4000 (Phoenix) + 5173 (Vite) in your firewall.
   With `firewalld`:
   ```sh
   sudo firewall-cmd --add-port=4000/tcp
   sudo firewall-cmd --add-port=5173/tcp
   ```
3. Start the server with the LAN IP exposed:
   ```sh
   DEV_LAN_HOST=<your-lan-ip> mix phx.server
   ```
4. Both devices browse to `http://<your-lan-ip>:4000` (always use
   the LAN IP, not `localhost`, when `DEV_LAN_HOST` is set —
   otherwise the browser's Private Network Access check blocks
   the cross-network asset fetch).

---

## Multi-node cluster (the BEAM showcase)

Two BEAM nodes on the same machine, sharing one Postgres + one
Vite, connected via Erlang distribution. PubSub + Presence
automatically fan out across the cluster — no Redis, no Kafka, no
message broker.

### Spin up two nodes

```sh
# Terminal 1 — owns Vite on port 5173
DEV_LAN_HOST=<your-lan-ip> PORT=4000 \
  iex --sname mixwave1 --cookie shared -S mix phx.server

# Terminal 2 — borrows Terminal 1's Vite
DEV_LAN_HOST=<your-lan-ip> PORT=4001 SKIP_VITE=1 \
  iex --sname mixwave2 --cookie shared -S mix phx.server
```

Visit:

- `http://<your-lan-ip>:4000` — page served by node 1
- `http://<your-lan-ip>:4001` — page served by node 2
- `http://<your-lan-ip>:4001/admin/cluster` — admin → Cluster tab

> Use the **LAN IP** in the URL (not `localhost`) when
> `DEV_LAN_HOST` is set. Mixing them triggers Private Network
> Access preflights that Vite doesn't satisfy.

### Wire them together

In the **Cluster** tab on either node, type the peer's full node
name (e.g. `mixwave2@your-hostname`) into the **Connect** form.
The table grows; PubSub + Presence converge automatically.

### What to demo

1. Open a chamber in two private windows — one on `:4000`, one on
   `:4001`. Each lands on a different BEAM.
2. Tap a drum on `:4000` → it plays on `:4001`. Cross-node fan-out
   working.
3. Hit **Drain** on the `:4001` row in the Cluster tab on `:4000`.
   `:rpc.call/4` reaches across, `Supervisor.terminate_child` +
   `restart_child` cycle node 2's Endpoint. The browser tab on
   `:4001` drops + reconnects within ~100 ms; the jam in
   `:4000` keeps going.
4. Hit **Kill** on a chamber row in the **System** tab. Watch the
   row flash red, restart count tick up, and the chamber's events
   buffer reset. The connected players keep playing through it
   because PubSub + Presence are independent of the per-chamber
   GenServer.

---

## Admin

`/admin` is gated by HTTP-form login (Basic Auth was replaced for
UX). Credentials come from runtime config:

```sh
ADMIN_USER=admin ADMIN_PASSWORD=secret mix phx.server
```

Defaults in dev (override only if you want non-defaults locally):
`admin` / `dev`.

In prod the `AdminAuth` plug fails closed — a missing
`ADMIN_PASSWORD` env returns 503 on every `/admin/*` request.

---

## Code layout

```
mixwave/
├── BRAINSTORM.md                 talk shape + locked decisions (older)
├── README.md                     this file
├── lib/
│   ├── mixwave/
│   │   ├── application.ex        supervision tree + ETS bootstrap
│   │   ├── accounts/             anonymous users + name generator + sweeper
│   │   ├── chambers/             Chamber schema + per-slug Server + sweeper
│   │   ├── chambers.ex           context: CRUD + telemetry + activity firehose
│   │   ├── restart_watcher.ex    counts singleton-process restarts
│   │   └── telemetry/counters.ex subscribes to mixwave events for the dashboard
│   └── mixwave_web/
│       ├── components/layouts/   root + app layouts (HEEX)
│       ├── controllers/          AdminSessionController + admin login form
│       ├── live/
│       │   ├── chamber_live.ex   the user-facing chamber
│       │   ├── landing_live.ex   chaos / secret picker
│       │   └── admin/            7 admin LVs + shared shell
│       ├── plugs/                EnsureAnonUser + AdminAuth
│       └── router.ex
├── assets/
│   ├── css/app.css               Tailwind v4 + shadcn-vue tokens + per-instrument neon palette + kill-flash keyframes
│   ├── js/app.js                 LiveSocket + LiveVue bootstrap
│   ├── vue/
│   │   ├── Chamber.vue           single live_vue island; v-ifs the active pad
│   │   ├── instruments/          7 pads (DrumPad, KeyboardPad, GuitarPad, BassPad, SynthPad, SulingPad, KendangPad)
│   │   ├── lib/audio.ts          Tone.js engine registry + master FX bus + chamber-kind switching
│   │   └── components/ui/        shadcn-vue starter components
│   └── vite.config.mjs
├── priv/repo/migrations/         anonymous_users + chambers
├── config/                       dev / test / runtime / config
└── test/
```

---

## Stack

| Layer | What |
|---|---|
| Backend | Elixir 1.18+, **Phoenix 1.8** + **LiveView 1.1**, Ecto + Postgres, Bandit, `dns_cluster` |
| Realtime | **Phoenix.PubSub** for note + activity broadcasts, **Phoenix.Presence** for the jammer panel |
| Observability | `:telemetry` custom events + `Telemetry.Metrics` + Phoenix LiveDashboard |
| Frontend | **Vue 3.5** + TypeScript (strict), Vite 8, Tailwind v4, **shadcn-vue** (Reka UI), Lucide icons |
| LV ↔ Vue bridge | **`live_vue` 1.2** — Vue islands rendered inside LiveView |
| Audio | **Tone.js** — PolySynth, MembraneSynth, MonoSynth, NoiseSynth, Sampler streaming from `tonejs-instruments` CDN, master FX bus |
| Hosting (planned) | Fly.io with `dns_cluster` auto-clustering |

The HEEX side and the Vue island side share one design language —
shadcn-vue's CSS variables are wired in `assets/css/app.css` and
resolve to light/dark values via a `dark` class on `<html>`.

---

## License

Personal / learning project.
