# Anki Desktop in Docker

Run Anki Desktop in Docker with:
- browser-accessible VNC UI via nginx at `http://<domain>/`
- public AnkiConnect API via nginx at `http://<domain>/api`
- automated AnkiWeb setup (using sync key)
- scheduled cleanup restart every 12 hours via systemd timer
- scheduled AnkiWeb sync every 10 minutes via AnkiConnect + on startup

This repository keeps the current automation approach used here:
- automated profile/setup flow via `scripts/setup_anki.py`
- automated AnkiConnect setup on first start

## Image

Canonical image reference used across this repo:

`ghcr.io/louismollick/anki-desktop-docker:main`

## Public Endpoint Contract

With nginx enabled:
- VNC UI: `http://<domain>/`
- AnkiConnect API: `http://<domain>/api`

API requests are proxied from `/api` to the container's internal `8765` endpoint.

## Quick Start (Local/Server)

1. Clone repo:

```bash
git clone https://github.com/louismollick/anki-desktop-docker.git
cd anki-desktop-docker
```

2. Configure env:

```bash
cp .env.example .env
```

Set at minimum:

```env
ANKI_DOMAIN=anki.example.com
ANKIWEB_USER=you@example.com
ANKIWEB_SYNC_KEY=your_sync_key
ANKIWEB_PASSWORD=
ANKI_IMAGE=ghcr.io/louismollick/anki-desktop-docker:main
```

3. Render nginx config and start stack:

```bash
./scripts/render-nginx-config.sh
docker compose up -d --build
```

4. Validate:

```bash
curl -I http://$ANKI_DOMAIN/
curl -sS http://$ANKI_DOMAIN/api \
  -H 'Content-Type: application/json' \
  -d '{"action":"version","version":6}'
```

## One-Shot Bootstrap on Clean Ubuntu VPS

Use:

```bash
./scripts/bootstrap-vps.sh <external_domain> <ankiweb_user> <ankiweb_password>
```

Example:

```bash
./scripts/bootstrap-vps.sh anki.louismollick.com louismollick@gmail.com 'your-password'
```

What it does:
- installs Docker + Compose dependencies if missing
- derives `ANKIWEB_SYNC_KEY` from username/password
- writes `.env` with domain, username, sync key, and GHCR image
- clears plaintext password from shell variables
- renders nginx config
- starts containers
- installs/enables a 12-hour cleanup systemd timer
- installs/enables a 10-minute AnkiWeb sync systemd timer

Password handling:
- password is used only to derive sync key
- password is not persisted to `.env`
- `.env` stores `ANKIWEB_SYNC_KEY`

## Cleanup Every 12 Hours

Files:
- `scripts/cleanup-restart.sh`
- `deploy/systemd/anki-cleanup.service`
- `deploy/systemd/anki-cleanup.timer`

Install timer manually (if you do not use bootstrap script):

```bash
sudo cp deploy/systemd/anki-cleanup.service /etc/systemd/system/
sudo cp deploy/systemd/anki-cleanup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now anki-cleanup.timer
```

Check status:

```bash
systemctl status anki-cleanup.timer
```

Run once manually:

```bash
sudo systemctl start anki-cleanup.service
```

## Scheduled Sync

Sync behavior:
- Startup sync is triggered from container startup when `AUTO_SYNC_ON_START=true`
- Periodic sync runs every 10 minutes via systemd timer

Files:
- `scripts/sync-now.sh`
- `deploy/systemd/anki-sync.service`
- `deploy/systemd/anki-sync.timer`

Install manually (if you do not use bootstrap script):

```bash
sudo cp deploy/systemd/anki-sync.service /etc/systemd/system/
sudo cp deploy/systemd/anki-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now anki-sync.timer
```

Check status:

```bash
systemctl status anki-sync.timer
```

Run once manually:

```bash
sudo systemctl start anki-sync.service
```

## Getting an Anki Sync Key

Use the included helper:

```bash
./get_sync_key.sh your-email@example.com your-password
```

Or directly via Docker:

```bash
docker run --rm ghcr.io/louismollick/anki-desktop-docker:main \
  python3 /app/scripts/get_anki_synckey.py \
  --user your-email@example.com \
  --password your-password
```

## Docker Compose Services

- `anki-desktop` (internal ports only): `3000`, `8765`
- `nginx` (public): `80`

`anki-desktop` is not directly published on host ports by default.

## Notes

- This deployment is intentionally HTTP-only in current setup.
- Ensure DNS for `ANKI_DOMAIN` points to your VPS.
- Ensure VPS firewall/security lists allow inbound TCP `80`.
