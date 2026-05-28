# Deployments

Self-hosting options for mixchamb. Pick one — the rest of this
directory has the per-method scripts, configs, and workflows.

| Method | When it fits | Subdirectory |
|---|---|---|
| **Linux host** (systemd + plain binaries) | One VPS, want full control, comfortable with shell + systemd. Lowest overhead at small scale. | `linux-host/` |
| **Docker Compose** | Want container isolation, run on any Docker-capable host, OK with running Docker as ops layer. | `docker-compose/` |
| **Podman + Quadlet** | Want containers but daemonless + rootless-capable, with systemd-native lifecycle management. Closest to "linux-host with containers." | `podman/` |
| **Dokploy** | Want a self-hosted PaaS UI (git push → deploy, managed Postgres, managed proxy). Already running Dokploy or willing to. | `dokploy/` |

All four methods produce the same runtime behaviour: Phoenix +
Postgres + a public URL. They differ in **what manages the
process tree** and **how the deploy step works.**

## Cross-cutting decisions (apply to every method)

- **TLS / edge.** Cloudflare Tunnel is the recommended ingress
  for all four methods — outbound dial, zero inbound ports, no
  origin cert to manage. Other options (Caddy, nginx, Traefik)
  are documented in the **Load balancing / edge ingress**
  section below.
- **Database.** Postgres 16. On `linux-host/` it runs as a
  package; on `docker-compose/`, `podman/`, and `dokploy/` it's
  a sibling container. Backups (daily `pg_dump` → off-box
  object storage) apply equally.
- **Monitoring.** Telegram bot as the single alerting
  destination across systemd `OnFailure=`, UptimeRobot,
  healthchecks.io, and Sentry. Per-method monitoring details are
  in each subdir's README; the conceptual layering is identical.
  Point HTTP probes (container `HEALTHCHECK`, fly `[[checks]]`,
  UptimeRobot) at **`GET /up`** — a lightweight public endpoint that
  pings the DB and returns `200 {"status":"ok"}` / `503` (no
  session/LiveView). The richer human view is `/admin/health`.
- **Secrets.** Never commit. Use the `.env.example` /
  `env.example` files as templates — copy, fill, never `git add`.

## Picking between them

- **Most ops control, fewest moving parts** → `linux-host/`. One
  systemd, one Postgres, one tunnel, done. Best if you treat the
  VPS like cattle anyway.
- **Already use Docker for everything else** → `docker-compose/`.
  Familiar tooling, easier to mirror locally, but you're adding
  Docker as a layer that systemd would otherwise handle for free.
- **Want containers + systemd, no daemon** → `podman/`. The
  Red Hat-family default, gaining ground on Debian/Ubuntu too.
- **Want a "git push and forget" UX without paying a PaaS** →
  `dokploy/`. The UI layer is the value; the cost is running and
  patching Dokploy itself.

If you're undecided, start with `linux-host/` — it has the most
detailed runbook and the simplest mental model. Migrating to one
of the other methods later is straightforward because Phoenix
releases + Postgres dumps + Cloudflare Tunnel are all portable.

## Load balancing / edge ingress

Three real choices for getting public traffic to your
Phoenix node(s). Pick based on whether you want to expose the
origin IP, manage TLS certs yourself, and how many origins
you're planning to run.

### Option A — Cloudflare Tunnel (recommended, what every subdir wires up)

- **Shape:** `cloudflared` dials out from each origin to
  Cloudflare's edge. Cloudflare terminates TLS, handles DDoS,
  routes requests through the tunnel to your app on
  `localhost:4000` (or `mixchamb:4000` for the container
  methods).
- **LB story:** native. Run N `cloudflared` instances against
  the same named tunnel — each one connects to Cloudflare's
  edge with multiple HA connections, and the edge load-balances
  requests across all healthy origins. Cloudflare's [tunnel
  replicas docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/local-management/tunnel-availability/)
  explain the failover semantics. No origin-side LB needed.
- **Pro:** zero inbound ports on origin (no `:443` listening,
  no `ufw allow https`), zero certs to manage, free DDoS
  protection at edge, origin IP never published.
- **Con:** Cloudflare-dependent. If Cloudflare has an outage
  (rare but happens), your site is down even if origins are
  healthy.
- **WebSocket scaling concern:** each `cloudflared` instance
  multiplexes WebSockets over HTTP/2 streams with a default
  budget around 400 concurrent (4 HA connections × 100 streams).
  Either bump `--ha-connections` to 8–16 in the cloudflared
  config, or run 2+ replicas, before you cross that ceiling.
- **Configured in every subdir.** Default. Nothing else to do.

### Option B — Origin-terminated TLS via Caddy / nginx / Traefik

Use this if you don't want to depend on Cloudflare Tunnel, or
you want to terminate TLS at the origin.

| Proxy | Best for | Notes |
|---|---|---|
| **Caddy** | One-config-file simplicity, automatic Let's Encrypt | `Caddyfile` is one line per site. Auto cert renewal. Smallest mental load for someone new to reverse proxies. |
| **nginx** | Maximum control, most battle-tested | More verbose config. The internet's reference reverse proxy. Cert renewal via `certbot` or a sidecar. |
| **Traefik** | Container-first, label-based config | Reads `docker-compose.yml` labels and configures itself. Natural fit for `docker-compose/` and `dokploy/` (Dokploy already ships Traefik). |

LB story for any of these:
- **Single origin:** the proxy listens on `:443`, terminates
  TLS, forwards to `localhost:4000`. No LB happening yet —
  the proxy is just an edge.
- **Multiple origins:** the proxy's `upstream` block lists each
  origin. Caddy/nginx/Traefik all support round-robin, least-
  connections, and sticky sessions (needed for Phoenix LiveView
  WebSockets — see below).
- **You expose `:443` publicly.** Origin IP is now discoverable
  via Censys/Shodan within hours. Either accept that and rely
  on Cloudflare proxied DNS for DDoS protection, or firewall
  `:443` to Cloudflare's published IP ranges (which you must
  keep current).
- **Certs are your job.** Caddy and Traefik automate Let's
  Encrypt; nginx needs `certbot` or similar cron.

LiveView WebSocket caveat: Phoenix LiveView holds a
long-lived WebSocket per client. If you run N Phoenix nodes
behind an LB, **WebSockets need sticky sessions** (LB pins a
given client to the same Phoenix node for the WS lifetime) —
or you need Phoenix.PubSub clustering (libcluster + PG2/Redis
adapter) so cross-node broadcasts work. Sticky sessions are
the simpler default; clustering is the right answer once you
exceed a single node's CPU.

### Option C — Beam clustering for multi-node Phoenix

When one origin isn't enough — usually around 5–10k concurrent
LiveView users on a single 4-core box — you scale by adding
Phoenix nodes and clustering them:

- `libcluster` for node discovery (DNS, static list, K8s, or
  gossip).
- `Phoenix.PubSub` with the `PG2` adapter (in-cluster fanout)
  or Redis adapter (out-of-cluster, slower but no cluster size
  limit).
- LB in front: still Cloudflare Tunnel (with N `cloudflared`
  replicas, one per origin) or your own proxy.

This is a separate doc — adding it here would be premature for
the current scale target. Single-node + Cloudflare Tunnel + 1
cloudflared instance covers the first few hundred concurrent
users; multi-replica cloudflared covers the first few thousand;
true cluster mode comes after that.

### Recommendation matrix

| Your situation | Pick |
|---|---|
| Single origin, no LB needed, want zero ops on TLS + DDoS | **Cloudflare Tunnel** (Option A) — what every subdir defaults to |
| Single origin, refuse Cloudflare dependency, want simplest TLS | **Caddy** (Option B) — one config file, auto-renew |
| Already using Docker labels for everything | **Traefik** (Option B) — auto-configures from compose |
| Multi-origin, single region | **Cloudflare Tunnel** with N cloudflared replicas (Option A) + libcluster between Phoenix nodes (Option C) |
| Multi-origin, multi-region, hundreds of thousands of users | Out of scope for this doc — managed K8s or Fly.io territory |
