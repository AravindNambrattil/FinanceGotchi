#!/usr/bin/env bash
# Runs ON the server as root (deploy.sh sends it over SSH). Safe to run again.
# Requires SITE_HOST in the environment, e.g. SITE_HOST=66-42-93-22.sslip.io
set -euo pipefail
: "${SITE_HOST:?set SITE_HOST}"
export DEBIAN_FRONTEND=noninteractive
BASE=/opt/financegotchi
APP=$BASE/app

echo "==> packages"
apt-get update -y
apt-get install -y python3-venv python3-pip caddy ufw sqlite3

echo "==> service user + folders"
id -u financegotchi >/dev/null 2>&1 || useradd --system --home "$BASE" --shell /usr/sbin/nologin financegotchi
mkdir -p "$APP" "$BASE/backups"

echo "==> python environment"
[ -d "$BASE/venv" ] || python3 -m venv "$BASE/venv"
"$BASE/venv/bin/pip" install --quiet --upgrade pip
"$BASE/venv/bin/pip" install --quiet -r "$APP/requirements.txt"

echo "==> permissions"
chown -R financegotchi:financegotchi "$BASE"
[ -f "$APP/.env" ] && chmod 600 "$APP/.env" || echo "   (no .env yet: Nessie stays off until it exists)"

echo "==> systemd service"
install -m 644 "$BASE/deploy/financegotchi.service" /etc/systemd/system/financegotchi.service
systemctl daemon-reload
systemctl enable financegotchi >/dev/null
systemctl restart financegotchi

echo "==> Caddy (HTTPS for $SITE_HOST)"
sed "s/__SITE__/$SITE_HOST/" "$BASE/deploy/Caddyfile.template" > /etc/caddy/Caddyfile
systemctl enable caddy >/dev/null
systemctl restart caddy

echo "==> nightly database copy (keeps 14 days)"
cat > /etc/cron.d/financegotchi-backup <<CRON
0 3 * * * financegotchi sqlite3 $APP/financegotchi.db ".backup '$BASE/backups/fg-\$(date +\%F).db'" && find $BASE/backups -name 'fg-*.db' -mtime +14 -delete
CRON
chmod 644 /etc/cron.d/financegotchi-backup

echo "==> firewall (SSH first so we can't lock ourselves out)"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

echo "==> done"
systemctl --no-pager --lines=0 status financegotchi caddy | grep -E "Active:|●" || true
