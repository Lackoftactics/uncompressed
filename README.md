# uncompressed

My arr stack. Hardened Docker Compose config for Jellyfin + Sonarr/Radarr + qBittorrent with VPN namespace isolation and zero-trust ingress.

I run this on Unraid. It took a few months to get the networking right — most guides just slap a firewall rule on the VPN and call it a day. I wanted actual isolation, not "it probably works." Here's what I landed on.

My family uses [Seerr](https://github.com/fallenbagel/jellyseerr) to request movies/shows and [Infuse](https://firecore.com/infuse) on Apple TV to watch them. 

<p align="center">
  <img src="docs/screenshots/screen-jellyfin.png" width="32%" alt="Jellyfin media library" />
  <img src="docs/screenshots/screen-real-radarr.png" width="32%" alt="Radarr movie management" />
  <img src="docs/screenshots/screen-sonarr.png" width="32%" alt="Sonarr TV show management" />
</p>

## Prerequisites

- **Docker + Compose**
- **[Tailscale](https://tailscale.com) account.** Open these ports in your Tailscale ACL for the host running this stack: `tcp:80`, `tcp:443` (Traefik, bound to your Tailscale IP) and `tcp:8096` (Jellyfin direct, for LAN clients like Infuse / Apple TV). Nothing else is published to the host.
- **[ProtonVPN](https://protonvpn.com) account** with WireGuard keys (P2P-enabled servers in NL/CH).
- **Domain on [Cloudflare DNS](https://www.cloudflare.com)** with a scoped API token (not the Global API Key). Create the token at [dash.cloudflare.com → My Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens) with these permissions on the target zone:
  - `Zone → Zone → Read`
  - `Zone → DNS → Edit`

  This is the minimum required for the ACME DNS-01 challenge. See [`.env.example`](.env.example) for the full variable list.

## Quick Start

**Fast track** — download and run the guided setup wizard (no git required):

```bash
curl -L https://github.com/Lackoftactics/uncompressed/archive/main.tar.gz | tar xz
cd uncompressed-main && ./setup.sh
```

Or with git (gives you `git pull` for future updates):

```bash
git clone https://github.com/Lackoftactics/uncompressed.git
cd uncompressed && ./setup.sh
```

**Manual setup** — if you prefer to do it yourself:

```bash
cp .env.example .env              # fill in secrets, domain, Tailscale IP, WG keys, CF token
ln -s ../.env arr/.env            # each compose stack reads its own .env
ln -s ../.env infra/.env
docker network create traefik_proxy
```

Then start the stack (from the repo root — no `cd` needed):

```bash
docker compose -f infra/docker-compose.yml up -d  # traefik first
docker compose -f arr/docker-compose.yml up -d     # media pipeline (9 containers)
```

Each compose file declares `env_file: ./.env`, resolved relative to its own directory — so `arr/docker-compose.yml` needs `arr/.env`. Symlinking keeps one source of truth at the repo root.

### Configuring each services
To configure each service, be sure to use docker internal DNS to let services reach each other on the network `arr_internal` :
- http://prowlarr:9696
- http://radarr:7878
- http://gluetun:8080 (qbittorrent)
- http://jellyfin:8096
- http://sonarr:8989
- http://bazarr:6767
- http://seerr:5055

### Subdomains
This is the list of subdomains for which you must create `A` records pointing to the Tailscale IP of the machine that hosts Traefik:
- traefik
- bazarr
- jellyfin
- prowlarr
- qbit
- radarr
- seerr
- sonarr

Note: create full FQDNs (e.g., traefik.example.com) in your DNS zone (alternatively, add them to your hosts file), each pointing to your host's Tailscale IP.

### qBittorrent
The web UI is at `qbit.example.com` and a temporary password for the `admin` user will be printed to the container log on startup.

You must then change username/password in the web UI section of settings. If you do not change the password a new one will be generated every time the container starts.

## Networking & Security

This is the part that's actually interesting. The services themselves are standard — the value is in how they're wired together.

**VPN namespace isolation** — qBittorrent doesn't just "use" the VPN. It runs inside gluetun's network namespace (`network_mode: service:gluetun`), meaning it shares gluetun's entire network stack. The container has no network interface of its own. An init script ([`10-config.sh`](arr/qbittorrent-init/10-config.sh)) additionally forces `BIND_TO_INTERFACE: tun0` as defense in depth. If the VPN drops, there is no path for traffic to take — it's a kernel boundary, not a firewall rule that could be misconfigured.

**No published ports, with one exception** — only Jellyfin publishes `:8096` to the host so LAN clients (Infuse, Apple TV) can hit it directly. Everything else is reachable only through Traefik over the Docker network — there's no way to hit Sonarr/Radarr/Prowlarr/etc. by going to `host:port` and bypassing TLS + security headers.

**Tailscale-only ingress** — Traefik binds to `${TAILSCALE_IP}:443`, not `0.0.0.0:443`. You must be on the Tailscale mesh to reach any service. No ports face the public internet. HTTPS certs are auto-renewed via Cloudflare DNS challenge.

**Three isolated networks** — `traefik_proxy` for HTTPS ingress, `arr_internal` (marked `internal: true`) for service-to-service, `vpn_network` for tunnel traffic. Port forwarding from ProtonVPN is automatic — gluetun gets the forwarded port and pushes it to qBittorrent's API.

## Architecture

<p align="center">
  <img src="docs/architecture-diagram.png" alt="Media architecture — dockerized solution" width="720" />
</p>

Cloudflare is used only as the ACME DNS-01 challenge target for cert renewal — control plane, not in the user-traffic path.

## What's in the stack

**`arr/`** — Gluetun, qBittorrent, Jellyfin, Sonarr, Radarr, Prowlarr, Seerr, Bazarr, Autoheal. Every container has an endpoint-specific health check. Autoheal restarts anything that fails. `depends_on: service_healthy` prevents cascading startup issues.

**`infra/`** — Traefik v2.10.7 reverse proxy with auto HTTPS via Cloudflare DNS challenge.

## License

[MIT](LICENSE)
