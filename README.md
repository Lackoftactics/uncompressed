# homelab

Production Docker infrastructure: 17 containers, 8 stacks, self-healing, VPN-isolated media pipeline, geo-routed tunnels. Runs on Unraid with zero-trust networking via Tailscale.

Built because streaming services compress 4K content to 15-25 Mbps. A Blu-ray remux is 60-80 Mbps. I wanted full control over quality, availability, and the request pipeline.

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
  ┌─────────┐    ┌─────────────────┐       ┌──────────┐
  │Jellyfin │    │   *arr suite    │       │ AdGuard  │
  │ Kavita  │    │ Sonarr  Radarr  │       │  Home    │
  │ Dashy   │    │Prowlarr Bazarr  │       │DNS/DoT/Q │
  │Open-WebUI│   │   Overseerr     │       └──────────┘
  └─────────┘    └────────┬────────┘
                          │
                 ┌────────┴────────┐
                 │   qBittorrent   │  network_mode: service:gluetun
                 │  bound to tun0  │  (VPN namespace isolation)
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

Three distinct traffic paths:

1. **HTTPS ingress** — Cloudflare DNS → Tailscale mesh → Traefik (bound to Tailscale IP only, not `0.0.0.0`) → service by hostname
2. **P2P egress** — qBittorrent → gluetun network namespace (`tun0` binding) → ProtonVPN WireGuard → Netherlands/Switzerland
3. **YouTube geo-bypass** — `youtube-router` (ipset/iptables) → `gluetun-exit` → ProtonVPN WireGuard → Albania

## Stacks

| Stack | Services | Network | Purpose |
|-------|----------|---------|---------|
| `infra/` | Traefik v2.10 | `traefik_proxy` | Reverse proxy, ACME certs via Cloudflare DNS challenge |
| `arr/` | Gluetun, qBittorrent, Jellyfin, Sonarr, Radarr, Prowlarr, Overseerr, Bazarr, Autoheal | `traefik_proxy` `arr_internal` `vpn_network` | Media acquisition and streaming |
| `dns/` | AdGuard Home | `traefik_proxy` | DNS/DoT/DoQ with ad-blocking on LAN + Tailscale |
| `yt-exit/` | Gluetun-exit, youtube-router | bridge | YouTube traffic through Albania exit node |
| `books/` | Kavita | `traefik_proxy` | Books, comics, manga server |
| `essential/` | Dashy | `traefik_proxy` | Service dashboard |
| `productivity/` | Open-WebUI | `traefik_proxy` | AI chat interface |
| `pt/` | Transmission | `traefik_proxy` | Direct BitTorrent client (no VPN) |

## Design Decisions

- **VPN namespace isolation** — qBittorrent runs inside gluetun's network namespace (`network_mode: service:gluetun`). An init script (`arr/qbittorrent-init/10-config.sh`) additionally forces the interface to `tun0`. Even if the tunnel drops, traffic cannot leak to the host. Defense in depth.

- **Dual VPN with purpose-specific exits** — Media stack exits through NL/CH (P2P-optimized ProtonVPN servers). YouTube tunnel exits through Albania for geo-bypass. Separate gluetun instances, separate WireGuard keys. No single-tunnel bottleneck.

- **Self-healing layering** — Three independent mechanisms: endpoint-specific health checks on every container, dependency ordering via `condition: service_healthy`, and an autoheal container that monitors and restarts unhealthy services. See [Self-Healing](#self-healing).

- **Zero-trust ingress** — Traefik binds to Tailscale IP only. No ports open to the public internet. All inbound traffic traverses Cloudflare DNS then Tailscale mesh.

- **YouTube routing via dynamic IP sets** — `youtube-router` downloads YouTube IP ranges, creates ipset/iptables rules inside the gluetun-exit network namespace, refreshes daily. Selective geo-bypass without full-tunnel VPN for all traffic.

- **DRY compose config** — YAML extension fields (`x-arr-env`, `x-arr-healthcheck`, `x-restart-policy`) eliminate duplication across 9 services in the arr stack.

## Self-Healing

```
health check (curl /health, 30-60s intervals)
  → Docker marks container unhealthy
    → autoheal detects (60s scan)
      → container restart
        → depends_on: service_healthy blocks dependents until recovered
```

Every container has an endpoint-specific health check. Gluetun checks `:9999/health`, qBittorrent verifies its API response and pings `1.1.1.1`, Jellyfin checks `/health`, each *arr service checks its own `/health` endpoint. No service relies on Docker's default PID-based liveness.

## Why Not Netflix?

Jellyfin serves lossless Blu-ray remuxes with hardware transcoding (Intel Quick Sync via `/dev/dri`). Streaming services compress 4K to 15-25 Mbps — a remux is 60-80 Mbps. Bazarr automates subtitle acquisition across languages. No algorithmic content curation. No content disappearing when licensing deals expire. Overseerr gives family members a request interface that matches commercial streaming UX. The entire pipeline is self-healing and zero-maintenance for end users.

## Repository Structure

```
.
├── infra/           # Traefik reverse proxy
├── arr/             # Media pipeline (9 containers)
├── dns/             # AdGuard Home DNS
├── yt-exit/         # YouTube geo-bypass tunnel
├── books/           # Kavita reading server
├── essential/       # Dashy dashboard
├── productivity/    # Open-WebUI
└── pt/              # Transmission (no VPN)
```

Each stack is independently deployable with `docker compose up -d`.

## Tech Stack

**Networking** — Traefik v2.10, Tailscale, Cloudflare DNS, Gluetun (WireGuard / ProtonVPN), AdGuard Home (DNS/DoT/DoQ)
**Media** — Jellyfin (hw transcoding), Sonarr, Radarr, Prowlarr, Bazarr, Overseerr, qBittorrent
**Operations** — Autoheal, endpoint health checks on all 17 containers, Docker Compose dependency ordering
**Other** — Kavita, Dashy, Open-WebUI, Transmission

## Quick Start

```bash
cp .env.example .env              # configure credentials and domain
docker network create traefik_proxy

cd infra && docker compose up -d  # Traefik first
cd ../arr && docker compose up -d # media pipeline
cd ../dns && docker compose up -d # DNS
# remaining stacks as needed
```

## License

[MIT](LICENSE)
