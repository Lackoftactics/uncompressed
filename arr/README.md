# arr — Media Pipeline

VPN-isolated media acquisition and streaming stack. 9 containers with self-healing.

## Services

- **gluetun** — ProtonVPN WireGuard tunnel (NL/CH, P2P-optimized). All torrent traffic exits here.
- **qbittorrent** — Torrent client sharing gluetun's network namespace. Bound to `tun0` interface via init script — traffic cannot leak if VPN drops.
- **jellyfin** — Media server with hardware transcoding (`/dev/dri`). Serves lossless remuxes.
- **sonarr** — TV show management and automation.
- **radarr** — Movie management and automation.
- **prowlarr** — Indexer manager for Sonarr/Radarr. Runs inside gluetun's network namespace — all indexer traffic exits through the VPN.
- **seerr** — Media request interface for end users.
- **bazarr** — Automated subtitle downloads.
- **auto-heal** — Monitors all containers, restarts any that fail health checks.

## Networks

- `traefik_proxy` — External, for HTTPS access via Traefik.
- `arr_internal` — Internal bridge for service-to-service communication.
- `vpn_network` — Bridge for gluetun and torrent traffic.

## Notes

- qBittorrent and Prowlarr use `network_mode: service:gluetun` for VPN namespace isolation. Neither container has a network interface of its own — if the VPN drops, there is no path for traffic to take.
- qBittorrent additionally sets `BIND_TO_INTERFACE: tun0` as defense in depth.
- All *arr services depend on gluetun with `condition: service_healthy` — they won't start until the VPN is up.
- YAML extension fields (`x-arr-env`, `x-arr-healthcheck`, `x-restart-policy`) reduce duplication across services.
- Port forwarding is handled automatically via ProtonVPN's native port forwarding, with gluetun pushing the forwarded port to qBittorrent's API.
- Because Prowlarr runs in gluetun's network namespace, Sonarr and Radarr must reach it at `http://gluetun:9696` (not `http://prowlarr:9696`). Update the Prowlarr URL in Sonarr/Radarr settings accordingly.
