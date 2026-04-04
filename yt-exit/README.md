# yt-exit — YouTube Geo-Bypass Tunnel

Routes YouTube traffic through an Albanian ProtonVPN exit node to bypass geo-restrictions. Separate VPN tunnel from the main media stack.

## Services

- **gluetun-exit** — ProtonVPN WireGuard tunnel exiting through Albania. Firewall whitelists Tailscale (100.64.0.0/10) and local (192.168.0.0/16) subnets.
- **youtube-router** — Alpine container that downloads YouTube IP ranges from a maintained gist, creates ipset/iptables rules, and refreshes daily.

## Notes

- This is a separate gluetun instance with its own WireGuard keys — completely independent from the P2P tunnel in `arr/`.
- `youtube-router` shares gluetun-exit's network namespace (`network_mode: service:gluetun-exit`).
- Only YouTube traffic is routed through the tunnel. All other traffic uses the default route.
- IP ranges are refreshed every 24 hours to track YouTube's infrastructure changes.
