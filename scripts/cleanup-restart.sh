#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

docker compose restart anki-desktop
sleep 10

response="$(docker compose exec -T anki-desktop curl -fsS -m 20 localhost:8765 -X POST -d '{"action":"version","version":6}' || true)"
if [[ -z "$response" ]]; then
  echo "cleanup restart failed healthcheck"
  exit 1
fi

echo "cleanup restart completed: $response"
