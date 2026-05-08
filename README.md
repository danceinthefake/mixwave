# mixwave

A music app rebuilt to make the case for **Vue + Elixir** as a stack
worth knowing. Anonymous users upload audio files, browse a public
library, and play tracks through a persistent footer player. Same
domain as [`vue-ztm/music`](../vue-ztm/music) (a Zero-To-Mastery
course follow-along) — but the goal here is no longer "introduce Vue
to my team." It's **show what this stack can do that other stacks
make harder.**

See [BRAINSTORM.md](./BRAINSTORM.md) for the full audience, talk
shape, and per-layer flagship features.

## What it is right now (v1)

Same surface area as the original ZTM course's app, on the new stack:

- **Anonymous auth** — visit the site and you're handed a Javanese-
  flavored handle (`ayu-merak-42`, `wani-macan-17`) on first request.
  Idle users (24h+) are reaped by a supervised GenServer.
- **Upload** — drag-and-drop an mp3 / m4a / ogg / flac, ≤25 MB. The
  browser PUTs directly to Cloudflare R2 via a short-lived presigned
  URL; Phoenix never touches the bytes.
- **Library** — paginated public feed of every uploaded song.
- **Song detail** — title, description, genre, who uploaded, comments.
- **Manage** — your songs, delete (cascades to R2 + comments).
- **Persistent player** — Vue island in the root layout. Click play
  on a song; the footer player picks up the track and survives
  navigation (LiveView re-renders never reset playback).

What lands in **v2** (BRAINSTORM §7): listen-together rooms (Phoenix
Presence + sync'd playback), live comments stream (PubSub), waveform
island with click-to-seek, background transcoder + orphan sweeper,
supervisor LiveView with the chaos button. **v3** is multi-node + the
public release.

## Stack at a glance

| Layer | What |
| --- | --- |
| Backend | Elixir 1.18+, **Phoenix 1.8** + **LiveView 1.1**, Ecto + Postgres, Bandit, DNSCluster |
| Frontend | **Vue 3.5** + TypeScript, Vite 8, Tailwind v4, **shadcn-vue** (Reka UI primitives), Lucide icons |
| LV ↔ Vue glue | **`live_vue` 1.2** (`<.vue v-component="…">` islands inside LiveView) |
| Storage | **Cloudflare R2** (S3-compatible), presigned PUT/GET via `ex_aws_s3` |
| Audio | `howler.js` |
| Hosting (planned) | Fly.io, with `dns_cluster` autowiring for v3 multi-node |

The Phoenix HEEX side and the Vue island side share one design
language — shadcn-vue's CSS variables (`bg-background`,
`text-foreground`, `bg-primary`, etc.) are wired in `assets/css/app.css`
and resolve to light/dark values via a `dark` class on `<html>`.

## Run it locally

### Prerequisites

- **Elixir 1.18+ and Erlang/OTP 27+** — `asdf install elixir 1.19.x`
  or your distro's package
- **Node 22+** — for Vite (Phoenix's asset pipeline goes through
  `phoenix_vite` which calls `npm`; the project is on npm, not pnpm,
  because `phoenix_vite` hardcodes the `npm` binary)
- **Postgres 15+** — easiest path is Docker:
  `docker run -d --name mixwave-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_USER=postgres -p 5432:5432 postgres:16-alpine`
- **A Cloudflare R2 bucket + API token** — optional for first-boot;
  required for actual uploads/playback. See `.env.example`.

### First-time setup

```sh
# 1. Install all deps (Elixir + npm).
mix setup

# 2. Configure R2 (only required if you want uploads to work).
cp .env.example .env.local
# Fill in R2_ENDPOINT_HOST, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
# R2_BUCKET. The host pattern is <account_id>.r2.cloudflarestorage.com.
# Then in your shell:
set -a && source .env.local && set +a

# 3. Create + migrate the database.
mix ecto.setup

# 4. Run the server.
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000). You'll be handed an
anonymous identity on first request.

### Without R2 configured

The app still boots and renders. The library/manage/song pages work
against the database. Upload won't function (the presigned-URL step
calls R2), and the song-detail page replaces the play button with an
"audio source unavailable" notice.

That's by design — the BRAINSTORM commits to "fail loud on
misconfiguration" rather than silently writing into the wrong bucket.

### Useful commands

```sh
mix setup            # install deps + create db + run migrations + build assets
mix ecto.reset       # drop + recreate db
mix phx.server       # run the server (dev mode, with Vite hot reload)
mix assets.build     # one-shot asset build via Vite
mix assets.deploy    # production asset build + digest
mix test             # run the (currently small) test suite
mix precommit        # compile --warnings-as-errors + format + test
```

## Layout

```
mixwave/
├── BRAINSTORM.md             goal + talk shape + decisions
├── README.md                 this file
├── lib/
│   ├── mixwave/              domain
│   │   ├── accounts/         anonymous users + sweeper + name generator
│   │   ├── library/          songs + comments schemas
│   │   ├── library.ex        list/get/create context functions
│   │   ├── storage.ex        R2 wrapper (presign, head, delete, list)
│   │   └── application.ex    supervisor tree
│   └── mixwave_web/
│       ├── components/       layouts.ex, core_components.ex (HEEX)
│       ├── live/             LibraryLive, UploadLive, SongLive, ManageLive
│       ├── plugs/            EnsureAnonUser
│       ├── router.ex
│       └── user_auth.ex      LV on_mount that injects current_user
├── assets/
│   ├── css/app.css           Tailwind v4 + shadcn-vue tokens
│   ├── js/app.js             Phoenix LiveView + LiveVue + Player bootstrap
│   ├── vue/
│   │   ├── components/ui/    shadcn-vue starter components
│   │   ├── lib/utils.ts      cn() helper
│   │   ├── Player.vue        persistent footer player (howler)
│   │   ├── VueDemo.vue       live_vue demo (LV-driven todos)
│   │   └── index.ts          live_vue entry
│   └── vite.config.mjs
├── priv/repo/migrations/     anonymous_users / songs / comments
├── config/                   compile-time + runtime config
└── test/
```

## License

Personal/learning project. See [BRAINSTORM.md](./BRAINSTORM.md) §1
for the audience and goal.
