# pt — Transmission

Direct BitTorrent client without VPN routing. Alternative to qBittorrent in the arr stack.

## Services

- **transmission** — Lightweight torrent client with web UI. Peer port 51414 (TCP/UDP).

## Notes

- No VPN dependency — traffic goes through the host network directly.
- Downloads to `/mnt/user/media/downloads/transmission`, shared with Jellyfin for direct access.
- Traefik routes to `pt.${DOMAIN_NAME}` with WebSocket middleware for the web interface.
- Health check: `curl http://localhost:9091/transmission/web/`.
