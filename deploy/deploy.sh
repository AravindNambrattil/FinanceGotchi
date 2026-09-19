#!/usr/bin/env bash
# Usage:  deploy/deploy.sh <server-ip> [https-hostname]
# Copies files/ + deploy/ to the server, then runs remote-setup.sh there.
# Never overwrites the server's financegotchi.db or .env.
set -euo pipefail
HOST="${1:?usage: deploy/deploy.sh <server-ip> [https-hostname]}"
SITE="${2:-$(echo "$HOST" | tr . -).sslip.io}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH="ssh -o BatchMode=yes"

echo "Deploying to $HOST as https://$SITE"
$SSH "root@$HOST" 'mkdir -p /opt/financegotchi/app /opt/financegotchi/deploy'
rsync -az -e "$SSH" \
  --exclude '.env' --exclude '*.db' --exclude '*.db-*' --exclude '__pycache__' --exclude 'venv' --exclude '.DS_Store' \
  "$ROOT/files/" "root@$HOST:/opt/financegotchi/app/"
rsync -az -e "$SSH" --exclude '.DS_Store' "$ROOT/deploy/" "root@$HOST:/opt/financegotchi/deploy/"
$SSH "root@$HOST" "SITE_HOST=$SITE bash -s" < "$ROOT/deploy/remote-setup.sh"
echo "Try:  curl https://$SITE/pets/mochi"
