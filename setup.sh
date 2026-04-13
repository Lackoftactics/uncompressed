#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
GUM_VERSION="0.16.0"
TOTAL_STEPS=6
CURRENT_STEP=0

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

# ── Theme ──────────────────────────────────────────────────────────
ACCENT="212"    # pink/magenta
MUTED="240"     # gray
OK="2"          # green
WARN="3"        # yellow

# ── Header ─────────────────────────────────────────────────────────
echo ""
gum style \
  --border double --padding "1 3" --margin "0 2" \
  --border-foreground "$ACCENT" \
  --bold --foreground "$ACCENT" \
  "uncompressed" \
  "" \
  "$(gum style --faint 'Jellyfin + *arr + VPN isolation')" \
  "$(gum style --faint 'setup wizard')"

# ── Helpers ────────────────────────────────────────────────────────
section() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo ""
  gum style --bold --foreground "$ACCENT" \
    "[$CURRENT_STEP/$TOTAL_STEPS] $1"
  gum style --foreground "$MUTED" \
    "$(printf '%.0s─' {1..45})"
}

hint() {
  gum style --foreground "$MUTED" --italic --margin "0 0 0 2" "$@"
}

prompt() {
  local label="$1" default="$2"
  gum input \
    --placeholder "$default" \
    --value "$default" \
    --header "  $label" \
    --header.foreground "$MUTED" \
    --prompt "› " \
    --prompt.foreground "$ACCENT" \
    --cursor.foreground "$ACCENT"
}

prompt_required() {
  local label="$1" default="${2:-}"
  local value=""
  while [ -z "$value" ]; do
    if [ -n "$default" ]; then
      value=$(gum input \
        --placeholder "$default" \
        --value "$default" \
        --header "  $label" \
        --header.foreground "$MUTED" \
        --prompt "› " \
        --prompt.foreground "$ACCENT" \
        --cursor.foreground "$ACCENT")
    else
      value=$(gum input \
        --placeholder "required" \
        --header "  $label" \
        --header.foreground "$MUTED" \
        --prompt "› " \
        --prompt.foreground "$ACCENT" \
        --cursor.foreground "$ACCENT")
      [ -z "$value" ] && gum style --foreground 1 "  This field is required."
    fi
  done
  echo "$value"
}

prompt_password_required() {
  local label="$1"
  local value=""
  while [ -z "$value" ]; do
    value=$(gum input --password \
      --header "  $label" \
      --header.foreground "$MUTED" \
      --prompt "› " \
      --prompt.foreground "$ACCENT" \
      --cursor.foreground "$ACCENT")
    [ -z "$value" ] && gum style --foreground 1 "  This field is required."
  done
  echo "$value"
}

ok()   { gum style --foreground "$OK"   "  ✓ $1"; }
warn() { gum style --foreground "$WARN" "  ⚠ $1"; }
skip() { gum style --foreground "$MUTED" "  ⟳ $1"; }

# ── 1. System ─────────────────────────────────────────────────────
section "System"
TZ=$(prompt "Timezone" "Europe/Warsaw")
PUID=$(prompt "User ID (PUID)" "1000")
PGID=$(prompt "Group ID (PGID)" "1000")

# ── 2. Domain & Networking ────────────────────────────────────────
section "Domain & Networking"
hint "A \$2/yr .xyz domain works — DNS records point to your private Tailscale IP."
DOMAIN_NAME=$(prompt_required "Domain name (e.g. media.xyz)")
TAILSCALE_IP=$(prompt_required "Tailscale IP (e.g. 100.64.1.5)")

# ── 3. Cloudflare ─────────────────────────────────────────────────
section "Cloudflare"
hint "Create a scoped API token at dash.cloudflare.com → API Tokens" \
     "Required scopes: Zone → Zone → Read  +  Zone → DNS → Edit"
CF_DNS_API_TOKEN=$(prompt_password_required "Cloudflare API token")
CF_API_EMAIL=$(prompt_required "Cloudflare account email")
ACME_EMAIL=$(prompt "ACME email (for Let's Encrypt)" "$CF_API_EMAIL")

# ── 4. ProtonVPN ──────────────────────────────────────────────────
section "ProtonVPN"
hint "WireGuard keys from account.protonvpn.com → Downloads → WireGuard configuration"
WG_PRIVATE_KEY=$(prompt_password_required "WireGuard private key")
WG_PUBLIC_KEY=$(prompt_required "WireGuard public key")
WIREGUARD_ADDRESSES=$(prompt "WireGuard address" "10.2.0.2/32")
echo ""
hint "OpenVPN credentials (used as fallback)"
PROTONVPN_USERNAME=$(prompt_required "ProtonVPN username")
PROTONVPN_PASSWORD=$(prompt_password_required "ProtonVPN password")

# ── 5. Volume Paths ───────────────────────────────────────────────
section "Volume Paths"
hint "Adjust for your system — defaults are Unraid paths."
DATA_DIR=$(prompt "Config/appdata base directory" "/mnt/user/appdata")
DOWNLOADS_DIR=$(prompt "Downloads directory" "/mnt/user/media/downloads/qbittorrent")
MEDIA_TV_DIR=$(prompt "TV shows directory" "/mnt/user/media/tv")
MEDIA_MOVIES_DIR=$(prompt "Movies directory" "/mnt/user/media/movies")

# ── 6. qBittorrent ────────────────────────────────────────────────
section "qBittorrent"
QB_USERNAME=$(prompt "WebUI username" "admin")
QB_PASSWORD=$(prompt_password_required "WebUI password")
BT_PORT=$(prompt "Torrenting port" "51413")

# ── Summary ────────────────────────────────────────────────────────
echo ""
gum style --bold --foreground "$ACCENT" "Review"
gum style --foreground "$MUTED" "$(printf '%.0s─' {1..45})"

gum style --border rounded --padding "1 2" --margin "0 2" \
  --border-foreground "$MUTED" \
  "$(gum style --bold 'Domain')        $DOMAIN_NAME" \
  "$(gum style --bold 'Tailscale IP')  $TAILSCALE_IP" \
  "$(gum style --bold 'CF Email')      $CF_API_EMAIL" \
  "" \
  "$(gum style --bold 'Data dir')      $DATA_DIR" \
  "$(gum style --bold 'Downloads')     $DOWNLOADS_DIR" \
  "$(gum style --bold 'TV dir')        $MEDIA_TV_DIR" \
  "$(gum style --bold 'Movies dir')    $MEDIA_MOVIES_DIR" \
  "" \
  "$(gum style --bold 'QB user')       $QB_USERNAME" \
  "$(gum style --bold 'QB port')       $BT_PORT" \
  "" \
  "$(gum style --faint 'Secrets (CF token, VPN keys, passwords) are hidden.')"

echo ""
if ! gum confirm \
  --prompt.foreground "$ACCENT" \
  --selected.background "$ACCENT" \
  "Write .env and set up?"; then
  gum style --foreground 1 "Aborted."
  exit 0
fi

# ── Write .env ─────────────────────────────────────────────────────
echo ""
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

ok "Wrote $ENV_FILE"

# ── Symlinks ───────────────────────────────────────────────────────
for subdir in arr infra; do
  target="$REPO_DIR/$subdir/.env"
  if [ -L "$target" ]; then
    skip "$subdir/.env already symlinked"
  elif [ -f "$target" ]; then
    warn "$subdir/.env exists as a regular file — remove it manually to use symlink"
  else
    ln -s ../.env "$target"
    ok "Symlinked $subdir/.env → ../.env"
  fi
done

# ── Docker network ─────────────────────────────────────────────────
if docker network inspect traefik_proxy &>/dev/null; then
  skip "traefik_proxy network already exists"
else
  gum spin \
    --spinner dot \
    --spinner.foreground "$ACCENT" \
    --title "Creating traefik_proxy network..." -- \
    docker network create traefik_proxy
  ok "Created traefik_proxy network"
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
gum style \
  --border double --padding "1 3" --margin "0 2" \
  --border-foreground "$OK" --foreground "$OK" --bold \
  "Setup complete!" \
  "" \
  "$(gum style --faint --foreground "$MUTED" 'Start the stack:')" \
  "$(gum style --foreground 7 '  cd infra && docker compose up -d')" \
  "$(gum style --foreground 7 '  cd ../arr && docker compose up -d')"
echo ""
