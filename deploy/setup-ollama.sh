#!/usr/bin/env bash
# Runs ON the server as root: installs Ollama and the model the AI text feature uses. Safe to run again.
# Usage from your Mac:  ssh root@<server-ip> 'bash -s' < deploy/setup-ollama.sh
# The model answers only to this server (127.0.0.1), never to the internet.
set -euo pipefail
MODEL="${AI_MODEL:-qwen2.5:3b}"

command -v ollama >/dev/null || curl -fsSL https://ollama.com/install.sh | sh

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/financegotchi.conf <<CONF
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Nice=10
CONF
systemctl daemon-reload
systemctl enable ollama >/dev/null
systemctl restart ollama
sleep 3

ollama pull "$MODEL"
# Load it now so the first real request isn't slow.
ollama run "$MODEL" "hi" --keepalive 24h >/dev/null 2>&1 || true

echo "listening on: $(ss -ltn | grep 11434 | awk '{print $4}')   (must be 127.0.0.1 only)"
ollama list
