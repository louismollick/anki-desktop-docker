#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <external_domain> <ankiweb_user> <ankiweb_password>"
  exit 1
fi

EXTERNAL_DOMAIN="$1"
ANKIWEB_USER_INPUT="$2"
ANKIWEB_PASSWORD_INPUT="$3"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

install_deps() {
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release openssl python3 python3-pip python3-requests python3-zstandard

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

install_deps
ensure_docker_access

mkdir -p anki_data nginx/conf.d

python3 -c "import requests, zstandard" >/dev/null 2>&1 || {
  echo "Python dependencies (requests, zstandard) are required but unavailable."
  exit 1
}

SYNC_KEY="$(python3 scripts/get_anki_synckey.py --user "$ANKIWEB_USER_INPUT" --password "$ANKIWEB_PASSWORD_INPUT")"
if [[ -z "$SYNC_KEY" ]]; then
  echo "Failed to derive ANKIWEB_SYNC_KEY"
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
fi

# Update or append a key=value in .env
set_env_var() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" .env; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env_var "ANKI_DOMAIN" "$EXTERNAL_DOMAIN"
set_env_var "ANKIWEB_USER" "$ANKIWEB_USER_INPUT"
set_env_var "ANKIWEB_SYNC_KEY" "$SYNC_KEY"
set_env_var "ANKIWEB_PASSWORD" ""
set_env_var "ANKI_IMAGE" "ghcr.io/louismollick/anki-desktop-docker:main"
set_env_var "AUTO_SYNC_ON_START" "true"

rm -f .env.bak

# Clear plaintext credentials from shell variables as soon as possible.
unset ANKIWEB_PASSWORD_INPUT

bash scripts/render-nginx-config.sh
"${DOCKER_BIN[@]}" compose pull anki-desktop nginx || true
"${DOCKER_BIN[@]}" compose up -d --build

sudo mkdir -p /etc/systemd/system
sudo cp deploy/systemd/anki-cleanup.service /etc/systemd/system/anki-cleanup.service
sudo cp deploy/systemd/anki-cleanup.timer /etc/systemd/system/anki-cleanup.timer

# Align service paths with current checkout for flexibility.
sudo sed -i "s|%h/anki-desktop-docker|$REPO_DIR|g" /etc/systemd/system/anki-cleanup.service

sudo systemctl daemon-reload
sudo systemctl enable --now anki-cleanup.timer

echo "Bootstrap complete."
echo "VNC UI: http://${EXTERNAL_DOMAIN}/"
echo "AnkiConnect: http://${EXTERNAL_DOMAIN}/api"
echo ""
echo "Smoke tests:"
echo "curl -I http://${EXTERNAL_DOMAIN}/"
echo "curl -sS http://${EXTERNAL_DOMAIN}/api -H 'Content-Type: application/json' -d '{\"action\":\"version\",\"version\":6}'"
