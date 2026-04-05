# uncompressed

My arr stack. Hardened Docker Compose config for Jellyfin + Sonarr/Radarr + qBittorrent with VPN namespace isolation and zero-trust ingress.

I run this on Unraid. It took a few months to get the networking right — most guides just slap a firewall rule on the VPN and call it a day. I wanted actual isolation, not "it probably works." Here's what I landed on.

My family uses [Seerr](https://github.com/fallenbagel/jellyseerr) to request movies/shows and [Infuse](https://firecore.com/infuse) on Apple TV to watch them. They don't know or care what's behind it.

<p align="center">
  <img src="docs/screenshots/screen-jellyfin.png" width="32%" alt="Jellyfin media library" />
  <img src="docs/screenshots/screen-real-radarr.png" width="32%" alt="Radarr movie management" />
  <img src="docs/screenshots/screen-sonarr.png" width="32%" alt="Sonarr TV show management" />
</p>

## Quick Start

```bash
cp .env.example .env              # configure credentials and domain
docker network create traefik_proxy

cd infra && docker compose up -d  # traefik first
cd ../arr && docker compose up -d # everything else
```

You need Docker + Compose, a [Tailscale](https://tailscale.com) account, a [ProtonVPN](https://protonvpn.com) account with WireGuard keys, and a domain on [Cloudflare DNS](https://www.cloudflare.com). See [`.env.example`](.env.example) for all the variables.

## Networking & Security

This is the part that's actually interesting. The services themselves are standard — the value is in how they're wired together.

**VPN namespace isolation** — qBittorrent doesn't just "use" the VPN. It runs inside gluetun's network namespace (`network_mode: service:gluetun`), meaning it shares gluetun's entire network stack. The container has no network interface of its own. An init script ([`10-config.sh`](arr/qbittorrent-init/10-config.sh)) additionally forces `BIND_TO_INTERFACE: tun0` as defense in depth. If the VPN drops, there is no path for traffic to take — it's a kernel boundary, not a firewall rule that could be misconfigured.

**No published ports** — None of the services expose ports to the host. Traefik routes to containers through the Docker network directly. There's no way to hit Sonarr/Radarr/Jellyfin by going to `host:port` and bypassing TLS + security headers.

**Tailscale-only ingress** — Traefik binds to `${TAILSCALE_IP}:443`, not `0.0.0.0:443`. You must be on the Tailscale mesh to reach any service. No ports face the public internet. HTTPS certs are auto-renewed via Cloudflare DNS challenge.

**Three isolated networks** — `traefik_proxy` for HTTPS ingress, `arr_internal` (marked `internal: true`) for service-to-service, `vpn_network` for tunnel traffic. Port forwarding from ProtonVPN is automatic — gluetun gets the forwarded port and pushes it to qBittorrent's API.

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
  │         │    │     Seerr       │
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
```

## What's in the stack

**`arr/`** — Gluetun, qBittorrent, Jellyfin, Sonarr, Radarr, Prowlarr, Seerr, Bazarr, Autoheal. Every container has an endpoint-specific health check. Autoheal restarts anything that fails. `depends_on: service_healthy` prevents cascading startup issues.

**`infra/`** — Traefik v2.10.7 reverse proxy with auto HTTPS via Cloudflare DNS challenge.

Other stuff (DNS, books, dashboard) lives in a separate [homelab](https://github.com/Lackoftactics/homelab) repo.

## License

[MIT](LICENSE)
