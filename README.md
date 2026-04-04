# uncompressed

Self-healing, high-quality media pipeline.

Streaming services compress 4K to 15-25 Mbps. A Blu-ray remux is 60-80 Mbps. I built a self-healing media pipeline that serves full-quality remuxes to my family with a Netflix-like request interface — and they have no idea it's not a commercial service.

12 containers across 3 Docker Compose stacks, running on Unraid. Zero-trust networking via Tailscale, VPN-isolated torrenting with leak-proof namespace isolation, and a YouTube geo-bypass tunnel that selectively routes only Google's IP ranges through Albania.

## The Problem

I kept running into the same frustrations with streaming:

- **Quality** — 4K on Netflix/Disney+ is 15-25 Mbps HEVC. A UHD Blu-ray remux is 60-80 Mbps. The difference is obvious on a decent display, especially in dark scenes where streaming artifacts crush shadow detail.
- **Availability** — Content disappears when licensing deals expire. Shows split across 5+ services. Regional libraries vary wildly.
- **Control** — No way to choose audio tracks, subtitle sources, or playback behavior. Algorithmic recommendations over catalog browsing.

I wanted something where my family could open an app, search for a movie, hit "request", and have it appear in their library — with Blu-ray quality, automated subtitles in multiple languages, and zero maintenance on their end.

## How It Works

The core is a **9-container arr stack** that automates the entire pipeline:

```
Family member opens Overseerr → requests a movie
  → Radarr picks it up, searches Prowlarr for indexers
    → qBittorrent downloads through VPN tunnel (gluetun namespace)
      → Radarr imports, renames, organizes
        → Bazarr fetches subtitles
          → Jellyfin serves it with hardware transcoding
```

For TV shows, Sonarr does the same thing — monitors series, grabs new episodes automatically, and Jellyfin updates in real time.

The whole pipeline is self-healing. If any container goes down, it gets restarted automatically. If the VPN drops, torrent traffic stops dead — it physically cannot route outside the tunnel.

## Architecture

```
                       ┌────────────┐
                       │ Cloudflare │
                       │    DNS     │
                       └─────┬──────┘
                             │
                       ┌─────┴──────┐
                       │ Tailscale  │
                       │   Mesh     │
                       └─────┬──────┘
                             │
                ┌────────────┴────────────┐
                │      Traefik v2.10      │
                │   Let's Encrypt (ACME)  │
                │  bound to Tailscale IP  │
                └──┬─────┬─────┬──────┬───┘
                   │     │     │      │
       ┌───────────┘     │     │      └───────────┐
       ▼                 ▼     ▼                  ▼
  ┌─────────┐    ┌─────────────────┐
  │Jellyfin │    │   *arr suite    │
  │         │    │ Sonarr  Radarr  │
  │         │    │Prowlarr Bazarr  │
  │         │    │   Overseerr     │
  └─────────┘    └────────┬────────┘
                          │
                 ┌────────┴────────┐
                 │   qBittorrent   │  network_mode: service:gluetun
                 │  bound to tun0  │  (namespace isolation)
                 └────────┬────────┘
                          │
  ┌───────────────────────┼───────────────────────────┐
  │    vpn_network        │                           │
  │              ┌────────┴────────┐                  │
  │              │     Gluetun     │                  │
  │              │ ProtonVPN (WG)  │                  │
  │              │   NL/CH (P2P)   │                  │
  │              └─────────────────┘                  │
  └───────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────┐
  │    YouTube geo-bypass (separate VPN tunnel)       │
  │                                                   │
  │    youtube-router ──► gluetun-exit ──► Albania    │
  │    (ipset/iptables)    (ProtonVPN WG)             │
  └───────────────────────────────────────────────────┘
```

Three traffic paths, each isolated:

1. **HTTPS ingress** — Cloudflare DNS → Tailscale mesh → Traefik (bound to Tailscale IP only, not `0.0.0.0`) → service by hostname
2. **P2P egress** — qBittorrent → gluetun network namespace (`tun0` binding) → ProtonVPN WireGuard → Netherlands/Switzerland
3. **YouTube geo-bypass** — `youtube-router` (ipset/iptables) → `gluetun-exit` → ProtonVPN WireGuard → Albania

## Security Model

No ports are open to the public internet. The entire setup is zero-trust:

- **Ingress** — Traefik binds exclusively to the Tailscale IP, not `0.0.0.0`. You must be on the Tailscale mesh to reach any service. HTTPS with auto-renewed Let's Encrypt certs via Cloudflare DNS challenge.
- **VPN leak prevention** — qBittorrent runs inside gluetun's network namespace (`network_mode: service:gluetun`), meaning it literally shares gluetun's network stack. An init script additionally forces `BIND_TO_INTERFACE: tun0`. If the VPN drops, there is no network path for traffic to take — it's not a firewall rule that could be misconfigured, it's a namespace boundary.
- **Network segmentation** — Three Docker networks isolate traffic: `traefik_proxy` for HTTPS, `arr_internal` for service-to-service (marked `internal: true`, no external access), `vpn_network` for tunnel traffic.
## Self-Healing

Every container has an endpoint-specific health check — not just "is the process alive" but "is the service actually responding correctly":

```
health check (curl /health, 30-60s intervals)
  → Docker marks container unhealthy
    → autoheal detects (60s scan)
      → container restart
        → depends_on: service_healthy blocks dependents until recovered
```

Gluetun checks its own `:9999/health` endpoint. qBittorrent verifies both its API response *and* pings `1.1.1.1` through the tunnel. Jellyfin checks `/health`. Each *arr service hits its own health endpoint. If gluetun goes down, all dependent services wait for it to recover before starting — no partial-stack states.

Three independent layers: health checks catch failures, autoheal restarts them, dependency ordering prevents cascading issues.

## Stacks

| Stack | Containers | Purpose |
|-------|-----------|---------|
| [`arr/`](arr/) | Gluetun, qBittorrent, Jellyfin, Sonarr, Radarr, Prowlarr, Overseerr, Bazarr, Autoheal | Media acquisition, streaming, self-healing |
| [`infra/`](infra/) | Traefik v2.10 | Reverse proxy, ACME certs (Cloudflare DNS challenge) |
| [`yt-exit/`](yt-exit/) | Gluetun-exit, youtube-router | YouTube geo-bypass via Albania |

Other supporting services (DNS, books, dashboard, etc.) live in a separate [homelab](https://github.com/Lackoftactics/homelab) repo.

## Technical Details

**VPN namespace isolation** — qBittorrent shares gluetun's network namespace, not just its network. The container has no network interface of its own. An init script (`arr/qbittorrent-init/10-config.sh`) sets `tun0` binding as defense in depth. Port forwarding is automatic — gluetun gets a forwarded port from ProtonVPN and pushes it to qBittorrent's API.

**Dual VPN tunnels** — Two independent gluetun instances with separate WireGuard keys. The P2P tunnel exits through NL/CH (optimized for torrents). The YouTube tunnel exits through Albania (geo-bypass). Neither affects the other.

**YouTube selective routing** — `youtube-router` downloads YouTube/Google IP ranges, builds ipset rules, and applies iptables routing inside gluetun-exit's network namespace. Only YouTube traffic goes through the tunnel — everything else routes normally. IP ranges refresh every 24 hours.

**DRY compose config** — YAML extension fields (`x-arr-env`, `x-arr-healthcheck`, `x-restart-policy`) eliminate duplication across 9 services. One change propagates everywhere.

**Hardware transcoding** — Jellyfin uses Intel Quick Sync (`/dev/dri`) for real-time transcoding when clients can't direct-play. Serves full Blu-ray remuxes to capable devices, transcodes on-the-fly for phones/tablets.

## Quick Start

```bash
cp .env.example .env              # configure credentials and domain
docker network create traefik_proxy

cd infra && docker compose up -d  # Traefik (reverse proxy) — start first
cd ../arr && docker compose up -d # media pipeline (9 containers)
cd ../yt-exit && docker compose up -d # YouTube geo-bypass (optional)
```

You need: Docker + Compose, a Tailscale account, a ProtonVPN account with WireGuard keys, and a domain with Cloudflare DNS. See [`.env.example`](.env.example) for all configuration options.

## Repository Structure

```
.
├── infra/           # Traefik reverse proxy
├── arr/             # Media pipeline (9 containers)
│   └── qbittorrent-init/  # VPN interface binding script
└── yt-exit/         # YouTube geo-bypass tunnel
```

Each stack is independently deployable. The only shared dependency is the `traefik_proxy` Docker network. Supporting services (DNS, books, dashboard) live in the [homelab](https://github.com/Lackoftactics/homelab) repo.

## License

[MIT](LICENSE)
