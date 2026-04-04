# dns — AdGuard Home

Network-wide DNS with ad-blocking, available on both LAN and Tailscale.

## Services

- **adguardhome** — DNS server with ad/tracker blocking. Supports DNS (53), DNS-over-TLS (853), and DNS-over-QUIC (784).

## Notes

- Bound to both `${HOST_IP}:53` and `${TAILSCALE_IP}:53` — serves DNS on local network and across the Tailnet.
- Configure Tailscale to use this as a nameserver: all Tailnet devices get ad-blocking automatically.
- Fallback upstream: Cloudflare (1.1.1.1).
- Health check: `wget http://localhost:3000`.
- Setup UI at `adguard-setup.${DOMAIN_NAME}`, admin at `adguard.${DOMAIN_NAME}`.
