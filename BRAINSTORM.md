# mixwave — Vue + Elixir/Phoenix/LiveView showcase

A music app rebuilt to make the case for **Vue + Elixir** as a stack
worth knowing. Same domain as `vue-ztm/music`, but the goal is no
longer "introduce Vue to my team" — it's **show the world what this
stack can do that other stacks make hard.**

Each layer (Vue, Phoenix LiveView, Phoenix, BEAM/OTP) gets a flagship
feature so the talk and the public README can point at one thing per
layer and say "this is why."

## 1. Audience & Goal

- **v1–v2 audience**: my team during sharing sessions. The talk is my
  tech learning journey — Vue and Elixir/Phoenix/LiveView, the two
  stacks I picked up over the last year, finally meeting in one app.
- **v3 audience**: the wider dev community. Public deploy on a real
  domain, GitHub repo with a "you should try this" README, a writeup.
- **Primary goal**: a single project that shows the four-layer stack
  doing things other stacks make harder. Each layer's superpower has
  a concrete, demoable feature. Nothing abstract.
- **Non-goal**: a real production music platform. No transcoding
  pipeline, no royalties, no DMCA, no monetization.

## 2. The Stack and What Each Layer Brings

| Layer | What it brings | Flagship feature in mixwave |
| --- | --- | --- |
| **Vue 3.5** | Declarative reactivity, ergonomic component model | The persistent footer player + waveform-with-click-to-seek (rich client state, audio API, survives navigation) |
| **LiveView** | Server-driven reactive UI; HTML over WS, no client JS to maintain | Library list, song detail with live comments stream, manage page (zero JS hand-written for any of these) |
| **Phoenix** | First-class WebSocket Channels + PubSub + distributed Presence | Listen-together rooms — listeners sync playback + see each other's avatars |
| **BEAM/OTP — fault tolerance** | Supervised processes that auto-restart, "let it crash" | Transcode/waveform-extraction worker + a *chaos button* on a supervisor-tree LiveView (kill it, watch it restart in <100ms) |
| **BEAM/OTP — distribution** | Multi-node clustering with native message-passing across nodes | Cross-node Presence in listening rooms; "drain this node" button rebalances live listeners onto the surviving node |

That's six features, each demoing exactly one capability.

## 3. Demo Flow on Stage (5 minutes)

A talk-track that hits every layer in order, with no slide that says
"trust me":

1. **Open two browser tabs, each as a different anonymous user.**
   Both users appear in the listening room (LiveView Presence).
2. **Press play on tab A.** Tab B starts at the same offset
   (Phoenix.PubSub).
3. **Drop a comment on tab A.** Tab B sees it appear instantly without
   refresh (LiveView).
4. **Switch to a third tab pointed at the supervisor-tree LiveView.**
   Click "kill transcode worker." Watch the row turn red, then green
   as it restarts. Restart counter increments. (OTP supervision.)
5. **Open tab D against a *second running node* (e.g., `?node=2`).**
   The user from tab A is *already in* the listening room, no extra
   plumbing. (BEAM distribution + Phoenix.Presence.)
6. **Hit "drain node 1."** Watch the listener migrate to node 2
   without dropping playback. (Multi-node graceful drain.)

That's the demo. It's the README's animated GIF.

## 4. Tech Choices

### Backend — Elixir
- **Elixir 1.18+** with **Phoenix 1.8+** and **LiveView 1.x**
- **Ecto + Postgres** for the database
- **`live_vue`** ([github.com/Valian/live_vue](https://github.com/Valian/live_vue))
  for mounting Vue islands inside LiveViews
- **`libcluster`** for multi-node clustering on Fly (DNS poll
  topology against Fly's internal DNS)
- **`Phoenix.PubSub`** + **`Phoenix.Presence`** — built in
- **`ex_aws` + `ex_aws_s3`** for Cloudflare R2 (S3-compatible)
- **`req`** for ad-hoc HTTP

### Frontend — Vue islands
- **Vue 3.5** + **TypeScript (strict, `verbatimModuleSyntax`)**
- **Tailwind v4** + **shadcn-vue** (the components everyone screenshots)
- **howler** for playback, **wavesurfer.js** for waveform
- Vue runs only inside LiveView islands — no router, no store, no
  full SPA. Each island is a focused component.

### Storage
- **Cloudflare R2** from day one — S3-compatible, no egress fees.
- **Upload pattern: presigned PUT URLs**, browser uploads directly
  to R2. Phoenix never sees the bytes:
  1. LiveView's `allow_upload(..., external: &presign/2)` returns a
     short-lived signed URL.
  2. Browser PUTs the file directly to R2.
  3. LiveView upload protocol notifies us; we HEAD the object to
     verify size/type, then insert the `songs` row.
- This keeps Fly egress at zero (every byte is browser ↔ R2). The
  cost is one bonus OTP demo: a supervised
  `Mixwave.Workers.OrphanSweeper` that periodically deletes R2
  objects with no matching `songs.storage_key` (clients that aborted
  mid-upload). Three supervised workers total = three rows on the
  chaos board.
- Reads: signed GET URLs (15-min TTL) so playback links can't be
  enumerated forever.
- Bucket CORS is configured once, allowing PUT/GET/HEAD from the
  app's origin only.

### Limits
- **Max upload size: 25 MB.** Enforced in LiveView's
  `allow_upload(:audio, max_file_size: 25_000_000, ...)` plus the
  presigned URL's `Content-Length` constraint.
- **Accepted formats: mp3, m4a, ogg, flac.** Server-side `ffmpeg`
  transcodes everything to mp3 (128 kbps) on upload via the
  `Transcoder` worker. The original is deleted after successful
  transcode. `ffmpeg` is a runtime requirement — installed in the
  Fly Dockerfile.

### Auth — anonymous-only
- No email, no password, no signup form.
- First visit: server creates an `anonymous_users` row + sets a
  signed session cookie with the user_id.
- Every request bumps `last_active_at` (debounced once/minute).
- A supervised GenServer (`Mixwave.Workers.AnonSweeper`) runs every
  hour and deletes any user with `last_active_at < now() - 1 day`.
  `ON DELETE CASCADE` wipes their songs + comments; an after-commit
  callback removes their R2 objects.
- Optional v2: "claim a custom display name" — still no email.
- The sweeper is itself a flagship demo of OTP supervision: it's a
  supervised process; killing it on the supervisor LiveView shows it
  restart and resume its schedule.

#### Display name format

Server-generated, Javanese vibes: `<adjective>-<noun>-<NN>`. e.g.
`ayu-merak-42`, `wani-macan-17`, `tlaten-kupu-08`.

Starter wordlists (correct any I have wrong, or vibes I've missed):

```
adjectives:
  ayu, bagus, pinter, wani, alus, sabar, gagah, prigel, gemati,
  sumringah, temen, jujur, semanak, prasaja, mapan, mantep, legawa,
  tlaten, gemi, nastiti, sigap, lega, seneng, tegep, resik, trampil,
  anteng, wasis, padhang, guyub
                                                  (~30 entries)

nouns:
  macan, merak, garuda, gajah, kupu, menjangan, kidang, kucing, jaran,
  kembang, mawar, melati, pari, jati, bambu, gunung, kali, segara,
  mega, lintang, candra, surya, angin, gelombang, esuk, wengi,
  gamelan, wayang, batik, topeng
                                                  (~30 entries)
```

30 × 30 × 100 (the NN) = 90 000 unique names. Enough for any plausible
amount of traffic; collisions retried at insert time.

### Hosting
- **Fly.io**. Multi-node clustering is `fly scale count 2` plus a
  `libcluster` strategy of `dns_poll` against Fly's internal DNS.
- **Postgres: Fly Postgres** (in-region, <5 ms latency). Neon was
  considered; rejected because LiveView is round-trip-sensitive and
  the cold-start on a suspended Neon instance would show up as a
  visible delay on first page load.
- R2 lives outside Fly, reachable from anywhere.
- Domain: Fly's default subdomain for v1–v3; pick a custom domain
  later if the project warrants it.

## 5. Layout

```
mixwave/
├── BRAINSTORM.md (this file)
├── README.md
├── mix.exs
├── mix.lock
├── lib/
│   ├── mixwave/                       Domain
│   │   ├── application.ex             Supervisor tree root
│   │   ├── repo.ex
│   │   ├── accounts/                  anonymous_users + sweeper
│   │   │   ├── anonymous_user.ex
│   │   │   └── sweeper.ex             GenServer, supervised
│   │   ├── library/
│   │   │   ├── song.ex
│   │   │   └── comment.ex
│   │   ├── library.ex                 context
│   │   ├── storage.ex                 R2 wrapper (presign, put, delete)
│   │   ├── presence.ex                Phoenix.Presence module
│   │   └── workers/
│   │       ├── transcoder.ex          GenServer, supervised
│   │       └── orphan_sweeper.ex      GenServer, supervised — sweeps R2 objects with no matching song row
│   └── mixwave_web/
│       ├── endpoint.ex
│       ├── router.ex
│       ├── plugs/
│       │   └── ensure_anon_user.ex    creates user on first hit
│       ├── live/
│       │   ├── library_live.ex
│       │   ├── song_live.ex           with listen-together room
│       │   ├── upload_live.ex
│       │   ├── manage_live.ex
│       │   └── ops/
│       │       ├── supervisor_live.ex chaos button + tree view
│       │       └── cluster_live.ex    multi-node viz
│       ├── components/
│       │   ├── core_components.ex     shadcn-flavored helpers
│       │   └── layouts.ex
│       └── live_vue/
│           └── (live_vue server config)
├── assets/                            Vue islands
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── style.css                      Tailwind + theme
│   ├── vendor/
│   │   └── (lib utils for shadcn-vue)
│   └── vue/
│       ├── main.ts                    live_vue entry
│       └── components/
│           ├── Player.vue             persistent footer
│           ├── Waveform.vue           wavesurfer + click-to-seek
│           └── UploadDropzone.vue     dnd + presigned PUT
├── priv/
│   ├── repo/migrations/
│   └── static/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs                    R2 creds + cluster config from env
└── test/
```

## 6. Database Schema

```sql
CREATE TABLE anonymous_users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name    TEXT NOT NULL,
  last_active_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX anonymous_users_last_active_idx
  ON anonymous_users (last_active_at);

CREATE TABLE songs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES anonymous_users(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT,
  genre           TEXT,
  storage_key     TEXT NOT NULL,        -- R2 object key
  duration_s      REAL,
  waveform_peaks  REAL[],               -- pre-computed for fast render
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE comments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  song_id     UUID NOT NULL REFERENCES songs(id)            ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES anonymous_users(id)  ON DELETE CASCADE,
  body        TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Songs are global-public — every visitor sees everyone's uploads. That's
intentional: it makes the "play this song with strangers" demo work
without any room-invite flow.

## 7. Versions

### v1 — feature parity, single node

Same surface as `vue-ztm/music`, on the new stack.

1. Anonymous-auth plug + sweeper (sweeper visible in supervisor tree
   from day one)
2. Library LiveView (paginated list of all songs)
3. Upload LiveView (UploadDropzone.vue island handles the actual
   upload to R2 via presigned PUT)
4. Song LiveView (title, description, comments form + list)
5. Manage LiveView (your songs, edit/delete)
6. Persistent Player.vue island in the root layout

**Ship target**: a competent music app on a novel stack. First
sharing session.

### v2 — stack-showcase features, single node

Layers in the BEAM/OTP and Phoenix superpowers, except distribution.

7. Listen-together rooms — LiveView Presence on Song page; tab A and
   tab B see each other's avatars; press play in one syncs the other
   via `Phoenix.PubSub.broadcast/3`
8. Live comments stream — comments appear instantly across tabs (no
   polling) via the same PubSub
9. Waveform.vue island — wavesurfer.js renders pre-computed peaks
   from `songs.waveform_peaks`; click anywhere seeks
10. Background `Transcoder` GenServer — on upload, normalizes audio
    to mp3 128 kbps via ffmpeg + extracts waveform peaks; supervised
11. `OrphanSweeper` GenServer — periodically deletes R2 objects that
    have no corresponding `songs.storage_key` (aborted uploads);
    supervised, runs hourly
12. Supervisor LiveView — server-rendered tree of running children +
    restart counts. Three flagship workers visible (anon-sweeper,
    transcoder, orphan-sweeper). Chaos button kills any picked
    process; the page shows it restart in real-time

**Ship target**: hell of a demo. Second sharing session, internal
write-up.

### v3 — multi-node + public release

The "world" wave.

13. Fly.io deploy with `fly scale count 2`
14. `libcluster` `dns_poll` strategy → nodes auto-cluster
15. Cluster LiveView — list of connected nodes, processes per node,
    cross-node message latency probe
16. "Drain node N" button on the cluster page — sends `:drain` to the
    node's listeners; Phoenix.Presence rebalances them onto siblings
17. README + animated GIF + writeup; open-source on GitHub
18. Public link (Fly default subdomain — custom domain post-v3 if
    the project warrants it)

**Ship target**: the project lands on Twitter / HN / r/elixir /
r/vuejs as "Vue + Elixir, here's what's possible."

## 8. Build Order (high-level — detailed once we start)

1. `mix phx.new mixwave --database postgres --no-mailer --binary-id`
2. Add deps: `live_vue`, `ex_aws`, `ex_aws_s3`, `libcluster`, `req`
3. Configure assets/ for Vue + Tailwind v4 + shadcn-vue
4. Migrations: anonymous_users, songs, comments
5. Plug `EnsureAnonUser`, sweeper GenServer, supervised
6. R2 storage wrapper + presign helpers
7. v1 LiveViews + Vue islands (Player, UploadDropzone)
8. **Ship v1** (sharing session 1)
9. v2 features: Presence rooms, comments stream, waveform island,
   transcoder, supervisor LiveView with chaos button
10. **Ship v2** (sharing session 2)
11. v3: Fly multi-node, libcluster, cluster LiveView, drain button
12. README + writeup + open-source
13. **Ship v3** (public)

## 9. Decisions (locked)

- **Display name** — Javanese `<adj>-<noun>-<NN>`; starter wordlists
  in §4.
- **File size cap** — 25 MB.
- **Audio formats** — accept mp3, m4a, ogg, flac; server transcodes
  everything to mp3 128 kbps via the `Transcoder` worker. `ffmpeg`
  is a runtime dep in the Fly image.
- **Postgres host** — Fly Postgres (low LiveView latency).
- **Domain** — Fly default subdomain through v3; revisit later.
- **Upload pattern** — presigned PUT direct from browser to R2
  (Pattern A). Phoenix never touches the bytes.
- **Scope creep guard** — v3 is the stop. No v4 semantic-search,
  AI, recommendations, or anything else. The point is *stack
  showcase*, not "every feature."
