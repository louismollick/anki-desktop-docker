#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

response=""
for _ in $(seq 1 12); do
  response="$(docker compose exec -T anki-desktop sh -lc '
    API_KEY="${ANKICONNECT_API_KEY:-}"
    if [ -n "$API_KEY" ]; then
      curl -fsS -m 20 localhost:8765 -X POST -d "{\"action\":\"sync\",\"version\":6,\"key\":\"$API_KEY\"}"
    else
      curl -fsS -m 20 localhost:8765 -X POST -d "{\"action\":\"sync\",\"version\":6}"
    fi
  ' || true)"

  if [[ -n "$response" ]]; then
    echo "sync completed: $response"
    exit 0
  fi

  sleep 10
done

echo "sync failed after retries"
exit 1
