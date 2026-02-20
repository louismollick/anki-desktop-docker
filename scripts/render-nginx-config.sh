#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_DIR/nginx/conf.d/anki.http.conf.template"
OUTPUT="$REPO_DIR/nginx/conf.d/anki.conf"

if [[ -f "$REPO_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
  set +a
fi

: "${ANKI_DOMAIN:?ANKI_DOMAIN is required (set in .env)}"

mkdir -p "$(dirname "$OUTPUT")"

awk -v domain="$ANKI_DOMAIN" '
{
  gsub("__ANKI_DOMAIN__", domain)
  print
}
' "$TEMPLATE" > "$OUTPUT"

echo "Wrote nginx config to $OUTPUT"
