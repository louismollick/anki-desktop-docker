#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <external_domain> [ankiweb_user] [ankiweb_password]"
  echo "If username/password are omitted, existing ANKIWEB_SYNC_KEY from .env is reused."
  exit 1
fi

EXTERNAL_DOMAIN="$1"
ANKIWEB_USER_INPUT="${2:-}"
ANKIWEB_PASSWORD_INPUT="${3:-}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

load_env_var() {
  local key="$1"
  local env_file="$REPO_DIR/.env"
  if [[ -f "$env_file" ]]; then
    grep -E "^${key}=" "$env_file" | tail -n1 | cut -d= -f2-
  fi
}

install_deps() {
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release openssl python3 python3-pip python3-requests python3-zstandard certbot

  if ! command -v docker >/dev/null 2>&1; then
    sudo install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
      sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi

    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
  fi

  if ! docker compose version >/dev/null 2>&1; then
    sudo apt-get install -y docker-compose-plugin
  fi
}

ensure_docker_access() {
  if docker info >/dev/null 2>&1; then
    DOCKER_BIN=(docker)
  elif sudo docker info >/dev/null 2>&1; then
    DOCKER_BIN=(sudo docker)
  else
    echo "Docker daemon is not accessible"
    exit 1
  fi
}

set_env_var() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" .env; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

request_tls_cert_if_missing() {
  local domain="$1"
  local cert_email="$2"
  local cert_dir="/etc/letsencrypt/live/${domain}"

  if sudo test -f "${cert_dir}/fullchain.pem" && sudo test -f "${cert_dir}/privkey.pem"; then
    echo "Existing Let's Encrypt certificate found for ${domain}; reusing it."
    return 0
  fi

  echo "No existing certificate found for ${domain}; requesting a new Let's Encrypt certificate."
  sudo certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --domain "$domain" \
    --email "$cert_email" \
    --agree-tos \
    --non-interactive \
    --keep-until-expiring
}

EXISTING_ANKIWEB_USER="$(load_env_var ANKIWEB_USER || true)"
EXISTING_SYNC_KEY="$(load_env_var ANKIWEB_SYNC_KEY || true)"
EXISTING_LETSENCRYPT_EMAIL="$(load_env_var LETSENCRYPT_EMAIL || true)"

ANKIWEB_USER_RESOLVED="${ANKIWEB_USER_INPUT:-$EXISTING_ANKIWEB_USER}"
SYNC_KEY="${EXISTING_SYNC_KEY:-}"

if [[ -n "$ANKIWEB_PASSWORD_INPUT" && -z "$ANKIWEB_USER_RESOLVED" ]]; then
  echo "AnkiWeb username is required when providing AnkiWeb password."
  exit 1
fi

install_deps
ensure_docker_access

mkdir -p anki_data nginx/conf.d
sudo mkdir -p /var/www/certbot

python3 -c "import requests, zstandard" >/dev/null 2>&1 || {
  echo "Python dependencies (requests, zstandard) are required but unavailable."
  exit 1
}

if [[ -n "$ANKIWEB_PASSWORD_INPUT" ]]; then
  SYNC_KEY="$(python3 scripts/get_anki_synckey.py --user "$ANKIWEB_USER_RESOLVED" --password "$ANKIWEB_PASSWORD_INPUT")"
  if [[ -z "$SYNC_KEY" ]]; then
    echo "Failed to derive ANKIWEB_SYNC_KEY"
    exit 1
  fi
elif [[ -z "$SYNC_KEY" ]]; then
  echo "No ANKIWEB_SYNC_KEY available. Provide AnkiWeb credentials or pre-populate .env."
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
fi

set_env_var "ANKI_DOMAIN" "$EXTERNAL_DOMAIN"
if [[ -n "$ANKIWEB_USER_RESOLVED" ]]; then
  set_env_var "ANKIWEB_USER" "$ANKIWEB_USER_RESOLVED"
fi
set_env_var "ANKIWEB_SYNC_KEY" "$SYNC_KEY"
set_env_var "ANKIWEB_PASSWORD" ""
set_env_var "ANKI_IMAGE" "ghcr.io/louismollick/anki-desktop-docker:main"
set_env_var "AUTO_SYNC_ON_START" "true"

LETSENCRYPT_EMAIL="${EXISTING_LETSENCRYPT_EMAIL:-}"
if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
  echo "LETSENCRYPT_EMAIL is required in .env"
  exit 1
fi
set_env_var "LETSENCRYPT_EMAIL" "$LETSENCRYPT_EMAIL"

rm -f .env.bak
unset ANKIWEB_PASSWORD_INPUT

# Start with HTTP config for ACME challenge path if no cert exists yet.
bash scripts/render-nginx-config.sh
"${DOCKER_BIN[@]}" compose pull anki-desktop nginx || true
"${DOCKER_BIN[@]}" compose up -d --build

request_tls_cert_if_missing "$EXTERNAL_DOMAIN" "$LETSENCRYPT_EMAIL"

# Re-render config to HTTPS once cert exists and reload nginx.
bash scripts/render-nginx-config.sh
"${DOCKER_BIN[@]}" compose up -d --force-recreate nginx

sudo mkdir -p /etc/systemd/system
sudo cp deploy/systemd/anki-cleanup.service /etc/systemd/system/anki-cleanup.service
sudo cp deploy/systemd/anki-cleanup.timer /etc/systemd/system/anki-cleanup.timer
sudo cp deploy/systemd/anki-sync.service /etc/systemd/system/anki-sync.service
sudo cp deploy/systemd/anki-sync.timer /etc/systemd/system/anki-sync.timer

# Align service paths with current checkout for flexibility.
sudo sed -i "s|%h/anki-desktop-docker|$REPO_DIR|g" /etc/systemd/system/anki-cleanup.service
sudo sed -i "s|%h/anki-desktop-docker|$REPO_DIR|g" /etc/systemd/system/anki-sync.service

sudo systemctl daemon-reload
sudo systemctl enable --now anki-cleanup.timer
sudo systemctl enable --now anki-sync.timer

echo "Bootstrap complete."
echo "VNC UI: https://${EXTERNAL_DOMAIN}/"
echo "AnkiConnect: https://${EXTERNAL_DOMAIN}/api"
echo ""
echo "Smoke tests:"
echo "curl -I https://${EXTERNAL_DOMAIN}/"
echo "curl -sS https://${EXTERNAL_DOMAIN}/api -H 'Content-Type: application/json' -d '{\"action\":\"version\",\"version\":6}'"
