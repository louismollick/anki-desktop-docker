#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$REPO_DIR/nginx/conf.d/anki.conf"

if [[ -f "$REPO_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
  set +a
fi

: "${ANKI_DOMAIN:?ANKI_DOMAIN is required (set in .env)}"

mkdir -p "$(dirname "$OUTPUT")"

HTTP_TEMPLATE="$REPO_DIR/nginx/conf.d/anki.http.conf.template"
HTTPS_TEMPLATE="$REPO_DIR/nginx/conf.d/anki.https.conf.template"
CERT_FULLCHAIN="/etc/letsencrypt/live/${ANKI_DOMAIN}/fullchain.pem"
CERT_PRIVKEY="/etc/letsencrypt/live/${ANKI_DOMAIN}/privkey.pem"

cert_files_exist() {
  if [[ -f "$CERT_FULLCHAIN" && -f "$CERT_PRIVKEY" ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo test -f "$CERT_FULLCHAIN" && sudo test -f "$CERT_PRIVKEY"
    return $?
  fi

  return 1
}

if cert_files_exist; then
  TEMPLATE="$HTTPS_TEMPLATE"
else
  TEMPLATE="$HTTP_TEMPLATE"
fi

awk -v domain="$ANKI_DOMAIN" '
{
  gsub("__ANKI_DOMAIN__", domain)
  print
}
' "$TEMPLATE" > "$OUTPUT"

echo "Wrote nginx config to $OUTPUT (template: $(basename "$TEMPLATE"))"
