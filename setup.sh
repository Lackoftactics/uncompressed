#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
GUM_VERSION="0.16.0"

# ── Dependency check ───────────────────────────────────────────────
if ! command -v gum &>/dev/null; then
  echo "gum not found — downloading v${GUM_VERSION}..."
  mkdir -p "$REPO_DIR/.bin"

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="x86_64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  OS=$(uname -s)
  case "$OS" in
    Linux)  OS="Linux" ;;
    Darwin) OS="Darwin" ;;
    *) echo "Unsupported OS: $OS"; exit 1 ;;
  esac

  curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_${OS}_${ARCH}.tar.gz" \
    | tar xz -C "$REPO_DIR/.bin" --strip-components=1 "gum_${GUM_VERSION}_${OS}_${ARCH}/gum"
  export PATH="$REPO_DIR/.bin:$PATH"
  echo "gum installed to $REPO_DIR/.bin/gum"
fi

# ── Header ─────────────────────────────────────────────────────────
gum style \
  --border rounded --padding "0 2" --margin "1 0" \
  --bold \
  "uncompressed — setup wizard"

# ── Helpers ────────────────────────────────────────────────────────
prompt() {
  local label="$1" default="$2"
  gum input --placeholder "$default" --value "$default" --header "$label"
}

prompt_password() {
  local label="$1"
  gum input --password --header "$label"
}

prompt_required() {
  local label="$1" default="${2:-}"
  local value=""
  while [ -z "$value" ]; do
    if [ -n "$default" ]; then
      value=$(gum input --placeholder "$default" --value "$default" --header "$label (required)")
    else
      value=$(gum input --placeholder "required" --header "$label (required)")
    fi
  done
  echo "$value"
}

prompt_password_required() {
  local label="$1"
  local value=""
  while [ -z "$value" ]; do
    value=$(gum input --password --header "$label (required)")
  done
  echo "$value"
}

section() {
  gum style --bold --foreground 6 --margin "1 0 0 0" "$1"
}

# ── System ─────────────────────────────────────────────────────────
section "System"
TZ=$(prompt "Timezone" "Europe/Warsaw")
PUID=$(prompt "User ID (PUID)" "1000")
PGID=$(prompt "Group ID (PGID)" "1000")

# ── Domain & Networking ────────────────────────────────────────────
section "Domain & Networking"
DOMAIN_NAME=$(prompt_required "Domain name (e.g. media.xyz)")
TAILSCALE_IP=$(prompt_required "Tailscale IP (e.g. 100.64.1.5)")

# ── Cloudflare ─────────────────────────────────────────────────────
section "Cloudflare"
gum style --faint --margin "0 0 0 2" \
  "Create a scoped API token at dash.cloudflare.com → API Tokens" \
  "Required scopes: Zone → Zone → Read  +  Zone → DNS → Edit"
CF_DNS_API_TOKEN=$(prompt_password_required "Cloudflare API token")
CF_API_EMAIL=$(prompt_required "Cloudflare account email")
ACME_EMAIL=$(prompt "ACME email (for Let's Encrypt)" "$CF_API_EMAIL")

# ── ProtonVPN ──────────────────────────────────────────────────────
section "ProtonVPN WireGuard"
WG_PRIVATE_KEY=$(prompt_password_required "WireGuard private key")
WG_PUBLIC_KEY=$(prompt_required "WireGuard public key")
WIREGUARD_ADDRESSES=$(prompt "WireGuard address" "10.2.0.2/32")

section "ProtonVPN Credentials"
PROTONVPN_USERNAME=$(prompt_required "ProtonVPN username")
PROTONVPN_PASSWORD=$(prompt_password_required "ProtonVPN password")

# ── Volume Paths ───────────────────────────────────────────────────
section "Volume Paths"
gum style --faint --margin "0 0 0 2" \
  "Adjust for your system — defaults are Unraid paths."
DATA_DIR=$(prompt "Config/appdata base directory" "/mnt/user/appdata")
DOWNLOADS_DIR=$(prompt "Downloads directory" "/mnt/user/media/downloads/qbittorrent")
MEDIA_TV_DIR=$(prompt "TV shows directory" "/mnt/user/media/tv")
MEDIA_MOVIES_DIR=$(prompt "Movies directory" "/mnt/user/media/movies")

# ── qBittorrent ────────────────────────────────────────────────────
section "qBittorrent"
QB_USERNAME=$(prompt "WebUI username" "admin")
QB_PASSWORD=$(prompt_password_required "WebUI password")
BT_PORT=$(prompt "Torrenting port" "51413")

# ── Summary ────────────────────────────────────────────────────────
section "Summary"
gum style --border rounded --padding "0 2" \
  "Domain:       $DOMAIN_NAME" \
  "Tailscale IP: $TAILSCALE_IP" \
  "CF Email:     $CF_API_EMAIL" \
  "Data dir:     $DATA_DIR" \
  "Downloads:    $DOWNLOADS_DIR" \
  "TV dir:       $MEDIA_TV_DIR" \
  "Movies dir:   $MEDIA_MOVIES_DIR" \
  "QB user:      $QB_USERNAME" \
  "QB port:      $BT_PORT"

if ! gum confirm "Write .env and set up?"; then
  echo "Aborted."
  exit 0
fi

# ── Write .env ─────────────────────────────────────────────────────
ENV_FILE="$REPO_DIR/.env"
cat > "$ENV_FILE" <<EOF
# Generated by setup.sh

# Timezone
TZ=$TZ

# Container user/group IDs
PUID=$PUID
PGID=$PGID

# Domain for Traefik routing (*.$DOMAIN_NAME)
DOMAIN_NAME=$DOMAIN_NAME

# Tailscale IP (bind Traefik here, not 0.0.0.0)
TAILSCALE_IP=$TAILSCALE_IP

# Cloudflare (ACME DNS challenge for Let's Encrypt)
CF_DNS_API_TOKEN=$CF_DNS_API_TOKEN
CF_API_EMAIL=$CF_API_EMAIL
ACME_EMAIL=$ACME_EMAIL

# ProtonVPN WireGuard — main tunnel (NL/CH, P2P)
WG_PRIVATE_KEY=$WG_PRIVATE_KEY
WG_PUBLIC_KEY=$WG_PUBLIC_KEY
WIREGUARD_ADDRESSES=$WIREGUARD_ADDRESSES

# ProtonVPN credentials (OpenVPN fallback)
PROTONVPN_USERNAME=$PROTONVPN_USERNAME
PROTONVPN_PASSWORD=$PROTONVPN_PASSWORD

# Volume paths
DATA_DIR=$DATA_DIR
DOWNLOADS_DIR=$DOWNLOADS_DIR
MEDIA_TV_DIR=$MEDIA_TV_DIR
MEDIA_MOVIES_DIR=$MEDIA_MOVIES_DIR

# qBittorrent
QB_USERNAME=$QB_USERNAME
QB_PASSWORD=$QB_PASSWORD
BT_PORT=$BT_PORT
EOF

gum style --foreground 2 "✓ Wrote $ENV_FILE"

# ── Symlinks ───────────────────────────────────────────────────────
for subdir in arr infra; do
  target="$REPO_DIR/$subdir/.env"
  if [ -L "$target" ]; then
    gum style --foreground 3 "⟳ $subdir/.env already symlinked — skipping"
  elif [ -f "$target" ]; then
    gum style --foreground 3 "⚠ $subdir/.env exists as a regular file — skipping (remove it manually to use symlink)"
  else
    ln -s ../.env "$target"
    gum style --foreground 2 "✓ Symlinked $subdir/.env → ../.env"
  fi
done

# ── Docker network ─────────────────────────────────────────────────
if docker network inspect traefik_proxy &>/dev/null; then
  gum style --foreground 3 "⟳ traefik_proxy network already exists — skipping"
else
  gum spin --title "Creating traefik_proxy network..." -- \
    docker network create traefik_proxy
  gum style --foreground 2 "✓ Created traefik_proxy network"
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
gum style --border rounded --padding "0 2" --foreground 2 --bold \
  "Setup complete!" \
  "" \
  "Start the stack:" \
  "  cd infra && docker compose up -d" \
  "  cd ../arr && docker compose up -d"
