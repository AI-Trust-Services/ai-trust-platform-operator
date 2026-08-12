#!/bin/bash
# Task B — READ-ONLY: probe shoot connectivity, then dump gateway + cert + traefik wiring.
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config

BK=".state/backup-dnscert"
mkdir -p "$BK"

echo "===== CONNECTIVITY PROBE ====="
# Try a lightweight shoot call with a short timeout so we don't hang on interactive login.
if [ ! -s "$SHOOT_KUBECONFIG" ]; then
  echo "No shoot kubeconfig yet — attempting to mint (non-interactive)…"
  # mint uses garden login; if garden token expired this will die with a message.
  timeout 40 bash -c '
    cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
    source scripts/lib.sh; load_config; mint_shoot_kubeconfig
  ' || { echo "PROBE-RESULT: garden login expired — needs prerequisites/login.sh (mint hung/failed)"; exit 7; }
fi

if timeout 30 kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns "$MESH_NS" >/dev/null 2>&1; then
  echo "PROBE-RESULT: shoot reachable"
else
  echo "PROBE-RESULT: shoot NOT reachable (kubeconfig may be stale) — needs prerequisites/login.sh"
  exit 7
fi
