# infra — Traefik Reverse Proxy

HTTPS ingress layer for all services. Automatic TLS certificates via Let's Encrypt with Cloudflare DNS challenge.

## Services

- **traefik** v2.10 — Reverse proxy bound to Tailscale IP only (not `0.0.0.0`). Routes `*.domain` hostnames to backend services via Docker labels.

## Notes

- Ports 80/443 bind to `${TAILSCALE_IP}`, enforcing zero-trust ingress. No ports are exposed to the public internet.
- ACME certificates use Cloudflare DNS challenge — no need for port 80 to be publicly reachable.
- HTTP → HTTPS redirection is configured at the entrypoint level.
- All other stacks connect to the `traefik_proxy` external network and declare routing via container labels.
- DNS resolvers: Tailscale MagicDNS (100.100.100.100) with Cloudflare (1.1.1.1) fallback.
